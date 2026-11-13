import Foundation

nonisolated
enum LearningGoal: String, Codable, CaseIterable, Identifiable, Sendable {
    case work
    case movingAbroad
    case exam
    case travel
    case toTalkToTeacher
    case somethingElse

    var id: Self { self }

    var displayTitle: String {
        switch self {
        case .work:            L10n.tr("goal.work", "Work")
        case .movingAbroad:    L10n.tr("goal.moving_abroad", "Moving abroad")
        case .exam:            L10n.tr("goal.exam", "An exam")
        case .travel:          L10n.tr("goal.travel", "Travel")
        case .toTalkToTeacher: L10n.tr("goal.to_talk_to_you", "To talk to you")
        case .somethingElse:   L10n.tr("goal.something_else", "Something else")
        }
    }
}
