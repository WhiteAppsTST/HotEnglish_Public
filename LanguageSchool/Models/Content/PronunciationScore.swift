import Foundation

/// Результат оценки произношения (Figma 373:2263). Отдаётся бэком (или GPT)
/// в ответ на голосовое сообщение юзера. Открывается тапом на Hint если у
/// юзера есть последнее голосовое/текстовое сообщение — вместо стандартного
/// «Need a hint?» sheet-а.
/// TODO: заменить моки на fetch — POST /content/score с audio-blob и получением
/// PronunciationScore с бэка.
nonisolated
struct PronunciationScore: Hashable, Sendable {
    /// Балл 0…100. В UI большая зелёная/жёлтая/красная цифра.
    let score: Int
    /// Максимум (обычно 100).
    let totalPossible: Int

    /// Короткий вердикт: «You'll be understood».
    let verdict: String
    /// Уточняющий подзаголовок: «One word needs work».
    let subVerdict: String

    /// Распознанный transcript в зелёном стиле (успешные части).
    let cleanTranscript: String
    /// Подпись под clean transcript (Figma 373:2263):
    /// «Green means clean, yellow means noticeable accent».
    let accentHint: String

    /// Полезный совет по акценту («The c in "conocerte" is a soft th …»).
    let feedback: String
}

// MARK: - Mock

enum ScoreContent {

    /// Мок под макет 373:2263. TODO: заменить на реальный ответ от бэка.
    static func mockScore(for language: LanguageCode) -> PronunciationScore {
        switch language {
        case .es:
            return PronunciationScore(
                score: 82,
                totalPossible: 100,
                verdict: "You'll be understood",
                subVerdict: "One word needs work",
                cleanTranscript: "¡Hola a todos!, soy Evan.",
                accentHint: "Green means clean, yellow means noticeable accent",
                feedback: "The c in “conocerte” is a soft th in Spain: co-no-THER-te."
            )
        case .en:
            return PronunciationScore(
                score: 82,
                totalPossible: 100,
                verdict: "You'll be understood",
                subVerdict: "One word needs work",
                cleanTranscript: "Hello everyone, I'm Evan.",
                accentHint: "Green means clean, yellow means noticeable accent",
                feedback: "The th in “everyone” is a soft th: ev-ree-won."
            )
        }
    }
}
