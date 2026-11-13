import Foundation
import SwiftData

@MainActor
@Observable
final class TalkViewModel {

    // MARK: - Config

    static let freeTextsPerDay = 3
    static let limitWindow: TimeInterval = 24 * 3600
    /// Сколько последних сообщений отправляем в контекст. Ограничиваем чтобы не жечь токены.
    private static let historyContextLimit = 30

    // MARK: - Deps

    let user: UserEntity
    private let repository: UserRepository
    private let context: ModelContext
    private let chat: AIChatServicing?
    let speech: SpeechDictationService

    // MARK: - Observable state

    var messages: [AIMessage] = []
    var inputText: String = ""
    var isSending = false
    var error: String?
    var showPaywall = false

    /// Последняя реакция учителя, пришедшая с GPT-ответом. View подписывается
    /// через onChange и триггерит `AvatarPlayer.playOnce(reactionVideo)`.
    /// Каждый новый ответ поднимает `reactionTick`, чтобы одинаковые reaction'ы
    /// подряд тоже вызывали проигрыш.
    var lastReaction: TalkReaction?
    var reactionTick: Int = 0

    /// Кэш переводов по messageId. nil = ещё не переведено. Пустая строка =
    /// перевод грузится (используется чтобы показать плейсхолдер).
    var translations: [String: String] = [:]
    var translatingIds: Set<String> = []

    /// URL озвучки каждой реплики учительницы (messageId → mp3 с сервера
    /// `/v1/ai/tts`). Пустой словарь при загрузке из disk-истории —
    /// восстанавливаемые реплики без аудио (юзер может дожать speaker
    /// вручную, чтобы догрузить). Свежие реплики от GPT сразу получают
    /// свой TTS в `send()` и попадают сюда.
    var audioUrlByMessageId: [String: URL] = [:]
    /// id реплики, для которой сейчас играет аудио (используем чтобы
    /// подсветить speaker-иконку розовым в UI). nil — тишина.
    var playingMessageId: String?
    /// Плеер поверх AVAudioPlayer. Общий для всех реплик — новый play
    /// автоматически останавливает предыдущий (см. `PlaybackService.play`).
    let remoteAudio = PlaybackService()

    // MARK: - Init

