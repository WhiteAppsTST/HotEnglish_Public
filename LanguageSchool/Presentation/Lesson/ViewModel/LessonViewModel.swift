import Foundation
import SwiftUI

@MainActor
@Observable
final class LessonViewModel {

    // MARK: - Config

    /// Сессионный лимит на step: 10 минут. Юзер может пройти быстрее, но не
    /// дольше. После 10:00 таймер стопается — что с этим делать (auto-complete /
    /// paywall / retry) решим когда backend подтянем.
    /// TODO: логика cutoff при истечении.
    static let sessionMaxSeconds: Int = 10 * 60

    /// Кол-во бесплатных подсказок на step.
    /// TODO: подцепить настоящий hint-quota сервис (Keychain + 24ч окно?
    /// per-step или per-day — ждём продуктового решения).
    static let hintsPerStep: Int = 3

    // MARK: - Deps

    let unitId: String
    let step: Step
    let teacher: TeacherProfile
    let language: LanguageCode
    let user: UserEntity
    let speech: SpeechDictationService
    let network: NetworkMonitor

    // MARK: - Session

    /// UUID сессии — генерится один раз в init. Идемпотентный ключ: повтор
    /// того же UUID вернёт ту же попытку (дока говорит).
    let sessionAttemptId: UUID = UUID()
    /// Момент старта — считаем `durationSeconds` при финише.
    private var sessionStartedAt: Date?
    /// Ответ сервера на `POST /session-attempts` (в нём — `remainingLessons`,
    /// `resetsAt` — для UI-баннеров). nil пока не пришёл ответ.
    var sessionStart: SessionStartResponseDTO?
    /// Ответ сервера на `PATCH .../{id}` — прогресс с `heartWon` и стриком.
    var sessionFinish: SessionFinishResponseDTO?
    /// Что делать view если сервер отказал в старте. View подписывается через
    /// `.onChange` и выполняет побочный эффект (paywall / dismiss / alert).
    var sessionAbort: SessionAbort?
    /// Идёт ли сейчас старт сессии — блокирует UI пока не пришёл ответ.
    var isStartingSession: Bool = false

    enum SessionAbort: Hashable, Sendable {
        /// 402 — юзеру не хватает подписки. View → `.in_lessons` paywall + dismiss.
        case paywallRequired
        /// 409 — шаг закрыт или попытка уже завершена. View → syncMe + dismiss.
        case stepConflict
        /// 429 — дневная квота исчерпана. View → показать `resetsAt`, dismiss.
        case quotaExhausted(resetsAt: Date?)
    }

    /// Единая анимация для всех переходов между `InputMode` — 373:2077 / 4741 /
    /// 4831 / 4129 и обратно. По просьбе пользователя: линейно 0.33s.
    private static let modeTransition: Animation = .linear(duration: 0.33)

    var error: String?

    // MARK: - Observable state

    var messages: [LessonMessage] = []
    var inputText: String = ""

    /// Последний score от бэка/GPT для последнего голосового ответа юзера.
    /// Если не nil — тап на Hint открывает score-sheet (Figma 373:2263), а не
    /// обычный «Need a hint?».
    /// TODO: подцепить реальный API POST /content/score.
    var lastScore: PronunciationScore?

    /// Флаг открытия score-sheet (Figma 373:2263).
    var showScoreSheet: Bool = false

    /// Ключевые фразы (Figma 373:2487). Для `.lecture` payload — заполняются
    /// только после того, как показан последний turn (в `advanceLecture`).
    /// Для `.topicWords` / `.pattern` — сразу при `populate`.
    var keyPhrases: [KeyPhrase] = []

    /// Pattern-примеры (Figma 373:2487). Правило то же, что и keyPhrases.
    var patterns: [PatternExample] = []

    /// Полный набор keyPhrases/patterns из `.lecture` payload — отложен до
    /// конца лекции. `.topicWords` / `.pattern` пишут напрямую в `keyPhrases`/
    /// `patterns` и `pending*` не трогают.
    var pendingKeyPhrases: [KeyPhrase] = []
    var pendingPatterns: [PatternExample] = []

    /// Все turns лекции показаны. Триггер рендера кнопки «Finish lesson».
    var isLectureFinished: Bool {
        !allLectureTurns.isEmpty && lectureCursor >= allLectureTurns.count
    }

    /// Ошибка обработки последней записи голоса. Отображается вверху чата над
    /// bottom-bar-ом (Figma 373:4511). `nil` — ошибки нет.
    /// TODO: биндить к реальной оценке транскрипта от бэка/GPT.
    var voiceError: VoiceError?

    /// Длительность последней записи для waveform-бабла.
    /// TODO: биндить к AVAudioRecorder.currentTime.
    var lastRecordingDuration: TimeInterval = 2

    /// Для .wordOrder вопросов: слова, которые юзер выбрал (в порядке выбора).
    /// Ключ — id вопроса, значение — массив выбранных слов.
    var wordOrderSelections: [String: [String]] = [:]

    /// DEBUG-флаг чтобы форсировать offline-стейт даже когда есть сеть
    /// (для отладки макета 373:4639). Убрать перед прод-релизом.
    var debugForceOffline: Bool = false

    /// Показывать offline-banner. True если сеть отсутствует ИЛИ выставлен
    /// debug-флаг. TODO: расширить: считать offline при N подряд AI-ошибках
    /// сети (задача из ответов пользователя: «и реальный мониторинг сети и
    /// ошибки нейронки»).
    var isOffline: Bool {
        debugForceOffline || !network.isOnline
    }
    /// Дефолт — 3-кнопочный ряд (Text · Speak · Hint), как на макете 373:2077.
    var inputMode: InputMode = .buttons
    var phase: LessonPhase = .lecture
    var isFullscreen: Bool = false

    // MARK: - Avatar reactions (bridge for view-side AvatarPlayer)

    /// Реакция учителя на последний user-action (правильный/неправильный ответ).
    /// View подписывается через `.onChange(reactionTick)` и триггерит
    /// `AvatarPlayer.playOnce(video: teacher.lessonVideo(state))`.
    var lastReaction: LessonReaction?
    /// Счётчик — чтобы одинаковые reaction'ы подряд тоже вызывали проигрыш.
    var reactionTick: Int = 0

    func triggerReaction(_ reaction: LessonReaction) {
        lastReaction = reaction
        reactionTick &+= 1
    }

    /// URL аудио-озвучки текущего вопроса (учительница «читает» задание вслух).
    /// TODO: сейчас всегда nil — когда бэк начнёт отдавать `audioURL` в
    /// `PracticeQuestion`, этот геттер вернёт ссылку, и view'ха проиграет её
    /// через `AvatarPlayer.playOnce(video: talking, audio: url)` при появлении
    /// нового вопроса на экране.
    func currentQuestionAudioURL() -> URL? { nil }
    var showHintSheet: Bool = false

    /// Подсказки к репликам учительницы: turnId → «что можно ответить».
    /// Строится при разборе `LecturePayload.turns[].userReply`.
    var suggestedReplyByTurnId: [String: String] = [:]

    /// URL озвучки каждой лекторской реплики (turnId → audioUrl).
    var audioUrlByMessageId: [String: URL] = [:]

    /// Кэш ВИДИМОГО перевода реплики: messageId → текст, который сейчас
    /// показан под баблом. Заполняется только тапом на translate-иконку
    /// (см. `toggleTranslation(for:)`) — раньше сюда пушился ещё серверный
    /// `translation` из `chat-turn` / `openingLine`, но бэк периодически
    /// возвращает translation == оригинал (или на том же языке), что
    /// показывалось юзеру как «перевод фейковый». Теперь UI рисует перевод
    /// только по тапу.
    var translations: [String: String] = [:]
    /// Серверный кандидат перевода (из `chat-turn.translation` или
    /// `openingLine.translation`). Держим отдельно и используем при первом
    /// тапе на translate-иконку — если он осмысленный (не пустой и не
    /// совпадает с оригиналом). Иначе фолбэк на GPT-перевод.
    var serverTranslations: [String: String] = [:]
    /// Идёт ли сейчас перевод конкретной реплики — блокирует повторный тап.
    var translatingIds: Set<String> = []

    /// AI-клиент для перевода (GPT напрямую с клиента). Не путать с
    /// серверным `/ai/chat-turn` — тот пойдёт под evaluate-reply/date.
    private let aiChat: AIChatServicing? = try? AIChatService()

    /// Плеер для проигрывания серверного `audioUrl` из лекторских реплик.
    let remoteAudio = PlaybackService()

    /// id реплики, которая сейчас проигрывается (для UI-состояния кнопки Play).
    var playingMessageId: String?

    /// Все turns лекции с сервера. Пришли — но не все показаны разом:
    /// прогрессия по одной за ответ / тап next. Хранятся для `advanceLecture`.
    var allLectureTurns: [LectureTurnDTO] = []
    /// Индекс следующего turn'а которого ещё нет в `messages`.
    var lectureCursor: Int = 0

    // MARK: - Speaking free-chat fallback

    /// Максимум обменов юзер↔учитель для speaking-степа в free-chat режиме.
    /// N user-реплик → N teacher-ответов через GPT, потом Finish.
    static let speakingFreeChatExchanges = 6

    /// Speaking-степ без серверных turns → ведём диалог через локальный GPT.
    var isSpeakingFreeChatMode: Bool = false
    /// Сценарий из `payload.scenario` — используется как контекст в system-
    /// prompt каждого GPT-запроса, чтобы учитель не уходил с темы.
    var speakingScenario: String = ""
    /// Сколько user-реплик уже отправлено в GPT. По достижении
    /// `speakingFreeChatExchanges` — Finish разблокируется.
    var speakingExchangeCount: Int = 0
    /// Guard против двойных тапов Send пока GPT-запрос в полёте.
    var isSpeakingReplyInFlight: Bool = false

    // MARK: - Date free-chat fallback

    /// Максимум обменов юзер↔учитель для date-шага в free-chat режиме.
    static let dateFreeChatExchanges = 8

    /// Date-шаг ведём диалог через клиентский GPT (сервер `/ai/chat-turn`
    /// в песочнице режет 402 для локально-платящих юзеров и вообще нестабилен
    /// на текущей интеграции; клиентский GPT работает всегда).
    var isDateFreeChatMode: Bool = false
    /// Поля из `payload` (topic/context/goal) — используются как контекст в
    /// system-prompt каждого GPT-запроса, чтобы учитель не уходил со сцены.
    var dateTopic: String = ""
    var dateContext: String = ""
    var dateGoal: String = ""
    /// Сколько user-реплик уже отправлено в GPT. По достижении
    /// `dateFreeChatExchanges` — Finish разблокируется, GPT финиширует
    /// беседу closing-репликой (см. `dateLessonSystemPrompt`).
    var dateExchangeCount: Int = 0

    /// Аудио-URL слов из `LecturePayload.words[]` — для play на key phrase.
    var audioUrlByWordId: [String: URL] = [:]

    /// Глобальная квота подсказок (3/24h). Общая между уроками для free,
    /// байпасится для premium. Через `hintsRemaining` пробрасывается в UI.
    let hintQuota: HintQuotaService

    /// Единственный источник правды по премиуму на клиенте —
    /// `SubscriptionService` (Apphud + серверный webhook). Поле
    /// `user.isPremium` (mirror с /me) НЕ используется как гейт: оно
    /// отстаёт от Apphud сразу после покупки. Все гейты в уроке
    /// (voice, hints, paywall-триггеры) читают этот один флаг.
    var isPremium: Bool { SubscriptionService.shared.isActiveSubscription }

