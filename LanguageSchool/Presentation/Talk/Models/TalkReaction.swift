import Foundation

/// Реакция учителя, которую GPT возвращает в JSON-ответе для Talk-чата.
/// Маппится на `TeacherProfile.LessonState` для проигрывания соответствующего
/// видео через `AvatarPlayer`.
///
/// Синтаксис от GPT: `{"text": "...", "reaction": "talking"}` — reaction это
/// rawValue одного из кейсов ниже. Если reaction пустой/невалидный —
/// фолбэчимся на `.talking` (нейтральное "говорит").
nonisolated
enum TalkReaction: String, Codable, Sendable, CaseIterable {
    case talking
    case flirting
    case correct
    case wrong
    case idle

    var lessonState: TeacherProfile.LessonState {
        switch self {
        case .talking:  return .talking
        case .flirting: return .flirting
        case .correct:  return .correctAnswer
        case .wrong:    return .wrongAnswer
        case .idle:     return .idle
        }
    }

    /// Опциональный короткий SFX, который играется параллельно с видео-реакцией.
    /// `talking` и `idle` — немые (нейтральный/фоновый ответ).
    var soundEffect: TeacherProfile.SoundEffect? {
        switch self {
        case .flirting: return .flirting
        case .correct:  return .smile
        case .wrong:    return .thinking
        case .talking, .idle: return nil
        }
    }

    /// Список допустимых значений для описания в system-prompt'е.
    static var promptListing: String {
        allCases.map(\.rawValue).joined(separator: ", ")
    }
}
