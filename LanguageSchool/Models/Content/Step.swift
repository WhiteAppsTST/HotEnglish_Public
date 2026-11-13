import Foundation

nonisolated
enum StepKind: String, Codable, Hashable, Sendable {
    case lecture
    case topicWords
    case pattern
    case grammar
    case speaking
    case date
}

nonisolated
enum StepUnlockRule: Hashable, Sendable {
    case afterStep(String)
}

/// Клиентская модель шага урока. `payload` — полиморфные данные шага
/// (Lecture/TopicWords/Pattern/Grammar/Speaking/Date), приходят с бэка в
/// `GET /v1/content/{lang}`. LessonViewModel разбирает по `kind`.
///
/// Hashable сделан by-id — иначе payload с вложенными массивами ломает
/// автосинтез.
struct Step: Identifiable, Sendable {
    let id: String
    let order: Int
    let kind: StepKind
    let title: String
    let subtitle: String
    let unlockRule: StepUnlockRule?
    /// Аудио на уровне шага (у бэка на самом деле аудио внутри payload'а —
    /// поле оставлено для совместимости, конкретный проигрыватель тянет URL
    /// из payload).
    let audioUrl: URL?
    /// Тело шага: `LecturePayload`/`TopicWordsPayload`/... — см. `StepPayloadDTO`.
    /// nil для локальных моков и тестов.
    let payload: StepPayloadDTO?
}

extension Step: Hashable {
    static func == (lhs: Step, rhs: Step) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Step {
    /// Совместимый init для мест где payload'а нет (мок, тесты).
    init(
        id: String,
        order: Int,
        kind: StepKind,
        title: String,
        subtitle: String,
        unlockRule: StepUnlockRule? = nil
    ) {
        self.init(
            id: id, order: order, kind: kind,
            title: title, subtitle: subtitle,
            unlockRule: unlockRule, audioUrl: nil, payload: nil
        )
    }
}