    /// Сколько подсказок осталось. Для premium — всегда `hintsPerStep`
    /// (визуальная максималка), лимитом не гейтится.
    var hintsRemaining: Int {
        isPremium ? Self.hintsPerStep : hintQuota.remaining
    }

    // MARK: - Autoplay guard

    /// id первой реплики, для которой нужно сыграть autoplay после того как
    /// вью реально появится на экране. Устанавливается в `populate` (init),
    /// потребляется единожды в `startAutoplayIfNeeded()` из `.task` LessonView.
    var pendingInitialAutoplayId: String?
    /// Флаг «уже сработал» — защита от повторного тика из-за re-onAppear
    /// (переход в фон / возврат из sheet / rebuild навигации).
    private var didConsumeInitialAutoplay: Bool = false

    /// Вызывается один раз из LessonView.task при появлении экрана.
    /// Синхронизирует «первый autoplay» с реальным open, а не с init'ом VM
    /// (иначе NavigationLink проигрывает аудио ещё на Home, до перехода).
    /// Если у сообщения нет `audioUrl` (клиентский opener speaking-free-chat) —
    /// сперва добираем озвучку через `/v1/ai/tts`, потом играем.
    func startAutoplayIfNeeded() {
        guard !didConsumeInitialAutoplay, let id = pendingInitialAutoplayId else { return }
        didConsumeInitialAutoplay = true
        pendingInitialAutoplayId = nil
        Task { [weak self] in
            guard let self else { return }
            if self.audioUrlByMessageId[id] == nil,
               let text = self.messages.first(where: { $0.id == id })?.text,
               let url = await self.requestTTS(text: text) {
                self.audioUrlByMessageId[id] = url
            }
            await self.autoplayIfEnabled(messageId: id)
        }
    }

    // MARK: - Date step (POST /v1/ai/chat-turn)

    /// Идёт запрос к `/ai/chat-turn`. Блокирует повторные отправки.
    var isDateTurnPending: Bool = false
    /// Сервер сказал `shouldEnd: true` — прекратить дальше слать `chat-turn`.
    var dateShouldEnd: Bool = false
    /// Лимит `DatePayload.maxDurationSeconds` — насильно завершаем свидание
    /// когда сервер вернёт `elapsedSeconds >= maxDuration`.
    var dateMaxDurationSeconds: Int?
    var dateMinDurationSeconds: Int?

    /// Секунды с начала сессии. Тикает раз в секунду через LessonView-таймер.
    var elapsedSeconds: Int = 0

    /// Уровень отношений в контексте этого урока (Lvl 1..5).
    /// Обновляется из `ProgressDelta.teacherHearts` в `applyProgressDelta`.
    var affinityLevel: Int = 1
    var heartsFilled: Int = 1
    /// Средний скор из последнего `ProgressDelta.averageScore` — для показа в score sheet.
    var lastAverageScore: Int?
    /// Финальная оценка урока с `POST /v1/ai/evaluate-session` (score/communicationScore/highlights/suggestions).
    var sessionEvaluation: EvaluateSessionDTO?

    /// Прогресс внутри Lecture-фазы (сколько под-табов пройдено / всего).
    /// В макете 8 сегментов. TODO: тянуть с backend'а вместе с контентом урока.
    var lectureProgressCurrent: Int = 1
    var lectureProgressTotal: Int = 8

    // MARK: - Practice state

    /// Список Practice-вопросов текущего step. Заполняется при первом входе в
    /// Practice-фазу. TODO: заменить моки на fetch с бэка.
    var practiceQuestions: [PracticeQuestion] = []

    /// Chat-like стрим Practice: вопросы + feedback. Растёт вниз по мере
    /// прохождения. Скроллим к последнему добавленному.
    var practiceStream: [PracticeStreamItem] = []

    /// Пары (questionId → id выбранной опции). После ответа вопрос
    /// становится read-only, юзер не может перевыбрать.
    var practiceAnswers: [String: String] = [:]

    /// Всего пройденных (отвеченных) вопросов. Заполняет сегменты прогресс-бара.
    var practiceAnsweredCount: Int { practiceAnswers.count }

    // MARK: - Init

    init(unitId: String, step: Step, teacher: TeacherProfile, language: LanguageCode, user: UserEntity, hintQuota: HintQuotaService? = nil) {
        self.unitId = unitId
        self.step = step
        self.teacher = teacher
        self.language = language
        self.user = user
        self.hintQuota = hintQuota ?? HintQuotaService()
        self.speech = SpeechDictationService()
        self.network = NetworkMonitor()

        // Только реальные данные из `step.payload`. Без payload'а — пустой
        // экран (нет моков). Home всё равно не даст открыть шаг без контента,
        // но защита от случайного показа муляжа лишней не будет.
        if let payload = step.payload {
            populate(from: payload, kind: step.kind, language: language)
        } else {
            phase = .lecture
        }
    }

    // MARK: - Payload → view state

    /// Раскладывает `StepPayloadDTO` по стейту вью-модели.
    private func populate(from payload: StepPayloadDTO, kind: StepKind, language: LanguageCode) {
        switch payload {
        case .lecture(let p):
            // Реальный урок — по одной реплике за раз. Все turns складываем в
            // `allLectureTurns`; в `messages` только первый. Юзер отвечает /
            // тапает next → `advanceLecture()` дольёт следующий.
            allLectureTurns = p.turns
            pendingKeyPhrases = p.words.map {
                KeyPhrase(
                    id: $0.id, native: $0.text, translation: $0.translation,
                    audioName: nil, audioUrl: $0.audioUrl.flatMap(URL.init(string:))
                )
            }
            pendingPatterns = [makePatternExample(from: p.pattern)]
            for turn in p.turns {
                if let reply = turn.userReply, !reply.isEmpty {
                    suggestedReplyByTurnId[turn.id] = reply
                }
                if let url = turn.audioUrl.flatMap(URL.init(string:)) {
                    audioUrlByMessageId[turn.id] = url
                }
            }
            if let first = p.turns.first {
                messages = [LessonMessage(id: first.id, role: .assistant, text: first.teacherText, hintUsed: false)]
                lectureCursor = 1
                // Автовоспроизведение первой реплики (если включено в настройках).
                pendingInitialAutoplayId = first.id
            }
            lectureProgressTotal = max(1, p.turns.count)
            phase = .lecture

        case .topicWords(let p):
            keyPhrases = p.words.map {
                KeyPhrase(id: $0.id, native: $0.text, translation: $0.translation, audioName: nil)
            }
            phase = .lecture

        case .pattern(let p):
            patterns = [makePatternExample(from: p)]
            phase = .lecture

        case .grammar(let p):
            practiceQuestions = p.exercises.enumerated().map { i, ex in
                makeGrammarQuestion(from: ex, index: i + 1, total: p.exercises.count)
            }
            if let first = practiceQuestions.first {
                practiceStream = [.question(first)]
            }
            phase = .practice

        case .speaking(let p):
            // Speaking-шаг («Use it with Emma»): сервер даёт сценарий
            // (инструкцию) + два массива turns — lecture-примеры и practice-
            // подсказки. Раньше мы только клали lecture-turns в `messages`
            // и не заполняли `allLectureTurns`, из-за чего `advanceLecture()`
            // после user-реплики не приложил следующий тёрн, а
            // `isLectureFinished` не тригерил Finish-кнопку → юзер стоял
            // после первого ответа без выхода.
            //
            // Теперь: сценарий всегда идёт первым assistant-баблом
            // (инструкция «что делать»), lecture-примеры показываются сразу
            // за ним, practice-turns кладём в `allLectureTurns` — их будем
            // раскрывать по одному по мере ответов юзера через
            // `advanceLecture()`. `canFinishLesson` для speaking допускает
            // финиш когда все practice-turns прошли ИЛИ юзер уже ответил
            // хотя бы раз (страховка для степов без practice-turns).
            var intro: [LessonMessage] = []
            if !p.scenario.isEmpty {
                intro.append(LessonMessage(
                    id: "\(step.id)_scenario",
                    role: .assistant,
                    text: p.scenario,
                    hintUsed: false
                ))
            }
            let lectureTurns = p.phases.lecture.turns ?? []
            for turn in lectureTurns {
                intro.append(LessonMessage(
                    id: turn.id, role: .assistant, text: turn.teacherText, hintUsed: false
                ))
                if let url = turn.audioUrl.flatMap(URL.init(string:)) {
                    audioUrlByMessageId[turn.id] = url
                }
                if let reply = turn.userReply, !reply.isEmpty {
                    suggestedReplyByTurnId[turn.id] = reply
                }
            }
            let practiceTurns = p.phases.practice.turns ?? []
            allLectureTurns = practiceTurns
            for turn in practiceTurns {
                if let url = turn.audioUrl.flatMap(URL.init(string:)) {
                    audioUrlByMessageId[turn.id] = url
                }
                if let reply = turn.userReply, !reply.isEmpty {
                    suggestedReplyByTurnId[turn.id] = reply
                }
            }
            // Fallback-режим для speaking-степов, где сервер прислал ТОЛЬКО
            // сценарий (пустые `phases.lecture.turns` и `.practice.turns`).
            // На весь каталог сейчас все 20/20 speaking-степов такие. Без
            // fallback'a урок вырождается в «одна teacher-фраза → любой
            // ответ → Finish». Проводим короткий диалог через клиентский
            // AIChatService (GPT), учитель ведёт беседу строго в контексте
            // сценария; после N экчейнджей — финиш.
            let hasServerTurns = !lectureTurns.isEmpty || !practiceTurns.isEmpty
            if !hasServerTurns, !p.scenario.isEmpty, aiChat != nil {
                speakingScenario = p.scenario
                isSpeakingFreeChatMode = true
                speakingExchangeCount = 0
                // В free-chat режиме сценарий уходит ТОЛЬКО в system-prompt
                // GPT (см. `speakingLessonSystemPrompt(scenario:…)`). В чате
                // юзеру его дублировать не надо — сценарий бэк часто шлёт
                // на родном языке студента, и рядом с target-language opener
                // это выглядит как «два языка в одном чате». Убираем scenario-
                // бабл, оставляем только opener на target-language.
                intro.removeAll { $0.id == "\(step.id)_scenario" }
                // Вводная реплика учительницы, она открывает диалог первым
                // вопросом, чтобы юзер понимал что от него ждут ответа.
                let openerId = "\(step.id)_speaking_opener"
                let openerText = L10n.tr(
                    "lesson.speaking.opener",
                    "Let's practice this in %@. I'll ask you a few short questions — reply naturally.",
                    language.displayTitle
                )
                intro.append(LessonMessage(
                    id: openerId,
                    role: .assistant,
                    text: openerText,
                    hintUsed: false
                ))
                // Opener — клиентский текст, у него нет `audioUrl` из
                // контента. Не запускаем TTS/autoplay здесь — populate
                // вызывается при init VM, а NavigationLink инициализирует
                // destination-экран eagerly (ещё на Home). Помечаем opener
                // как pending-autoplay; `startAutoplayIfNeeded()` из
                // `.task` LessonView лениво дёрнет TTS и сыграет ровно
                // когда экран урока реально появится.
                pendingInitialAutoplayId = openerId
                lectureProgressTotal = max(1, Self.speakingFreeChatExchanges)
            } else {
                isSpeakingFreeChatMode = false
                lectureProgressTotal = max(1, intro.count + practiceTurns.count)
            }
            messages = intro
            lectureCursor = 0
            phase = .lecture

        case .date(let p):
            let openingId = "\(step.id)_opening"
            messages = [LessonMessage(
                id: openingId,
                role: .assistant,
                text: p.openingLine.text,
                hintUsed: false
            )]
            if let translation = p.openingLine.translation, !translation.isEmpty {
                serverTranslations[openingId] = translation
            }
            if let audioURL = p.openingLine.audioUrl.flatMap(URL.init(string:)) {
                audioUrlByMessageId[openingId] = audioURL
            }
            pendingInitialAutoplayId = openingId
            dateMinDurationSeconds = p.minDurationSeconds
            dateMaxDurationSeconds = p.maxDurationSeconds
            // Client-side free-chat: сервер `/ai/chat-turn` в песочнице
            // режет 402 (плюс сама интеграция нестабильна), поэтому ведём
            // date-диалог локально через GPT в контексте topic/context/goal.
            // После `dateFreeChatExchanges` ответов Finish разблокируется,
            // GPT финиширует closing-репликой.
            if aiChat != nil {
                dateTopic = p.topic
                dateContext = p.context ?? ""
                dateGoal = p.goal
                dateExchangeCount = 0
                isDateFreeChatMode = true
                lectureProgressTotal = max(1, Self.dateFreeChatExchanges)
            } else {
                isDateFreeChatMode = false
            }
            phase = .lecture

        case .unknown:
            phase = .lecture
        }
    }

