import Foundation

/// Реакция учителя на действие ученика в Practice-фазе.
/// Маппится на `TeacherProfile.LessonState` (видео) и опциональный
/// `SoundEffect` (короткий SFX), которые проигрывает `AvatarPlayer`.
nonisolated
enum LessonReaction: Sendable {
    case correct
    case wrong
    /// Учительница «говорит» — проигрывается пока звучит её реплика (autoplay
    /// teacher audio). После окончания audio VM возвращает idle-видео.
    case talking

    var lessonState: TeacherProfile.LessonState {
        switch self {
        case .correct: return .correctAnswer
        case .wrong:   return .wrongAnswer
        case .talking: return .talking
        }
    }

    var soundEffect: TeacherProfile.SoundEffect? {
        switch self {
        case .correct: return .smile
        case .wrong:   return .thinking
        case .talking: return nil
        }
    }
}
