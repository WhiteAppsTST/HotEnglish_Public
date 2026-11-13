import Foundation

/// Один Practice-вопрос. Два вида: заполни пропуск в предложении (grammar) и
/// прослушай аудио → выбери что было сказано (listen-choose).
/// TODO: заменить моки на fetch `GET /content/practice/{stepId}?languageCode=...`
nonisolated
struct PracticeQuestion: Identifiable, Hashable, Sendable {

    enum Kind: String, Sendable {
        case fillBlank      // Figma 373:3665 — grammar: подставить слово в пропуск
        case listenChoose   // Figma 373:4010 — прослушать аудио → выбрать вариант
        case wordOrder      // Figma 373:3761 — расставить слова в правильном порядке
        case describeImage  // Figma 373:3933 — описать картинку одним предложением
    }

    let id: String
    let kind: Kind

    /// 1-based индекс вопроса. Показывается как «Question N of M».
    let index: Int
    let total: Int

    // MARK: - Grammar (kind == .fillBlank)

    /// Предложение с пропуском, например «Ayer ____ al cine con mis amigos.»
    /// Подчёркивание/пропуск делаем через строку `____` — вьюха рендерит как есть.
    let promptNative: String?
    let promptTranslation: String?

    // MARK: - Listen-choose (kind == .listenChoose)

    /// Инструкция сверху audio-player'а, например «Listen, then choose what I said».
    let instruction: String?
    /// URL или файл-имя аудио. TODO: заменить на URL с бэка.
    let audioName: String?
    /// Длительность аудио в секундах для лейбла «0:02».
    let audioDurationSeconds: TimeInterval?

    // MARK: - Word order (kind == .wordOrder)

    /// Подсказочный subtitle сверху карточки: «Put the words in order».
    let wordOrderSubtitle: String?
    /// Правильный порядок слов: `["Me", "gustaría", "hablar", "contigo"]`.
    let expectedOrder: [String]?
    /// Все слова в word-bank (включая distractors), перемешанные.
    let wordBank: [String]?

    // MARK: - Describe image (kind == .describeImage)

    /// Prompt: «Tell me what you see. One sentence is enough.»
    let describePrompt: String?
    /// Имя ассета картинки/видео. TODO: заменить на URL с бэка.
    let describeImageName: String?

    // MARK: - Common

    let options: [PracticeOption]

    /// id правильной опции. TODO: убрать когда GPT будет валидировать ответы.
    let correctOptionId: String
}

/// Один вариант ответа. `label` — префикс: «A»/«B»/«C» для grammar, «1»/«2»/«3»
/// для listen-choose (в Figma рендерится по-разному).
nonisolated
struct PracticeOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let text: String
}

// MARK: - Mock

/// TODO: заменить на fetch с бэка. Мок под макет 373:3665.
enum PracticeContent {

    static func grammarMock(index: Int = 1, total: Int = 6) -> PracticeQuestion {
        PracticeQuestion(
            id: "practice_grammar_\(index)",
            kind: .fillBlank,
            index: index,
            total: total,
            promptNative: "Ayer ____ al cine con mis amigos.",
            promptTranslation: "Yesterday I ____ to the cinema with my friends.",
            instruction: nil,
            audioName: nil,
            audioDurationSeconds: nil,
            wordOrderSubtitle: nil,
            expectedOrder: nil,
            wordBank: nil,
            describePrompt: nil,
            describeImageName: nil,
            options: [
                PracticeOption(id: "a", label: "A", text: "voy"),
                PracticeOption(id: "b", label: "B", text: "fui"),
                PracticeOption(id: "c", label: "C", text: "iré"),
                PracticeOption(id: "d", label: "D", text: "iba")
            ],
            correctOptionId: "b"
        )
    }

    /// TODO: подключить реальное аудио когда бэк отдаст URL.
    static func listenChooseMock(index: Int = 2, total: Int = 6) -> PracticeQuestion {
        PracticeQuestion(
            id: "practice_listen_\(index)",
            kind: .listenChoose,
            index: index,
            total: total,
            promptNative: nil,
            promptTranslation: nil,
            instruction: "Listen, then choose what I said",
            audioName: nil,
            audioDurationSeconds: 2,
            wordOrderSubtitle: nil,
            expectedOrder: nil,
            wordBank: nil,
            describePrompt: nil,
            describeImageName: nil,
            options: [
                PracticeOption(id: "1", label: "1", text: "Salí con unos amigos y volví tarde"),
                PracticeOption(id: "2", label: "2", text: "Salí con unos amigos y volví tarde"),
                PracticeOption(id: "3", label: "3", text: "Salí con unos amigos y volví tarde")
            ],
            correctOptionId: "1"
        )
    }

    /// TODO: заменить на fetch с бэка.
    static func wordOrderMock(index: Int = 3, total: Int = 5) -> PracticeQuestion {
        PracticeQuestion(
            id: "practice_wordorder_\(index)",
            kind: .wordOrder,
            index: index,
            total: total,
            promptNative: "I'd like to talk with you",
            promptTranslation: nil,
            instruction: nil,
            audioName: nil,
            audioDurationSeconds: nil,
            wordOrderSubtitle: "Put the words in order",
            expectedOrder: ["Me", "gustaría", "hablar", "contigo"],
            wordBank: ["Me", "gustaría", "contigo", "hablar", "mucho", "ahora"],
            describePrompt: nil,
            describeImageName: nil,
            options: [],
            correctOptionId: ""
        )
    }

    /// TODO: подключить реальные изображения когда бэк отдаст URLs.
    static func describeImageMock(index: Int = 4, total: Int = 6) -> PracticeQuestion {
        PracticeQuestion(
            id: "practice_describe_\(index)",
            kind: .describeImage,
            index: index,
            total: total,
            promptNative: nil,
            promptTranslation: nil,
            instruction: nil,
            audioName: nil,
            audioDurationSeconds: nil,
            wordOrderSubtitle: nil,
            expectedOrder: nil,
            wordBank: nil,
            describePrompt: "Tell me what you see. One sentence is enough.",
            describeImageName: nil,
            options: [],
            correctOptionId: ""
        )
    }
}

// MARK: - Practice stream (chat-like scroll)

/// Один элемент стрима Practice-фазы: либо вопрос с опциями, либо feedback-
/// сообщение от Emma. Добавляется в scroll снизу по мере прохождения.
nonisolated
enum PracticeStreamItem: Identifiable, Hashable, Sendable {
    case question(PracticeQuestion)
    case feedback(id: String, text: String, isCorrect: Bool)

    var id: String {
        switch self {
        case .question(let q):        return "q_\(q.id)"
        case .feedback(let id, _, _): return "f_\(id)"
        }
    }
}