    private func makePatternExample(from dto: PatternPayloadDTO) -> PatternExample {
        let examples = dto.examples.enumerated().map { i, ex -> PatternExample.Example in
            let prefix = highlightPrefix(from: dto.formula, in: ex.text)
            return PatternExample.Example(
                id: "\(step.id)_ex\(i)",
                text: ex.text,
                highlightPrefix: prefix,
                translation: ex.translation,
                audioName: nil,
                audioUrl: ex.audioUrl.flatMap(URL.init(string:))
            )
        }
        return PatternExample(id: step.id, formula: dto.formula, examples: examples)
    }

    /// Пытаемся взять префикс до "+" из формулы (`me gustaría + infinitive`),
    /// проверяем что он есть в начале текста примера. Если не подходит —
    /// возвращаем пустую строку (highlight выключен для этого примера).
    private func highlightPrefix(from formula: String, in text: String) -> String {
        let head = formula
            .split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return text.lowercased().hasPrefix(head.lowercased()) ? head : ""
    }

    private func makeGrammarQuestion(
        from ex: GrammarExerciseDTO,
        index: Int,
        total: Int
    ) -> PracticeQuestion {
        // Word bank для .wordOrder — все ожидаемые слова + дистракторы.
        let bank = (ex.expected + (ex.distractors ?? [])).shuffled()

        // MCQ-опции для .fillBlank / .listenChoose. Первое `expected` —
        // правильный ответ; остальные expected + distractors — distractors.
        // Летер A/B/C/D. correctOptionId привязан к правильному ответу.
        let kind = mapPresentation(ex.presentation)
        var options: [PracticeOption] = []
        var correctOptionId = ""
        var renderedPrompt = ex.prompt
        var instructionText: String? = nil

        // Разные механики — разная сборка опций.
        // fillBlank: prompt — полное предложение, вырезаем случайное слово,
        //   опции = вырезанное + другие значимые слова того же предложения.
        // listenChoose: аудио проговаривает целую фразу, опции — ПОЛНЫЕ
        //   фразы (правильный ответ + distractors с сервера). Ни в коем
        //   случае не разбираем на слова.
        if kind == .fillBlank {
            let sentence = ex.prompt
            let (blanked, removedWord) = removeRandomWord(from: sentence)
            renderedPrompt = blanked
            let correctText = removedWord ?? (ex.expected.first ?? "")
            let siblingWords = significantWords(in: sentence).filter { $0 != correctText }
            let serverExtras = Array(ex.expected.dropFirst()) + (ex.distractors ?? [])
            var distractors = Array((siblingWords + serverExtras).prefix(3))
            distractors = Array(NSOrderedSet(array: distractors)) as? [String] ?? distractors
            var pool: [String] = ([correctText] + distractors).filter { !$0.isEmpty }
            if pool.isEmpty { pool = [correctText] }
            pool = Array(NSOrderedSet(array: pool)) as? [String] ?? pool
            pool.shuffle()
            let labels = ["A", "B", "C", "D"]
            options = pool.enumerated().map { i, text in
                let id = "\(ex.id)_opt_\(i)"
                if text == correctText { correctOptionId = id }
                let label = i < labels.count ? labels[i] : "\(i + 1)"
                return PracticeOption(id: id, label: label, text: text)
            }
            instructionText = L10n.tr("practice.fillblank.task", "Fill in the blank")
        } else if kind == .listenChoose {
            // Правильная фраза = ПОЛНОЕ prompt-предложение (то, что говорит
            // teacher в аудио). Distractors — то что сервер прислал в
            // `distractors`; если пусто — падаем на другие `expected`.
            let correctText = ex.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            var distractors = (ex.distractors ?? []) + Array(ex.expected.dropFirst())
            distractors = distractors
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != correctText }
            distractors = Array(NSOrderedSet(array: distractors)) as? [String] ?? distractors
            distractors = Array(distractors.prefix(3))
            var pool: [String] = ([correctText] + distractors).filter { !$0.isEmpty }
            pool = Array(NSOrderedSet(array: pool)) as? [String] ?? pool
            pool.shuffle()
            let labels = ["A", "B", "C", "D"]
            options = pool.enumerated().map { i, text in
                let id = "\(ex.id)_opt_\(i)"
                if text == correctText { correctOptionId = id }
                let label = i < labels.count ? labels[i] : "\(i + 1)"
                return PracticeOption(id: id, label: label, text: text)
            }
            instructionText = L10n.tr("practice.listen.task",
                                     "Listen, then choose what I said")
        }
        return PracticeQuestion(
            id: ex.id,
            kind: kind,
            index: index,
            total: total,
            promptNative: renderedPrompt,
            promptTranslation: ex.translation,
            instruction: instructionText,
            // audioName переиспользуется как «источник звука» — для listen-choose
            // передаём полный audioUrl с бэка; PracticeQuestion+audioURL резолвит.
            audioName: ex.audioUrl,
            audioDurationSeconds: nil,
            wordOrderSubtitle: "Put the words in order",
            expectedOrder: ex.expected,
            wordBank: bank,
            describePrompt: nil,
            describeImageName: nil,
            options: options,
            correctOptionId: correctOptionId
        )
    }

    private func mapPresentation(_ raw: String?) -> PracticeQuestion.Kind {
        switch raw {
        case "fillBlank":   return .fillBlank
        case "listenChoice": return .listenChoose
        case "wordOrder":   return .wordOrder
        default:            return .wordOrder
        }
    }

    /// «Значимые» слова в предложении — минимум 3 буквы, чтобы отсеять
    /// артикли/предлоги ("me", "a", "el") и знаки пунктуации.
    private func significantWords(in sentence: String) -> [String] {
        sentence
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
            .filter { $0.trimmingCharacters(in: .letters.inverted).count >= 3 }
    }

    /// Берёт случайное значимое слово из предложения и возвращает пару
    /// `(prompt_с_пропуском, вырезанное_слово)`. Пунктуация вокруг слова
    /// сохраняется в prompt (заменяем только буквенную часть).
    private func removeRandomWord(from sentence: String) -> (String, String?) {
        let candidates = significantWords(in: sentence)
        guard let pick = candidates.randomElement() else {
            return (sentence, nil)
        }
        // Ищем именно слово, оставляя знаки препинания на месте.
        // «Ana.» → удалим «Ana», точка останется рядом с пропуском.
        let wordCore = pick.trimmingCharacters(in: .punctuationCharacters)
        guard !wordCore.isEmpty,
              let range = sentence.range(of: wordCore) else {
            return (sentence, nil)
        }
        var blanked = sentence
        blanked.replaceSubrange(range, with: "____")
        return (blanked, wordCore)
    }

    /// Тап Retry в offline-banner. Пробуем переподключиться.
    /// TODO: отправить все `isQueued` сообщения на бэк / повторить последний AI-запрос.
    func retryConnection() {
        // Ничего не делаем — NWPathMonitor сам обновит isOnline когда сеть
        // вернётся. Для DEBUG сбрасываем force-флаг.
        debugForceOffline = false
    }

    // MARK: - Derived

    /// "4:29 / 10:00" — формат под макет.
    var timerLabel: String {
        formatMMSS(elapsedSeconds) + " / " + formatMMSS(Self.sessionMaxSeconds)
    }

    /// Premium: подсказки без лимита. Free: 3 подсказки на шаг, потом paywall.
    var isHintsExhausted: Bool { !isPremium && hintsRemaining <= 0 }

    /// Активна ли запись (или ждём отправки после стопа). Смысл lock-иконки
    /// над миком в Figma 373:4741: в этих состояниях чат-скролл и тапы по
    /// сообщениям должны быть заблокированы.
    var isRecordingActive: Bool {
        inputMode == .recording || inputMode == .recordingStopped
    }

    /// Единый список для fullscreen-чата — то же что видно в обычном (не
    /// fullscreen) режиме контент-секции. В Lecture: messages + Key phrases card
    /// + Pattern cards (после последней ассистент-реплики). В Practice: feedback
    /// от Emma. Question-карточки в fullscreen как компактные баблы не рендерим.
    var fullscreenChatItems: [FullscreenChatItem] {
        switch phase {
        case .lecture:
            var items: [FullscreenChatItem] = messages.map { .message($0) }
            // Key phrases + Pattern card — те же условия что в messagesList:
            // показываем если последний message = assistant.
            if messages.last?.role == .assistant {
                if !keyPhrases.isEmpty {
                    items.append(.keyPhrases)
                }
                for pattern in patterns {
                    items.append(.pattern(pattern))
                }
            }
            return items
        case .practice:
            // В fullscreen показываем ВЕСЬ practice-стрим: и вопросы, и
            // feedback. Без вопросов был пустой экран.
            return practiceStream.map { item -> FullscreenChatItem in
                switch item {
                case .feedback(let id, let text, let isCorrect):
                    return .practiceFeedback(id: id, text: text, isCorrect: isCorrect)
                case .question(let q):
                    return .practiceQuestion(q)
                }
            }
        }
    }

    /// Item для fullscreen-чата — все виды контента который может быть в
    /// contentSection в normal-режиме.
    enum FullscreenChatItem: Identifiable, Hashable {
        case message(LessonMessage)
        case keyPhrases
        case pattern(PatternExample)
        case practiceFeedback(id: String, text: String, isCorrect: Bool)
        case practiceQuestion(PracticeQuestion)

        var id: String {
            switch self {
            case .message(let m):                 return "m_\(m.id)"
            case .keyPhrases:                     return "kp"
            case .pattern(let p):                 return "pt_\(p.id)"
            case .practiceFeedback(let id, _, _): return "f_\(id)"
            case .practiceQuestion(let q):        return "q_\(q.id)"
            }
        }
    }

    /// Текущее значение progress-бара. Filled сегменты в Practice = номер
    /// текущего вопроса (Q1 → 1 сегмент filled, Q2 → 2 filled, и т.д.).
    /// В Lecture — lectureProgressCurrent как раньше.
    var progressCurrent: Int {
        switch phase {
        case .lecture:  lectureProgressCurrent
        case .practice: min(currentQuestionNumber, progressTotal)
        }
    }

    /// Total сегментов progress-бара. В Practice — реальное число вопросов
    /// текущего шага (сервер отдаёт разное количество для разных упражнений).
    /// Ранее было фикс 5 из Figma-мока — не совпадало с реальным контентом.
    var progressTotal: Int {
        switch phase {
        case .lecture:  lectureProgressTotal
        case .practice: max(1, practiceQuestions.count)
        }
    }

    /// Текущий (последний неотвеченный) вопрос в стриме.
    var currentPracticeQuestion: PracticeQuestion? {
        for item in practiceStream.reversed() {
            if case .question(let q) = item, practiceAnswers[q.id] == nil {
                return q
            }
        }
        // Если все отвечены — берём последний в стриме.
        if let last = practiceStream.reversed().first(where: { if case .question = $0 { return true } else { return false } }),
           case .question(let q) = last {
            return q
        }
        return practiceQuestions.first
    }

    /// Номер текущего вопроса для лейбла «Question N of M».
    var currentQuestionNumber: Int {
        currentPracticeQuestion?.index ?? (practiceAnsweredCount + 1)
    }
    var currentQuestionTotal: Int {
        currentPracticeQuestion?.total ?? practiceQuestions.count
    }

    // MARK: - Actions

    func tick() {
        guard elapsedSeconds < Self.sessionMaxSeconds else { return }
        elapsedSeconds += 1
    }

    func toggleFullscreen() {
        isFullscreen.toggle()
    }

    func switchToTextInput() {
        withAnimation(Self.modeTransition) { inputMode = .text }
    }

    func switchToButtons() {
        withAnimation(Self.modeTransition) { inputMode = .buttons }
    }

    // MARK: - Recording flow

    /// Тап Speak. Проверяет speech + mic permissions, запускает реальную запись
    /// через SpeechDictationService. Внутри урока голос бесплатный —
    /// платный voice-гейт живёт только на Free Talk (`TalkViewModel`).
    func startRecording() async {
        let speechStatus = await speech.requestAuthorization()
        guard speechStatus == .authorized else {
            error = L10n.tr("error.speech_permission_hint", "Speech recognition permission required. Enable in Settings → Privacy → Speech Recognition.")
            return
        }
        let micGranted = await speech.requestMicPermission()
        guard micGranted else {
            error = L10n.tr("error.mic_permission_hint", "Microphone permission required. Enable in Settings → Privacy → Microphone.")
            return
        }
        do {
            try await speech.startRecording(language: language)
            withAnimation(Self.modeTransition) { inputMode = .recording }
        } catch {
            self.error = L10n.tr("error.mic_start_failed",
                                "Couldn't start recording. Please try again.")
        }
    }

    /// Тап эквалайзера → останавливаем реальную запись, экран показывает
    /// «стоп» с транскриптом наготове (в `speech.transcript`).
    func stopRecording() {
        speech.stopRecording()
        withAnimation(Self.modeTransition) { inputMode = .recordingStopped }
    }

    /// Тап Cancel → останавливаем запись без сохранения, возврат в кнопки.
    func cancelRecording() {
        speech.stopRecording()
        withAnimation(Self.modeTransition) { inputMode = .buttons }
    }

    /// Является ли текущий шаг date-свиданием.
    var isDateStep: Bool { step.kind == .date }

    /// Учитель «печатает ответ» — показываем typing-индикатор в чате, чтобы
    /// юзер видел, что запрос не повис. Триггерят серверный chat-turn (в
    /// date) и клиентский GPT (в speaking/date free-chat). Значение true —
    /// пока в полёте один из двух путей.
    var isTeacherReplying: Bool { isDateTurnPending || isSpeakingReplyInFlight }

    /// Локализованный label typing-индикатора на target-языке, как в Talk:
    /// «Yuki is typing» / «Yuki está escribiendo».
    var typingLabel: String {
        switch language {
        case .en: return "\(teacher.name) is typing"
        case .es: return "\(teacher.name) está escribiendo"
        }
    }

    // MARK: - Conversation info sheet
    /// Sheet-подсказка на языке юзера: «вы в живом диалоге с учителем
    /// на тему такую-то». Показываем тапом по chip «What to reply?».
    /// Заменяет старый Hint-sheet в интерактивных степах.
    var showConversationInfoSheet: Bool = false

    /// Тема для sheet-подсказки. Собираем из step-метаданных
    /// (title / subtitle), в fallback идёт локализованное generic-название.
    /// Никаких длинных сценариев — иначе бабл-подсказка превращается в
    /// simulator lorem.
    var conversationTopic: String {
        let title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let subtitle = step.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subtitle.isEmpty { return subtitle }
        return L10n.tr("lesson.conversation.info.default_topic", "this lesson")
    }

    func openConversationInfoSheet()  { showConversationInfoSheet = true }
    func closeConversationInfoSheet() { showConversationInfoSheet = false }

    /// Родной язык юзера — на нём показываем UI-подсказки, чтобы юзер
    /// читал их «на своём», а не на изучаемом. Определяется от системы:
    /// если системный язык совпадает с target обучения (юзер настроил
    /// iOS на изучаемый) — берём противоположный из наших двух локалей;
    /// иначе — просто en/es по устройству. Мы поддерживаем только en/es.
    private var nativeUILang: String {
        let deviceLang = Locale.current.language.languageCode?.identifier ?? "en"
        let studyLang = language.rawValue
        if deviceLang == studyLang {
            return studyLang == "en" ? "es" : "en"
        }
        return (deviceLang == "es") ? "es" : "en"
    }

    /// Заголовок sheet «What to reply?» на родном языке юзера.
    var conversationInfoTitle: String {
        nativeUILang == "es" ? "Modo conversación" : "Conversation mode"
    }

    /// Тело sheet «What to reply?» с подставленной темой урока
    /// (`conversationTopic`) — тоже на родном языке юзера.
    var conversationInfoBody: String {
        let template = nativeUILang == "es"
            ? "Estás manteniendo una conversación en vivo con tu profesor(a) sobre %@. Responde con naturalidad — el profesor mantendrá el tema."
            : "You're having a live conversation with your teacher about %@. Reply naturally — the teacher will keep the topic."
        return String(format: template, conversationTopic)
    }

    /// Подпись close-кнопки sheet «What to reply?» на родном языке юзера.
    var conversationInfoCloseLabel: String {
        nativeUILang == "es" ? "Entendido" : "Got it"
    }

    /// «Trigger-driven» шаг — бек прислал готовый список turns/фраз, юзер не
    /// общается с GPT, а просто листает по одному тапу «Next». Используется
    /// **только в Lecture-фазе**. Для Practice-фазы см. `canTapNext` /
    /// `canUseTextOrVoice` — там правила другие (per-question).
    var isTriggerDriven: Bool {
        switch step.kind {
        case .lecture, .topicWords, .pattern, .grammar: return true
        case .date, .speaking:                          return false
        }
    }

    /// Активна ли кнопка Next в bottom bar. Правила:
    /// - Lecture-фаза: активна ровно для trigger-driven степов
    ///   (`.lecture / .topicWords / .pattern / .grammar`), в остальных
    ///   (интерактивный `.date / .speaking`) юзер тригерит своей репликой.
    /// - Practice-фаза: активна ТОЛЬКО для `.wordOrder` (юзер сам собирает
    ///   предложение и жмёт Next для валидации). `.fillBlank / .listenChoose`
    ///   валидируются тапом по опции, `.describeImage` пока без Next-логики.
    var canTapNext: Bool {
        switch phase {
        case .lecture:
            return isTriggerDriven
        case .practice:
            guard let q = currentPracticeQuestion else { return false }
            guard practiceAnswers[q.id] == nil else { return false }
            switch q.kind {
            case .wordOrder:                          return true
            case .fillBlank, .listenChoose, .describeImage: return false
            }
        }
    }

    /// Активны ли Text/Speak в bottom bar. В Practice-фазе всегда false
    /// (юзер тапает по опциям / жмёт Next). В Lecture-фазе — только для
    /// интерактивных степов, где идёт разговор с GPT. Дополнительно —
    /// как только показан Finish (`canFinishLesson`), урок фактически
    /// закончен и любые новые реплики от юзера бессмысленны, ввод
    /// блокируется.
    var canUseTextOrVoice: Bool {
        guard !canFinishLesson else { return false }
        switch phase {
        case .practice: return false
        case .lecture:  return !isTriggerDriven
        }
    }

    /// Универсальный хендлер тапа Next. В Lecture — advance к следующей
    /// реплике учителя. В Practice — валидируем текущий `.wordOrder` вопрос
    /// (собранное юзером предложение уходит в `answerPractice`-like поток
    /// с feedback'ом и переходом к следующему вопросу).
    func onNextTap() {
        switch phase {
        case .lecture:
            advanceLecture()
        case .practice:
            guard let q = currentPracticeQuestion,
                  q.kind == .wordOrder,
                  practiceAnswers[q.id] == nil
            else { return }
            validateWordOrder(for: q)
        }
    }

    /// Флаг «нужно показать .free_chat пейвол» — оставлен для date-триггера
    /// извне (если понадобится). Сейчас не используется — voice-гейт
    /// поднимает `shouldShowInLessonsPaywall`.
    var shouldShowFreeChatPaywall: Bool = false

    /// Флаг «показать `.in_lessons` пейвол» — free-юзер тапнул мик
    /// в уроке. LessonView подписан через `.onChange` и триггерит paywall.
    var shouldShowInLessonsPaywall: Bool = false

    /// Тап стрелки-отправки в состоянии .recordingStopped.
    /// - lecture / grammar / speaking / topicWords / pattern: транскрипт
    ///   уходит как обычный текстовый ответ (routeReply).
    /// - date: транскрипт + аудио уходят на `chat-turn` мультимодально
    ///   (пока — только текст; аудио-канал добавим когда сервер примет).
    func sendRecordedReply() {
        let transcript = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // Забираем аудио СРАЗУ, до перехода в .buttons — стоп-записи мог
        // ещё не успеть флашнуть файл, но SpeechDictationService уже вызвал
        // finalizeAudioCapture в stopRecording, так что URL стабилен.
        // Читаем Data лениво — только если действительно есть транскрипт.
        let audioURL = speech.recordedAudioURL
        withAnimation(Self.modeTransition) { inputMode = .buttons }
        guard !transcript.isEmpty else { return }
        let audioData: Data? = audioURL.flatMap { try? Data(contentsOf: $0) }
        appendUserMock(text: transcript, hintUsed: false)
        routeReply(transcript, audio: audioData)
    }

    /// Отправить текстовое сообщение из TextField.
    func sendUserReply(_ text: String, hintUsed: Bool = false) {
        // Урок уже готов к завершению (`canFinishLesson`) — новые реплики
        // не принимаем: и чтобы GPT/бек не крутили лишние ходы, и чтобы
        // UI не отвлекал юзера от кнопки Finish.
        guard !canFinishLesson else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendUserMock(text: trimmed, hintUsed: hintUsed)
        routeReply(trimmed, audio: nil)
        inputText = ""
    }

    /// Роутит user-реплику по типу шага:
    /// - `.date` → `POST /v1/ai/chat-turn` (свободный диалог) или client GPT
    ///   (date-fallback). Client GPT слышит `audio`, если оно есть.
    /// - `.speaking` → advance-lecture + `POST /v1/ai/evaluate-reply` (оценка),
    ///   либо client GPT (speaking-fallback), который тоже слышит `audio`.
    /// - остальные (lecture / topicWords / pattern / grammar) → advance-lecture.
    ///
    /// - Parameter audio: WAV-байты последней голосовой записи (16 kHz mono
    ///   int16). Уходят только в GPT-ветки — для оценки произношения.
    ///   Серверные ветки (`chat-turn`, `evaluate-reply`) сейчас принимают
    ///   только текст, аудио игнорируется. `nil` — если реплика пришла с
    ///   клавиатуры.
    private func routeReply(_ text: String, audio: Data?) {
        switch step.kind {
        case .date:
            Task { await handleDateReply(text: text, audio: audio) }
        case .speaking:
            // Fallback-режим: сервер прислал пустые turns → ведём диалог
            // через клиентский GPT в рамках сценария.
            if isSpeakingFreeChatMode {
                Task { await handleSpeakingFreeChatReply(text: text, audio: audio) }
                return
            }
            let exchangeId = lectureCursor > 0 ? allLectureTurns[lectureCursor - 1].id : step.id
            advanceLecture()
            Task { await sendSpeakingEvaluation(exchangeId: exchangeId, text: text) }
        default:
            advanceLecture()
        }
    }

    /// Speaking-fallback: сервер прислал только сценарий, ведём короткий
    /// диалог через `AIChatService`. Учитель отвечает по system-промпту,
    /// заточенному под сценарий; после `speakingFreeChatExchanges` реплик
    /// GPT сам финиширует беседу (см. `speakingLessonSystemPrompt` — там
    /// последнему экчейнджу выдаётся инструкция wrap-up), а
    /// `canFinishLesson` разблокирует Finish.
    private func handleSpeakingFreeChatReply(text: String, audio: Data?) async {
        guard !isSpeakingReplyInFlight else { return }
        guard speakingExchangeCount < Self.speakingFreeChatExchanges else { return }
        isSpeakingReplyInFlight = true
        defer { isSpeakingReplyInFlight = false }

        // Первичный путь: серверный chat-turn (даёт голос учителя через
        // audioUrl). Публикуем реплику через sync-emit — текст появляется
        // одновременно с готовым к воспроизведению аудио.
        if let dto = await requestServerChatTurn(userText: text) {
            let trimmed = dto.teacherText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let messageId = "\(step.id)_speaking_t\(speakingExchangeCount)"
            speakingExchangeCount += 1
            advanceProgress()
            await emitTeacherReplySynced(
                id: messageId,
                text: trimmed,
                audioUrl: dto.audioUrl,
                translation: dto.translation
            )
            return
        }

        // Fallback: серверный chat-turn отдаёт 409 на speaking-степах →
        // ведём диалог клиентским GPT, а озвучку получаем отдельным
        // запросом `/v1/ai/tts`. Если TTS ответит — sync-emit склеит
        // бабл с готовым голосом; если нет — покажем без озвучки.
        // Счётчик не тронут при ошибке GPT.
        guard let aiChat else { return }
        let remaining = Self.speakingFreeChatExchanges - speakingExchangeCount
        let system = teacher.speakingLessonSystemPrompt(
            scenario: speakingScenario,
            language: language,
            remainingExchanges: remaining,
            userName: user.name
        )
        // История для GPT — вся текущая переписка (scenario, opener,
        // предыдущие обмены). Ограничиваем последними 12, чтобы контекст
        // не пух на длинных степах. Если реплика пришла голосом — исключаем
        // последний user-turn (он уйдёт как audio, иначе GPT увидит юзера
        // дважды: и в history-тексте, и в input_audio).
        let history = historyForGPT(limit: 12, dropLastUserIfAudio: audio != nil, expectedText: text)
        do {
            var replyText = try await sendToGPT(
                aiChat: aiChat,
                history: history,
                systemPrompt: system,
                audio: audio
            )
            // На финальном ходе иногда GPT всё равно задаёт вопрос —
            // перезапрашиваем с жёсткой пост-инструкцией.
            if remaining <= 1, replyLooksLikeQuestion(replyText),
               let clean = await retryClosingReply(
                aiChat: aiChat,
                history: history,
                systemPrompt: system,
                audio: audio,
                firstAttempt: replyText
               ) {
                replyText = clean
            }
            guard !replyText.isEmpty else { return }
            let messageId = "\(step.id)_speaking_t\(speakingExchangeCount)"
            speakingExchangeCount += 1
            advanceProgress()
            let audioUrl = await requestTTS(text: replyText)
            await emitTeacherReplySynced(
                id: messageId,
                text: replyText,
                audioUrl: audioUrl,
                translation: nil
            )
        } catch {
            // Молчим — юзер может попробовать ещё раз (счётчик не тронут).
        }
    }

    /// Speaking-фаза: оценка последней user-реплики через `evaluate-reply`.
    /// Correction (если есть) добавляется отдельным assistant-баблом ниже
    /// текущей учительской реплики.
    private func sendSpeakingEvaluation(exchangeId: String, text: String) async {
        do {
            let dto = try await AiAPI.evaluateReply(.init(
                sessionAttemptId: sessionAttemptId.uuidString,
                exchangeId: exchangeId,
                userInput: .init(text: text, audioKey: nil)
            ))
            guard !dto.correctionText.isEmpty || !dto.feedback.isEmpty else { return }
            let feedback = composedFeedback(dto: dto)
            withAnimation(.easeInOut(duration: 0.28)) {
                messages.append(LessonMessage(
                    id: "\(exchangeId)_fb",
                    role: .assistant,
                    text: feedback,
                    hintUsed: false
                ))
            }
        } catch {
            // Молчим — оценка не критична, урок продолжается.
        }
    }

    /// Один шаг свободного диалога.
    /// - `isDateFreeChatMode == true` (по умолчанию для date-шагов, если
    ///   доступен `AIChatService`) — ведём диалог локально через GPT в
    ///   контексте `topic/context/goal`; после `dateFreeChatExchanges`
    ///   реплик GPT финиширует closing-репликой, `dateShouldEnd = true`
    ///   → `finishSession`.
    /// - Иначе (нет OpenAI-ключа) — старый путь через сервер
    ///   `POST /v1/ai/chat-turn`, финиш по `shouldEnd` от сервера.
    func handleDateReply(text: String, audio: Data? = nil) async {
        guard !isDateTurnPending, !dateShouldEnd else { return }
        isDateTurnPending = true
        defer { isDateTurnPending = false }
        if isDateFreeChatMode {
            await handleDateFreeChatReply(text: text, audio: audio)
            return
        }
        // Серверная ветка chat-turn аудио пока не принимает — идёт только
        // текстовый transcript, `audio` игнорируется. В ответе получаем
        // `teacherText` + `audioUrl` (озвучка в голосе учителя) — реплику
        // публикуем через `emitTeacherReplySynced`, чтобы текст появился
        // ровно когда голос готов проиграться.
        do {
            let dto = try await AiAPI.chatTurn(.init(
                sessionAttemptId: sessionAttemptId.uuidString,
                userText: text
            ))
            let messageId = "\(step.id)_t\(dto.turnIndex)"
            elapsedSeconds = max(elapsedSeconds, dto.elapsedSeconds)
            advanceProgress()
            await emitTeacherReplySynced(
                id: messageId,
                text: dto.teacherText,
                audioUrl: dto.audioUrl,
                translation: dto.translation
            )
            if dto.shouldEnd {
                dateShouldEnd = true
                lastScore = nil
                Task { await finishSession(completed: true) }
            }
        } catch APIError.paymentRequired {
            sessionAbort = .paywallRequired
        } catch APIError.conflict {
            sessionAbort = .stepConflict
        } catch let APIError.rateLimited(_, _, resetsAt) {
            sessionAbort = .quotaExhausted(resetsAt: resetsAt)
        } catch {
            // Сеть/декодер — молчим, юзер попробует ещё раз.
        }
    }

    /// Date-fallback: сцена ведётся клиентским GPT в контексте
    /// `dateTopic/dateContext/dateGoal`. На последнем экчейндже промпт
    /// переключается в wrap-up (см. `dateLessonSystemPrompt`), сразу
    /// после ответа GPT ставим `dateShouldEnd = true` и триггерим
    /// `finishSession` — Home увидит завершение.
    private func handleDateFreeChatReply(text: String, audio: Data?) async {
        // Первичный путь: серверный chat-turn — он вернёт текст + audioUrl
        // (озвучка в голосе учителя). Прогоняем через sync-emit, чтобы
        // бабл появился одновременно с голосом.
        if let dto = await requestServerChatTurn(userText: text) {
            let messageId = "\(step.id)_date_t\(dateExchangeCount)"
            elapsedSeconds = max(elapsedSeconds, dto.elapsedSeconds)
            dateExchangeCount += 1
            advanceProgress()
            await emitTeacherReplySynced(
                id: messageId,
                text: dto.teacherText,
                audioUrl: dto.audioUrl,
                translation: dto.translation
            )
            if dto.shouldEnd || dateExchangeCount >= Self.dateFreeChatExchanges {
                dateShouldEnd = true
                Task { await finishSession(completed: true) }
            }
            return
        }

        // Fallback: сервер chat-turn недоступен → ведём диалог клиентским GPT,
        // но озвучку берём отдельным запросом `/v1/ai/tts`. Если TTS ответит —
        // sync-emit склеит текст с готовым голосом; если нет — покажем без
        // озвучки (старое поведение).
        guard let aiChat else { return }
        let remaining = max(1, Self.dateFreeChatExchanges - dateExchangeCount)
        let system = teacher.dateLessonSystemPrompt(
            topic: dateTopic,
            context: dateContext,
            goal: dateGoal,
            language: language,
            remainingExchanges: remaining,
            userName: user.name
        )
        let history = historyForGPT(limit: 14, dropLastUserIfAudio: audio != nil, expectedText: text)
        do {
            var replyText = try await sendToGPT(
                aiChat: aiChat,
                history: history,
                systemPrompt: system,
                audio: audio
            )
            if remaining <= 1, replyLooksLikeQuestion(replyText),
               let clean = await retryClosingReply(
                aiChat: aiChat,
                history: history,
                systemPrompt: system,
                audio: audio,
                firstAttempt: replyText
               ) {
                replyText = clean
            }
            guard !replyText.isEmpty else { return }
            let messageId = "\(step.id)_date_t\(dateExchangeCount)"
            dateExchangeCount += 1
            advanceProgress()
            let audioUrl = await requestTTS(text: replyText)
            await emitTeacherReplySynced(
                id: messageId,
                text: replyText,
                audioUrl: audioUrl,
                translation: nil
            )
            if dateExchangeCount >= Self.dateFreeChatExchanges {
                dateShouldEnd = true
                Task { await finishSession(completed: true) }
            }
        } catch {
            // GPT недоступен — молчим, юзер попробует ещё раз.
        }
    }

    /// Собирает историю для GPT из последних `limit` сообщений. Если реплика
    /// пришла голосом (`dropLastUserIfAudio == true`), исключаем самый
    /// последний user-turn: он уйдёт отдельной аудио-репликой через
    /// `sendMultimodal`, иначе GPT увидел бы юзера дважды — текстом и голосом.
    /// Дополнительная защита: `expectedText` совпадает с последним user text.
    private func historyForGPT(limit: Int, dropLastUserIfAudio: Bool, expectedText: String) -> [AIMessage] {
        var slice = Array(messages.suffix(limit))
        if dropLastUserIfAudio,
           let last = slice.last,
           last.role == .user,
           last.text == expectedText {
            slice.removeLast()
        }
        return slice.map { m in
            AIMessage(
                id: m.id,
                role: m.role == .assistant ? .assistant : .user,
                text: m.text,
                createdAt: .now
            )
        }
    }

    /// Один вход в GPT: если есть `audio` — идём мультимодалом (аудио
    /// сопровождает историю), иначе обычный text-only `send`. При ошибке
    /// мультимодала откатываемся в text-only с полной историей (включая
    /// последнюю user-реплику), чтобы юзер получил ответ.
    private func sendToGPT(
        aiChat: AIChatServicing,
        history: [AIMessage],
        systemPrompt: String,
        audio: Data?
    ) async throws -> String {
        if let audio {
            do {
                let reply = try await aiChat.sendMultimodal(
                    history: history,
                    userAudio: AIAudioInput(data: audio, format: .wav),
                    systemPrompt: systemPrompt,
                    model: AIChatService.audioModel,
                    replyModality: .textOnly
                )
                return reply.message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                // Fallback: используем полную историю (с последней user-репликой),
                // а не «обрезанную под аудио» — GPT должен знать, что сказал юзер.
                let full: [AIMessage] = messages.suffix(history.count + 1).map { m in
                    AIMessage(
                        id: m.id,
                        role: m.role == .assistant ? .assistant : .user,
                        text: m.text,
                        createdAt: .now
                    )
                }
                let reply = try await aiChat.send(
                    history: full,
                    systemPrompt: systemPrompt,
                    model: AIChatService.defaultModel
                )
                return reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            let reply = try await aiChat.send(
                history: history,
                systemPrompt: systemPrompt,
                model: AIChatService.defaultModel
            )
            return reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Добавить следующую лекторскую реплику из очереди. Двигает прогресс-бар,
    /// автоплейит аудио (если включено в настройках), в конце — выпускает
    /// key phrases + patterns под финальным баблом.
    func advanceLecture() {
        guard lectureCursor < allLectureTurns.count else {
            advanceProgress()
            return
        }
        let turn = allLectureTurns[lectureCursor]
        withAnimation(.easeInOut(duration: 0.28)) {
            messages.append(LessonMessage(
                id: turn.id, role: .assistant, text: turn.teacherText, hintUsed: false
            ))
        }
        lectureCursor += 1
        advanceProgress()
        Task { await autoplayIfEnabled(messageId: turn.id) }
        if isLectureFinished {
            withAnimation(.easeInOut(duration: 0.28)) {
                keyPhrases = pendingKeyPhrases
                patterns   = pendingPatterns
            }
        }
    }

    // MARK: - Progress

    /// Продвигает Lecture-прогресс. Practice-прогресс продвигается через
    /// `advanceToNextPractice()` после ответа на вопрос.
    private func advanceProgress() {
        guard lectureProgressCurrent < lectureProgressTotal else { return }
        lectureProgressCurrent += 1
    }

    // MARK: - Phase switching

    func selectPhase(_ p: LessonPhase) {
        // При первом входе в Practice — загружаем моки. Backend fetch — TODO.
        if p == .practice && practiceQuestions.isEmpty {
            loadMockPractice()
        }
        withAnimation(Self.modeTransition) { phase = p }
    }

    /// Загружает мок-Practice-контент и инициализирует стрим первым вопросом.
    /// TODO: заменить на fetch `GET /content/practice/{stepId}?languageCode=...`.
    func loadMockPractice() {
        practiceQuestions = [
            PracticeContent.grammarMock(index: 1, total: 6),
            PracticeContent.listenChooseMock(index: 2, total: 6)
        ]
        practiceStream = [.question(practiceQuestions[0])]
        practiceAnswers = [:]
    }

    // MARK: - Practice actions

    /// Тап по варианту ответа. Записывает выбор, сразу показывает feedback-бабл,
    /// и через 1.8 секунды подгружает следующий вопрос — чтобы юзер успел
    /// прочитать реакцию Emma. Параллельно уходит `POST /v1/ai/evaluate-reply`
    /// на бэк — когда придёт ответ, feedback заменяется на серверный.
    func answerPractice(question: PracticeQuestion, option: PracticeOption) {
        guard practiceAnswers[question.id] == nil else { return }
        practiceAnswers[question.id] = option.id

        let isCorrect = option.id == question.correctOptionId
        let feedback = mockFeedback(for: question, chosen: option, isCorrect: isCorrect)

        // Feedback появляется сразу с анимацией (fallback до ответа сервера).
        let feedbackId = UUID().uuidString
        withAnimation(.easeInOut(duration: 0.33)) {
            practiceStream.append(.feedback(
                id: feedbackId,
                text: feedback,
                isCorrect: isCorrect
            ))
        }
        Task { await evaluatePracticeReplyRemote(
            exchangeId: question.id,
            userText: option.text,
            feedbackId: feedbackId
        ) }

        // Триггерим avatar-реакцию учителя (correct/wrong видео + SFX).
        triggerReaction(isCorrect ? .correct : .wrong)

        // Следующий вопрос — с паузой 1.8s чтобы прочитать feedback.
        guard let idx = practiceQuestions.firstIndex(where: { $0.id == question.id }),
              idx + 1 < practiceQuestions.count
        else { return }
        let next = practiceQuestions[idx + 1]
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.33)) {
                    self?.practiceStream.append(.question(next))
                }
            }
        }
    }

    /// Возвращает id выбранной опции для вопроса или `nil` если ещё не отвечено.
    func selectedOption(for question: PracticeQuestion) -> String? {
        practiceAnswers[question.id]
    }

    // MARK: - Word order actions (Figma 373:3761)

    /// Текущий порядок выбранных слов юзером для .wordOrder вопроса.
    func wordOrderSelection(for question: PracticeQuestion) -> [String] {
        wordOrderSelections[question.id] ?? []
    }

    /// Оставшиеся слова в word-bank (не выбранные).
    func availableWords(for question: PracticeQuestion) -> [String] {
        let bank = question.wordBank ?? []
        let selected = wordOrderSelection(for: question)
        var remaining = bank
        for word in selected {
            if let idx = remaining.firstIndex(of: word) {
                remaining.remove(at: idx)
            }
        }
        return remaining
    }

    /// Тап на слово из word-bank → добавляем в selection. Валидация НЕ
    /// авто-триггерится — юзер сам жмёт Next в bottom bar когда считает,
    /// что предложение готово (см. `onNextTap` → `validateWordOrder`).
    func addWordToOrder(_ word: String, for question: PracticeQuestion) {
        guard practiceAnswers[question.id] == nil else { return }
        var current = wordOrderSelection(for: question)
        current.append(word)
        wordOrderSelections[question.id] = current
    }

    /// Тап на pink pill в drop-zone → возвращаем слово в bank.
    func removeWordFromOrder(at index: Int, for question: PracticeQuestion) {
        guard practiceAnswers[question.id] == nil else { return }
        var current = wordOrderSelection(for: question)
        guard current.indices.contains(index) else { return }
        current.remove(at: index)
        wordOrderSelections[question.id] = current
    }

    /// Валидируем текущий выбор юзера для .wordOrder вопроса и толкаем
    /// feedback + следующий вопрос — той же цепочкой, что и `answerPractice`
    /// для fillBlank / listenChoose. Вызывается тапом Next в bottom bar
    /// (см. `onNextTap`). Если выбор пустой — noop.
    func validateWordOrder(for question: PracticeQuestion) {
        let selected = wordOrderSelection(for: question)
        guard !selected.isEmpty,
              let expected = question.expectedOrder,
              practiceAnswers[question.id] == nil
        else { return }
        let isCorrect = selected == expected
        practiceAnswers[question.id] = isCorrect ? "correct" : "incorrect"

        let feedbackText = mockFeedbackForWordOrder(expected: expected, isCorrect: isCorrect)
        let feedbackId = UUID().uuidString
        withAnimation(.easeInOut(duration: 0.33)) {
            practiceStream.append(.feedback(
                id: feedbackId,
                text: feedbackText,
                isCorrect: isCorrect
            ))
        }
        Task { await evaluatePracticeReplyRemote(
            exchangeId: question.id,
            userText: selected.joined(separator: " "),
            feedbackId: feedbackId
        ) }

        triggerReaction(isCorrect ? .correct : .wrong)
        guard let idx = practiceQuestions.firstIndex(where: { $0.id == question.id }),
              idx + 1 < practiceQuestions.count
        else { return }
        let next = practiceQuestions[idx + 1]
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.33)) {
                    self?.practiceStream.append(.question(next))
                }
            }
        }
    }

    private func mockFeedbackForWordOrder(expected: [String], isCorrect: Bool) -> String {
        if isCorrect { return language == .es ? "¡Correcto!" : "Correct!" }
        let right = expected.joined(separator: " ")
        return language == .es
            ? "Casi. El orden correcto es: «\(right)»."
            : "Almost. The right order is: «\(right)»."
    }

    /// TODO: заменить mock на GPT-объяснение.
    private func mockFeedback(for q: PracticeQuestion, chosen: PracticeOption, isCorrect: Bool) -> String {
        if isCorrect {
            return language == .es ? "¡Correcto!" : "Correct!"
        }
        let right = q.options.first { $0.id == q.correctOptionId }?.text ?? "?"
        return language == .es
            ? "No exactamente. La respuesta correcta es «\(right)»."
            : "Not quite. The right answer is «\(right)»."
    }

    /// `POST /v1/ai/evaluate-reply` — асинхронная валидация ответа на бэке.
    /// Если сервер вернул более детальный feedback (или correction) — заменяем
    /// mock-текст на серверный по `feedbackId`.
    func evaluatePracticeReplyRemote(
        exchangeId: String,
        userText: String,
        feedbackId: String
    ) async {
        do {
            let dto = try await AiAPI.evaluateReply(.init(
                sessionAttemptId: sessionAttemptId.uuidString,
                exchangeId: exchangeId,
                userInput: .init(text: userText, audioKey: nil)
            ))
            let composed = composedFeedback(dto: dto)
            replaceFeedback(id: feedbackId, text: composed, isCorrect: dto.score >= 60)
        } catch {
            // Молчим — на экране остаётся локальный mock.
        }
    }

    private func composedFeedback(dto: EvaluateReplyDTO) -> String {
        var parts: [String] = [dto.feedback]
        if !dto.correctionText.isEmpty {
            parts.append("→ \(dto.correctionText)")
        }
        return parts.joined(separator: "\n")
    }

    private func replaceFeedback(id: String, text: String, isCorrect: Bool) {
        guard let idx = practiceStream.firstIndex(where: {
            if case .feedback(let fid, _, _) = $0 { return fid == id } else { return false }
        }) else { return }
        practiceStream[idx] = .feedback(id: id, text: text, isCorrect: isCorrect)
    }

    // MARK: - Mock content append

    private func appendUserMock(text: String, hintUsed: Bool) {
        messages.append(
            LessonMessage(
                id: UUID().uuidString,
                role: .user,
                text: text,
                hintUsed: hintUsed
            )
        )
    }

    /// TODO: заменить моком следующей реплики Emma. Это должен отдавать backend
    /// в ответ на прогресс + user-transcript.
    private func appendMockLectureReply() {
        let text: String
        switch language {
        case .en:
            text = "Great! Lets talk about how we say what is happening now.\n\nUse **am/is/are** + **verb - ing** to say what someone is doing now."
        case .es:
            text = "¡Bien! Ahora vamos a hablar de cómo decimos lo que está pasando ahora.\n\nUsa **estoy/estás/está** + **verbo + -ando/-iendo** para decir lo que alguien está haciendo."
        }
        messages.append(
            LessonMessage(
                id: UUID().uuidString,
                role: .assistant,
                text: text,
                hintUsed: false
            )
        )
    }

    /// Тап на Hint. Если есть последний score — открывается score-sheet
    /// (Figma 373:2263). Иначе — обычный «Need a hint?» / «Out of hints».
    func openHintSheet() {
        if lastScore != nil {
            showScoreSheet = true
        } else {
            showHintSheet = true
        }
    }
    func closeHintSheet() { showHintSheet = false }
    func closeScoreSheet() { showScoreSheet = false }

    /// Открытая подсказка после первого sheet: показывает сам текст reply
    /// в отдельном bottom-sheet (Figma-стиль как в score sheet 373:2263).
    var showHintRevealSheet: Bool = false
    /// Текст подсказки, которую видит юзер во втором sheet.
    /// Сохраняется на момент открытия, чтобы после advanceLecture
    /// текущий turn не сменился и второй sheet не показывал не то.
    var revealedHintText: String?
    func closeHintRevealSheet() { showHintRevealSheet = false }

    /// Идёт запрос GPT-подсказки (fallback когда сервер `userReply` пуст).
    var isGeneratingHint: Bool = false

    /// Подсказка для ПОСЛЕДНЕЙ assistant-реплики. Раньше итерировали в
    /// обратном порядке и падали на первый попавшийся — из-за этого при
    /// прогрессии turns без сохранённых userReply хинт возвращал старый
    /// «Ready.» до бесконечности. Теперь смотрим только на последнее
    /// сообщение: нет suggestion — nil → уходим в GPT-фолбэк.
    var currentSuggestedReply: String? {
        guard let last = messages.last(where: { $0.role == .assistant }) else { return nil }
        return suggestedReplyByTurnId[last.id]
    }

    /// Тап «Show me a hint» в первом sheet. Закрываем первый sheet, тратим
    /// одну подсказку, открываем второй sheet со самим текстом ответа.
    /// Если сервер не прислал suggestion для текущей реплики — подтягиваем
    /// подсказку через GPT в контексте языка и последних сообщений.
    func showHint() {
        // Для free — списываем из глобальной 24h-квоты (общей между уроками).
        // Для premium — просто не трогаем счётчик, доступ неограниченный.
        if !isPremium {
            hintQuota.consumeHint()
        }
        closeHintSheet()
        // Задержка чтобы первый sheet успел уйти — иначе SwiftUI не покажет
        // второй (два fullscreen presentation одновременно).
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if let cached = currentSuggestedReply {
                revealedHintText = cached
            } else {
                revealedHintText = nil
                isGeneratingHint = true
                showHintRevealSheet = true
                let text = await generateHintViaAI() ?? ""
                revealedHintText = text.isEmpty ? nil : text
                isGeneratingHint = false
                return
            }
            showHintRevealSheet = true
        }
    }

    /// GPT-фолбэк: строим короткий natural-reply на языке обучения,
    /// опираясь на 3 последних реплики из чата.
    private func generateHintViaAI() async -> String? {
        guard let aiChat else { return nil }
        let langName = language == .es ? "Spanish" : "English"
        let context = messages.suffix(3).map { m -> String in
            let role = m.role == .assistant ? "Teacher" : "Student"
            return "\(role): \(m.text)"
        }.joined(separator: "\n")
        let cleanName = user.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let learnerLine = cleanName.isEmpty
            ? "The student is using a language-learning app and studying \(langName)."
            : "The student's name is \(cleanName). They are using a language-learning app and studying \(langName)."
        let system = """
        You are helping the student mid-lesson with their teacher \(teacher.name).
        \(learnerLine)
        Suggest ONE short, natural reply the student can say next.
        Reply MUST be in \(langName). No quotes, no explanations, no translation.
        Output the sentence directly and nothing else. Keep it short (≤ 12 words).
        """
        let userTurn = AIMessage(id: UUID().uuidString, role: .user, text: context, createdAt: .now)
        do {
            let reply = try await aiChat.send(
                history: [userTurn],
                systemPrompt: system,
                model: AIChatService.defaultModel
            )
            return reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Тап «Use this reply» во втором sheet. Копирует reveal-text в TextField,
    /// переключает input в text-режим, закрывает sheet.
    func applyRevealedHint() {
        guard let text = revealedHintText else { return }
        inputText = text
        withAnimation(Self.modeTransition) { inputMode = .text }
        showHintRevealSheet = false
    }

    // MARK: - Translate & play (per-message actions)

    /// Куда переводим — язык устройства (родной язык юзера). Если он совпадает
    /// с языком урока, берём противоположный из пары en/es. Это делает
    /// перевод осмысленным для юзера: он учит EN, а видит родной перевод.
    private var translationTargetName: String {
        let deviceLang = Locale.current.language.languageCode?.identifier ?? "en"
        let studyLang = language.rawValue
        let target = (deviceLang == studyLang) ? (studyLang == "en" ? "es" : "en") : deviceLang
        return Locale(identifier: "en_US")
            .localizedString(forLanguageCode: target) ?? target
    }

    /// Тап на translate-иконку. Правила:
    /// 1. Если перевод УЖЕ показан — прячем.
    /// 2. Иначе смотрим на серверный кандидат: если он есть и не совпадает
    ///    с оригиналом (case-insensitive whitespace-trim) — берём его.
    /// 3. Иначе — переводим через GPT.
    /// Раньше серверный `translation` пушился сразу в `translations`, и
    /// UI показывал его без запроса юзера. Бэк на некоторых репликах
    /// возвращает translation == оригинал, из-за чего юзер видел «перевод»
    /// идентичный вопросу, скрывал его тапом, а второй тап уходил в GPT
    /// и наконец давал настоящий перевод — ровно тот баг.
    func toggleTranslation(for message: LessonMessage) async {
        if translations[message.id] != nil {
            translations.removeValue(forKey: message.id)
            return
        }
        // Пробуем серверный кандидат.
        if let candidate = serverTranslations[message.id],
           isMeaningfulTranslation(candidate, of: message.text) {
            translations[message.id] = candidate
            return
        }
        guard let chat = aiChat else { return }
        guard !translatingIds.contains(message.id) else { return }
        translatingIds.insert(message.id)
        defer { translatingIds.remove(message.id) }

        do {
            let system = """
            You are a professional translator. Your ONLY task: translate the user's next message into \(translationTargetName).
            Rules:
            - Reply with the translation ONLY. No quotes, no notes, no preamble.
            - Never paraphrase or summarize. Preserve tone and punctuation.
            - If the source is already in \(translationTargetName), reply with the source text unchanged.
            """
            let outbound = AIMessage(id: UUID().uuidString, role: .user, text: message.text, createdAt: .now)
            let reply = try await chat.send(
                history: [outbound],
                systemPrompt: system,
                model: AIChatService.defaultModel
            )
            translations[message.id] = reply.text
        } catch {
            // Молча — если GPT недоступен, юзер увидит что перевод не появился.
        }
    }

    /// Проверка «этот перевод стоит показывать». Отсеивает пустые строки и
    /// случаи когда сервер вернул то же самое, что и в оригинале
    /// (обрезаем whitespace + сравниваем без регистра — этого достаточно
    /// для нашего use case, реальное определение языка тут не нужно).
    private func isMeaningfulTranslation(_ candidate: String, of source: String) -> Bool {
        let c = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return false }
        let s = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return c.compare(s, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
    }

    /// Проиграть серверную озвучку сообщения. Через кэш качается локально
    /// (по имени файла — сервер гарантирует name = хеш содержимого).
    func playAudio(for message: LessonMessage) async {
        guard let url = audioUrlByMessageId[message.id] else { return }
        await playRemote(url: url, id: message.id)
    }

    /// Универсальный проигрыш абсолютного audioUrl (для key phrase / pattern).
    /// Триггерит `.talking` реакцию — аватар «говорит», пока звучит клип.
    /// Останавливает предыдущий трек — новое сообщение всегда прерывает старое.
    func playRemote(url: URL, id: String) async {
        remoteAudio.stop()
        playingMessageId = id
        triggerReaction(.talking)
        guard let local = await RemoteAudioCache.localURL(for: url) else {
            if playingMessageId == id { playingMessageId = nil }
            return
        }
        remoteAudio.play(url: local, id: id)
        // Скидываем UI-состояние через короткую задержку — сам плеер играет
        // асинхронно; конкретное «закончил» без делегата не отслеживаем.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if playingMessageId == id { playingMessageId = nil }
        }
    }

    /// Автовоспроизведение реплики учительницы, если в настройках включён
    /// `autoplayTeacherAudio`. Вызывается при добавлении assistant-сообщения
    /// с известным `audioUrl` (populate, advanceLecture, handleDateReply).
    func autoplayIfEnabled(messageId: String) async {
        guard user.settings.autoplayTeacherAudio else { return }
        guard let url = audioUrlByMessageId[messageId] else { return }
        await playRemote(url: url, id: messageId)
    }

    // MARK: - Free-chat sync (audio-then-bubble)

    /// Атомарно показать реплику учителя в свободном чате: сначала прекачать
    /// озвучку в диск-кэш (если URL пришёл), затем одновременно вставить
    /// бабл в чат и запустить autoplay. Так юзер видит текст ровно тогда,
    /// когда голос готов проиграться, а не «текст → пауза 3 секунды → голос».
    /// Если `audioUrl == nil` — просто вставляем бабл без задержки (это
    /// путь клиентского GPT-fallback'a, у него аудио нет).
    private func emitTeacherReplySynced(
        id: String,
        text: String,
        audioUrl: URL?,
        translation: String?
    ) async {
        if let audioUrl {
            audioUrlByMessageId[id] = audioUrl
            _ = await RemoteAudioCache.localURL(for: audioUrl)
        }
        if let translation, !translation.isEmpty {
            // Только кандидат; UI не покажет пока юзер не тапнет
            // translate-иконку. См. `toggleTranslation` — там валидируем.
            serverTranslations[id] = translation
        }
        withAnimation(.easeInOut(duration: 0.28)) {
            messages.append(LessonMessage(id: id, role: .assistant, text: text, hintUsed: false))
        }
        if audioUrl != nil {
            await autoplayIfEnabled(messageId: id)
        }
    }

    /// Попытка получить ответ учителя через серверный `/v1/ai/chat-turn`.
    /// Единственный источник голосовой озвучки от бэка — этот эндпоинт
    /// возвращает `audioUrl` вместе с `teacherText`. Используется как
    /// первичный путь во всех свободных чатах (date + speaking free-chat),
    /// при сбое (сеть / 4xx / 5xx) — вызывающий откатывается на клиентский
    /// GPT + TTS (см. `requestTTS`).
    private func requestServerChatTurn(userText: String) async -> ChatTurnDTO? {
        do {
            return try await AiAPI.chatTurn(.init(
                sessionAttemptId: sessionAttemptId.uuidString,
                userText: userText
            ))
        } catch {
            return nil
        }
    }

    /// GPT периодически игнорирует wrap-up-инструкцию и всё равно задаёт
    /// вопрос на финальном ходе. Проверяем — если ответ содержит `?` или
    /// начинается с типичного вопросительного слова, считаем что модель
    /// сорвалась и перезапросим её более жёстким «no-question» промптом.
    private func replyLooksLikeQuestion(_ text: String) -> Bool {
        if text.contains("?") { return true }
        let stems: [String] = [
            "what ", "how ", "why ", "which ", "when ", "where ", "who ",
            "do you", "does ", "did ", "are you", "is your", "would you",
            "could you", "can you", "will you", "have you", "tell me",
            "let's ", "shall ", "any other"
        ]
        let lower = text.lowercased()
        return stems.contains { lower.contains($0) }
    }

    /// Прогнать `sendToGPT` ещё раз с жёсткой пост-инструкцией «строго без
    /// вопросов, ровно 2 предложения». Возвращает `nil` если и повторный
    /// ответ содержит вопрос — вызывающий покажет то что есть.
    private func retryClosingReply(
        aiChat: AIChatServicing,
        history: [AIMessage],
        systemPrompt: String,
        audio: Data?,
        firstAttempt: String
    ) async -> String? {
        let harderPrompt = systemPrompt + """


        REMINDER — your previous draft was:
        "\(firstAttempt)"
        It contains a question or a question mark. Rewrite the reply as
        EXACTLY 2 short statements in the same language, WITH NO question marks
        and NO questions of any kind. Second sentence closes the lesson warmly.
        """
        do {
            let text = try await sendToGPT(
                aiChat: aiChat,
                history: history,
                systemPrompt: harderPrompt,
                audio: audio
            )
            return replyLooksLikeQuestion(text) ? nil : text
        } catch {
            return nil
        }
    }

    /// Запросить озвучку произвольного текста голосом текущего учителя через
    /// `POST /v1/ai/tts`. Используется для реплик, у которых нет
    /// `audioUrl` из коробки: локальный opener speaking-фазы и ответы
    /// клиентского GPT (когда серверный chat-turn 409 на speaking-степах).
    /// При любой ошибке возвращает `nil` — вызывающий покажет реплику без
    /// озвучки, а не заблокирует юзера.
    private func requestTTS(text: String) async -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let dto = try await AiAPI.tts(.init(
                text: trimmed,
                teacher: teacher.rawValue,
                language: language.rawValue
            ))
            return dto.audioUrl
        } catch {
            return nil
        }
    }

    // MARK: - Lesson finish

    /// Готовность к завершению урока. Для .lecture — когда все turns прошли.
    /// Для .date — сервер сам ставит `dateShouldEnd`. Для .grammar/.speaking —
    /// когда всё practice отвечено. Для .topicWords / .pattern — сразу.
    var canFinishLesson: Bool {
        switch step.kind {
        case .lecture:              return isLectureFinished
        case .date:                 return dateShouldEnd
        case .topicWords, .pattern: return true
        case .grammar:              return !practiceQuestions.isEmpty
                                    && practiceAnswers.count >= practiceQuestions.count
        case .speaking:
            // Speaking-шаг закрывается:
            //  • обычный режим (сервер прислал practice-turns) — когда все
            //    turns раскрыты (`isLectureFinished`);
            //  • fallback-режим (сервер прислал только сценарий, диалог
            //    через GPT) — когда набрано `speakingFreeChatExchanges`
            //    ответов учительницы.
            if isSpeakingFreeChatMode {
                return speakingExchangeCount >= Self.speakingFreeChatExchanges
            }
            return isLectureFinished || messages.contains { $0.role == .user }
        }
    }

    /// Тап кнопки «Finish lesson» / «Continue». Гарантированно пытается
    /// закрыть попытку на сервере и обновить локальный `completedStepIds`:
    /// 1) если `sessionStart` не поставлен (первый POST не прошёл раньше) —
    ///    пробуем `startSession` ещё раз;
    /// 2) шлём `finishSession(completed: true)`;
    /// 3) оптимистично добавляем step.id в локальный profile — даже если
    ///    сервер лежит, UI показывает Done;
    /// 4) вызываем `onDone` → view делает `dismiss()`.
    func finishLesson(onDone: @escaping @MainActor () -> Void) {
        guard sessionFinish == nil else {
            markStepCompletedLocally()
            onDone()
            return
        }
        Task {
            if !didStartOnServer { await startSession() }
            await finishSession(completed: true)
            markStepCompletedLocally()
            onDone()
        }
    }

    /// Оптимистичное локальное обновление `completedStepIds` — чтобы Home
    /// показал Done даже если `syncMe` не долетел (offline/500).
    /// При следующем `syncMe` сервер станет source of truth и всё выровняется.
    private func markStepCompletedLocally() {
        guard let profile = user.activeLearningProfile else { return }
        if !profile.completedStepIds.contains(step.id) {
            profile.completedStepIds.append(step.id)
        }
    }

    // MARK: - Score sheet actions (Figma 373:2263)

    /// «Once more» — юзер хочет попробовать сказать ещё раз. Закрываем sheet,
    /// возвращаемся к записи. TODO: подцепить сброс transcript + переход в .recording.
    func scoreOnceMore() {
        showScoreSheet = false
    }

    /// «Next» — принимаем скор, идём дальше.
    /// Отправляем финиш на бэк: если сервер вернул `heartWon: true` — вью
    /// его увидит через `sessionFinish` и разово покажет анимацию.
    func scoreNext() {
        showScoreSheet = false
        lastScore = nil
        Task { await finishSession(completed: true) }
    }

    // MARK: - Session lifecycle

    /// Регистрируем попытку прохождения шага на сервере. Вью зовёт из
    /// `.task { }` — один раз при открытии.
    ///
    /// - 200 → сохраняем `sessionStart` (в нём `remainingLessons` /
    ///   `resetsAt` для отображения баннеров).
    /// - 402 → нужен premium; `sessionAbort = .paywallRequired`.
    /// - 409 → шаг уже пройден/закрыт; `.stepConflict`, вью зовёт syncMe и
    ///   уходит с экрана.
    /// - 429 → дневная квота; `.quotaExhausted(resetsAt:)`.
    /// - прочее (сеть) — молча, юзер работает оффлайн; финиш не пойдёт.
    /// Сервер зарегистрировал попытку с нашим `sessionAttemptId` (2xx на POST).
    /// Отдельный флаг от `sessionStart`, потому что POST может вернуть
    /// `200` без тела при идемпотентном replay-е — `sessionStart` тогда nil,
    /// но серверная попытка есть и PATCH финиша пройдёт.
    var didStartOnServer: Bool = false

    func startSession() async {
        guard !didStartOnServer, sessionAbort == nil, !isStartingSession else { return }
        isStartingSession = true
        defer { isStartingSession = false }
        sessionStartedAt = .now
        do {
            let dto = try await SessionAPI.start(.init(
                id: sessionAttemptId.uuidString,
                languageCode: language.rawValue,
                unitId: unitId,
                stepId: step.id,
                teacher: teacher.rawValue
            ))
            sessionStart = dto
            didStartOnServer = true
        } catch APIError.paymentRequired {
            sessionAbort = .paywallRequired
        } catch APIError.conflict {
            sessionAbort = .stepConflict
        } catch let APIError.rateLimited(_, _, resetsAt) {
            sessionAbort = .quotaExhausted(resetsAt: resetsAt)
        } catch {
            // Сеть — оставляем юзера в уроке; следующий finish повторит start.
        }
    }

    /// Закрыть попытку. `completed: true` — юзер тапнул Next после успеха;
    /// `completed: false` — просто ушёл с экрана.
    ///
    /// Идемпотентно: сервер игнорирует повторный финиш той же сессии.
    /// Если стартовать не удалось (sessionStart == nil) — не шлём, потому
    /// что сервер не знает про эту попытку.
    func finishSession(completed: Bool) async {
        guard sessionFinish == nil else { return }
        // Без серверного старта сервер не знает про попытку — синкаем /me
        // и уходим. Локальное дополнение шага делается на вызывающей
        // стороне через `markStepCompletedLocally`.
        guard didStartOnServer else {
            await AuthService.shared.syncMe()
            return
        }
        let seconds = elapsedSeconds
        do {
            let dto = try await SessionAPI.finish(
                id: sessionAttemptId.uuidString,
                .init(durationSeconds: seconds, completed: completed)
            )
            sessionFinish = dto
            applyProgressDelta(dto.progress)
            // Прогресс на сервере поменялся — тянем свежий Me чтобы обновить
            // completedStepIds/hearts/streak в UI.
            await AuthService.shared.syncMe()
            // Free-юзер завершил step → тратим одну «бесплатную попытку» из
            // 24-часового окна. Enforcement на сервере всё равно шлёт 402
            // на 2-й старт, но локальный счётчик нужен чтобы Home и AllUnits
            // сразу нарисовали timer pill вместо Continue и открыли
            // dailyLimitSheet без похода в сеть. Premium не тратим — им
            // квота не касается.
            if completed, !isPremium {
                LessonQuotaService.shared.recordStepCompleted()
            }
            // Финальная оценка — фоновая, не блокирует переход к следующему шагу.
            if completed { Task { await evaluateSession() } }
            // Date-шаг на free → предложить продолжить свидание в свободном
            // чате (Figma 762:2511, .dating).
            // Не-date шаг на free → «You stopped one step before the good part»
            // (Figma 762:2568, .lesson_end).
            if completed, !isPremium {
                if isDateStep {
                    shouldShowDateContinuePaywall = true
                } else {
                    shouldShowLessonEndPaywall = true
                }
            }
        } catch {
            // 409 (уже финиш) или сеть — синкаем /me чтобы UI подхватил
            // completedStepIds если сервер уже засчитал попытку.
            await AuthService.shared.syncMe()
        }
    }

    /// Флаг «показать `.dating` пейвол по завершении date-шага». Вью подписан
    /// через `.onChange`, вызывает `premium.showPaywall(.dating)` и
    /// `dismiss()`.
    var shouldShowDateContinuePaywall: Bool = false

    /// Флаг «показать `.lesson_end` пейвол по завершении обычного шага
    /// (не-date) на free-плане». Дёргается тем же путём что и date-версия.
    var shouldShowLessonEndPaywall: Bool = false

    /// `POST /v1/ai/evaluate-session` — итоговая оценка урока по всему transcript.
    /// Результат сохраняется в `sessionEvaluation` для отображения в score sheet /
    /// UnitCompletion. Не критично: если сервер ошибётся — покажем локальный mock.
    private func evaluateSession() async {
        let transcript: [AiAPI.TranscriptLine] = messages.map {
            AiAPI.TranscriptLine(
                role: $0.role == .assistant ? "teacher" : "user",
                text: $0.text,
                audioUrl: audioUrlByMessageId[$0.id]?.absoluteString
            )
        }
        do {
            sessionEvaluation = try await AiAPI.evaluateSession(.init(
                sessionAttemptId: sessionAttemptId.uuidString,
                transcript: transcript.isEmpty ? nil : transcript
            ))
        } catch {
            // Молчим — evaluate-session — polish, не критично.
        }
    }

    /// Применить `ProgressDelta` к in-lesson состоянию. Reactive-обновление
    /// глобального `user.activeRelationship.affinity` идёт через `syncMe()`.
    private func applyProgressDelta(_ delta: ProgressDeltaDTO) {
        affinityLevel = max(1, min(5, delta.teacherHearts ?? affinityLevel))
        heartsFilled  = affinityLevel
        lastAverageScore = delta.averageScore
        if delta.heartWon == true {
            triggerReaction(.correct)
        }
    }

    /// Вьюха зовёт при уходе с экрана (`onDisappear`). Best-effort финиш
    /// с `completed: false`, если сессия существовала и ещё не закрыта.
    func abandonIfActive() async {
        guard didStartOnServer, sessionFinish == nil else { return }
        await finishSession(completed: false)
    }

    // MARK: - Nested

    enum InputMode: Equatable {
        case buttons          // Text · Speak · Hint (дефолт, 373:2077)
        case text             // TextField + mic (373:4129)
        case recording        // Cancel · [equalizer pink] + lock hint (373:4741)
        case recordingStopped // Cancel · [up-arrow pink send]        (373:4831)
    }

    /// Категория voice-ошибки. Пока один case; расширять когда бэк начнёт
    /// отдавать разные типы (шум, обрыв, недостаточно данных и т.п.).
    enum VoiceError: Equatable, Sendable {
        case tooQuiet
    }

    // MARK: - Voice error actions (Figma 373:4511)

    /// Сбросить ошибку и переключиться в text-режим — юзер выбрал печатать.
    func dismissVoiceErrorAndType() {
        voiceError = nil
        withAnimation(Self.modeTransition) { inputMode = .text }
    }

    /// Сбросить ошибку и переключиться в recording — повторная запись.
    /// TODO: подцепить `speech.startRecording(language:)` когда будет команда.
    func retryRecording() {
        voiceError = nil
        withAnimation(Self.modeTransition) { inputMode = .recording }
    }

    // MARK: - Private

    private func formatMMSS(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return "\(m):" + String(format: "%02d", s)
    }
}
