import Foundation

nonisolated
enum ReminderDays: String, Codable, CaseIterable, Identifiable, Sendable {
    case everyDay
    case monFri
    case weekends

    var id: Self { self }

    var displayTitle: String {
        switch self {
        case .everyDay: "Every day"
        case .monFri:   "Mon–Fri"
        case .weekends: "Weekends"
        }
    }
}
