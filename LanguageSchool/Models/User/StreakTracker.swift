import Foundation

nonisolated
enum Weekday: Int, Codable, CaseIterable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    static func from(date: Date, calendar: Calendar = .current) -> Weekday {
        Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .sunday
    }
}

nonisolated
struct StreakTracker: Codable, Hashable, Sendable {
    var currentStreak: Int
    var bestStreak: Int
    var lastActiveDay: Date?
    var activeDaysThisWeek: Set<Weekday>

    static let empty = StreakTracker(
        currentStreak: 0,
        bestStreak: 0,
        lastActiveDay: nil,
        activeDaysThisWeek: []
    )
}