    init(user: UserEntity, repository: UserRepository, context: ModelContext) {
        self.user = user
        self.repository = repository
        self.context = context
        self.speech = SpeechDictationService()
        do {
            self.chat = try AIChatService()
        } catch {
            self.chat = nil
            self.error = (error as? AIChatError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Derived

    /// Точка подключения будущего SubscriptionService.
    /// Источник правды по премиуму — `SubscriptionService` (Apphud +
    /// серверный webhook). `user.isPremium` — только зеркало /me, гейтить
    /// им нельзя (отстаёт от Apphud сразу после покупки).
    var isPremium: Bool { SubscriptionService.shared.isActiveSubscription }

    var teacher: TeacherProfile { user.settings.selectedTeacher }
    var language: LanguageCode { user.settings.currentLearningLanguage }
    var relationship: TeacherRelationshipEntity? { user.activeRelationship }
    var hearts: Int { relationship?.heartsForUI ?? 0 }

    var freeTextsUsed: Int {
        refreshLimitIfExpired()
        return defaults.integer(forKey: Key.freeTextsUsed)
    }

    var freeTextsRemaining: Int { max(0, Self.freeTextsPerDay - freeTextsUsed) }
    var quotaExhausted: Bool { !isPremium && freeTextsRemaining == 0 }

    var canSend: Bool {
        !isSending
        && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (isPremium || freeTextsRemaining > 0)
    }

    var voiceLocked: Bool { !isPremium }

    /// Локализованный текст "{имя} печатает" для typing-индикатора,
    /// на языке который юзер изучает.
    var typingLabel: String {
        switch language {
        case .en: return "\(teacher.name) is typing"
        case .es: return "\(teacher.name) está escribiendo"
        }
    }

    // MARK: - Lifecycle

    func onAppear() async {
        ensureRelationship()
        refreshLimitIfExpired()
        loadHistoryFromDisk()
        if let rel = relationship, rel.talkUnreadCount != 0 {
            rel.talkUnreadCount = 0
            repository.save()
        }
        if messages.isEmpty {
            messages.append(fallbackGreeting)
        }
    }

    /// Ленивое создание (teacher × language) связки при первом заходе в Talk
    /// после смены языка/учительницы. Без этого `send()` молча ретёрнит,
    /// потому что `activeRelationship == nil`.
    private func ensureRelationship() {
        guard relationship == nil else { return }
        let new = TeacherRelationshipEntity(
            teacher: teacher,
            languageCode: language
        )
        new.user = user
        user.teacherRelationships.append(new)
        context.insert(new)
        repository.save()
    }

    func onDisappear() {
        speech.stopRecording()
        remoteAudio.stop()
        playingMessageId = nil
    }

    private var fallbackGreeting: AIMessage {
        let text: String
        switch language {
        case .en: text = "Tell me something you didn't tell anyone today."
        case .es: text = "Cuéntame algo que no le hayas contado a nadie hoy."
        }
        return AIMessage(
            id: "fallback-greeting-\(language.rawValue)",
            role: .assistant,
            text: text,
            createdAt: .now
        )
    }

    // MARK: - History persistence

    private func loadHistoryFromDisk() {
        guard let raw = relationship?.talkHistoryJSON, let data = raw.data(using: .utf8) else { return }
        let decoded = try? JSONDecoder.chatDecoder.decode([AIMessage].self, from: data)
        if let decoded { messages = decoded }
    }

    private func saveHistoryToDisk() {
        guard let relationship else { return }
        // Не сохраняем фолбек-приветствие (у него id с префиксом "fallback-")
        // и локальные оптимистичные user-баблы (id "local-"). Только реальные.
        let real = messages.filter { !$0.id.hasPrefix("fallback-") }
        guard let data = try? JSONEncoder.chatEncoder.encode(real) else { return }
        relationship.talkHistoryJSON = String(data: data, encoding: .utf8)
        relationship.updatedAt = .now
        repository.save()
    }

    // MARK: - Send text

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard relationship != nil else { return }

        refreshLimitIfExpired()
        guard isPremium || freeTextsRemaining > 0 else {
            openPaywall()
            return
        }
        guard let chat else {
            self.error = L10n.tr("error.ai_unavailable", "AI unavailable — set OPENAI_API_KEY in Info.plist")
            return
        }

        inputText = ""
        isSending = true
        defer { isSending = false }

        let userMessage = AIMessage(
            id: UUID().uuidString,
            role: .user,
            text: text,
            createdAt: .now
        )
        messages.append(userMessage)

        if !isPremium {
            let newUsed = defaults.integer(forKey: Key.freeTextsUsed) + 1
            defaults.set(newUsed, forKey: Key.freeTextsUsed)
            if newUsed >= Self.freeTextsPerDay {
                defaults.set(Date().timeIntervalSince1970, forKey: Key.limitStartedAt)
            }
        }

        // Собираем контекст: system + последние N сообщений истории.
        let historyForContext = messages
            .filter { !$0.id.hasPrefix("fallback-") }
            .suffix(Self.historyContextLimit)

        do {
            let (reply, reaction) = try await chat.sendWithReaction(
                history: Array(historyForContext),
                systemPrompt: teacher.talkSystemPrompt(for: language, userName: user.name),
                model: AIChatService.defaultModel
            )
            // Озвучка ответа: тем же путём что и в Lesson/Date — сначала
            // тянем TTS в кэш, потом атомарно вставляем бабл в чат и
            // запускаем autoplay. Если TTS упал/недоступен — реплика
            // всё равно появится, просто без звука.
            await emitAssistantReplySynced(reply: reply, reaction: reaction)
            relationship?.lastInteractionAt = .now
            saveHistoryToDisk()
        } catch {
            self.error = (error as? AIChatError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Audio (TTS + playback)

    /// Собрать реплику учителя в чат «синхронно» с озвучкой: если сервер
    /// вернул audioUrl — сначала прекачиваем файл в диск-кэш и только
    /// потом вставляем сам бабл + autoplay. Это гарантирует, что юзер
    /// видит новое сообщение ровно тогда, когда голос готов заиграть,
    /// а не «текст → пауза → звук». Точно тот же паттерн, что в
    /// `LessonViewModel.emitTeacherReplySynced`.
    private func emitAssistantReplySynced(reply: AIMessage, reaction: TalkReaction?) async {
        if let url = await requestTTS(text: reply.text) {
            audioUrlByMessageId[reply.id] = url
            _ = await RemoteAudioCache.localURL(for: url)
        }
        messages.append(reply)
        lastReaction = reaction ?? .talking
        reactionTick &+= 1
        if audioUrlByMessageId[reply.id] != nil {
            await autoplayIfEnabled(messageId: reply.id)
        }
    }

    /// Обёртка над `/v1/ai/tts`: text → mp3 url в голосе текущего учителя.
    /// Значения teacher/language берём из `user.settings`. Любая ошибка
    /// (сеть, 4xx, отсутствие ключа) → `nil`, вызывающий покажет реплику
    /// без озвучки.
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

    /// Проиграть озвучку конкретной реплики. Если URL ещё нет в
    /// `audioUrlByMessageId` (например реплика из disk-истории) —
    /// делаем ленивый TTS-запрос и кэшируем на будущее.
    func playAudio(for message: AIMessage) async {
        if let url = audioUrlByMessageId[message.id] {
            await playRemote(url: url, id: message.id)
            return
        }
        guard let url = await requestTTS(text: message.text) else { return }
        audioUrlByMessageId[message.id] = url
        await playRemote(url: url, id: message.id)
    }

    /// Автовоспроизведение реплики учительницы, если в настройках включён
    /// `autoplayTeacherAudio`. Дёргается сразу после `emitAssistantReplySynced`.
    func autoplayIfEnabled(messageId: String) async {
        guard user.settings.autoplayTeacherAudio else { return }
        guard let url = audioUrlByMessageId[messageId] else { return }
        await playRemote(url: url, id: messageId)
    }

    /// Универсальный проигрыш: кэширует файл, стартует плеер, снимает
    /// `playingMessageId` через 3с (у AVAudioPlayer нет completion без
    /// делегата — этой задержки хватает для короткой TTS-фразы). Новый
    /// play прерывает старый — PlaybackService.play делает stop сам.
    func playRemote(url: URL, id: String) async {
        remoteAudio.stop()
        playingMessageId = id
        guard let local = await RemoteAudioCache.localURL(for: url) else {
            if playingMessageId == id { playingMessageId = nil }
            return
        }
        remoteAudio.play(url: local, id: id)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if playingMessageId == id { playingMessageId = nil }
        }
    }

    // MARK: - Voice (STT)

    func toggleMic() async {
        if !isPremium {
            showPaywall = true
            return
        }
        if speech.isRecording {
            speech.stopRecording()
            let transcript = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !transcript.isEmpty {
                inputText = transcript
                await send()
            }
        } else {
            let status = await speech.requestAuthorization()
            guard status == .authorized else {
                error = L10n.tr("error.speech_permission_required", "Speech recognition permission required")
                return
            }
            do {
                try await speech.startRecording(language: language)
            } catch {
                self.error = (error as? SpeechDictationError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - Translation

    /// Куда переводим ответ ассистента. Если у юзера в настройках стоит тот же
     /// язык, что и язык чата — фолбэчимся на "другой поддерживаемый", иначе
     /// перевод бессмыслен (переводит на тот же язык).
    var effectiveTranslationLanguage: LanguageCode {
        let target = user.settings.translationLanguage
        guard target != language else {
            return language == .en ? .es : .en
        }
        return target
    }

    func toggleTranslation(for message: AIMessage) async {
        if translations[message.id] != nil {
            translations.removeValue(forKey: message.id)
            return
        }
        guard let chat else {
            self.error = L10n.tr("error.ai_unavailable", "AI unavailable — set OPENAI_API_KEY in Info.plist")
            return
        }
        guard !translatingIds.contains(message.id) else { return }
        translatingIds.insert(message.id)
        defer { translatingIds.remove(message.id) }

        do {
            let target = effectiveTranslationLanguage
            let system = "You are a translator. Translate the following text into \(target.displayTitle). Reply only with the translation, no comments, no quotes."
            let user = AIMessage(id: UUID().uuidString, role: .user, text: message.text, createdAt: .now)
            let reply = try await chat.send(
                history: [user],
                systemPrompt: system,
                model: AIChatService.defaultModel
            )
            translations[message.id] = reply.text
        } catch {
            self.error = (error as? AIChatError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Paywall

    func openPaywall() {
        showPaywall = true
    }

    // MARK: - Limit window (24h, persistent)

    private func refreshLimitIfExpired() {
        let used = defaults.integer(forKey: Key.freeTextsUsed)
        guard used >= Self.freeTextsPerDay else { return }
        let startedAt = defaults.double(forKey: Key.limitStartedAt)
        guard startedAt > 0 else { return }
        let elapsed = Date().timeIntervalSince1970 - startedAt
        if elapsed >= Self.limitWindow {
            defaults.set(0, forKey: Key.freeTextsUsed)
            defaults.removeObject(forKey: Key.limitStartedAt)
        }
    }

    // MARK: - Storage

    private var defaults: UserDefaults { .standard }
    private enum Key {
        static let freeTextsUsed  = "talk.freeTexts.used"
        static let limitStartedAt = "talk.freeTexts.limitStartedAt"
    }

    // MARK: - Cross-screen queries

    /// Свободные тексты в свободном чате, оставшиеся на текущее 24ч-окно.
    /// Использует те же UserDefaults что и инстанс-геттеры. Позволяет
    /// HomeViewModel показывать актуальный бейдж/цвет Talk-кнопки без
    /// создания инстанса TalkViewModel.
    static func freeTextsRemaining() -> Int {
        let defaults = UserDefaults.standard
        let used = defaults.integer(forKey: Key.freeTextsUsed)
        let startedAt = defaults.double(forKey: Key.limitStartedAt)
        var effectiveUsed = used
        if used >= freeTextsPerDay, startedAt > 0 {
            let elapsed = Date().timeIntervalSince1970 - startedAt
            if elapsed >= limitWindow { effectiveUsed = 0 }
        }
        return max(0, freeTextsPerDay - effectiveUsed)
    }
}

private extension JSONEncoder {
    static let chatEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let chatDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
