import Foundation

@MainActor
@Observable
final class NotificationsViewModel {

    private enum Key {
        static let remindMeToPractise = "notif.remindMeToPractise"
        static let reminderHour       = "notif.reminder.hour"
        static let reminderMinute     = "notif.reminder.minute"
        static let reminderDays       = "notif.reminder.days"
        static let streakAboutToBreak = "notif.streak.aboutToBreak"
        static let newUnitUnlocked    = "notif.unit.new"
        static let emmaWritesFirst    = "notif.emma.writesFirst"
        static let productNews        = "notif.productNews"
        static let initialized        = "notif.initialized"
    }

    private let defaults: UserDefaults = .standard
    private let reminderService: LessonReminderScheduling

    // MARK: - Init

    init(reminderService: LessonReminderScheduling? = nil) {
        self.reminderService = reminderService ?? LessonReminderService()
        seedDefaultsIfNeeded()
    }

    // MARK: - Persisted flags (backed by UserDefaults — device-local)

    var remindMeToPractise: Bool {
        get { defaults.bool(forKey: Key.remindMeToPractise) }
        set {
            defaults.set(newValue, forKey: Key.remindMeToPractise)
            syncSystemReminder()
            syncBackend()
        }
    }

    var reminderHour: Int {
        get { defaults.integer(forKey: Key.reminderHour) }
        set {
            defaults.set(newValue, forKey: Key.reminderHour)
            syncSystemReminder()
            syncBackend()
        }
    }

    var reminderMinute: Int {
        get { defaults.integer(forKey: Key.reminderMinute) }
        set {
            defaults.set(newValue, forKey: Key.reminderMinute)
            syncSystemReminder()
            syncBackend()
        }
    }

    var reminderDays: ReminderDays {
        get {
            let raw = defaults.string(forKey: Key.reminderDays) ?? ReminderDays.monFri.rawValue
            return ReminderDays(rawValue: raw) ?? .monFri
        }
        set { defaults.set(newValue.rawValue, forKey: Key.reminderDays) }
    }

    var streakAboutToBreak: Bool {
        get { defaults.bool(forKey: Key.streakAboutToBreak) }
        set { defaults.set(newValue, forKey: Key.streakAboutToBreak) }
    }

    var newUnitUnlocked: Bool {
        get { defaults.bool(forKey: Key.newUnitUnlocked) }
        set { defaults.set(newValue, forKey: Key.newUnitUnlocked) }
    }

    var emmaWritesFirst: Bool {
        get { defaults.bool(forKey: Key.emmaWritesFirst) }
        set { defaults.set(newValue, forKey: Key.emmaWritesFirst) }
    }

    var productNews: Bool {
        get { defaults.bool(forKey: Key.productNews) }
        set { defaults.set(newValue, forKey: Key.productNews) }
    }

    // MARK: - Derived

    var reminderTimeText: String {
        String(format: "%02d:%02d", reminderHour, reminderMinute)
    }

    var reminderTimeDate: Date {
        var comps = DateComponents()
        comps.hour = reminderHour
        comps.minute = reminderMinute
        return Calendar.current.date(from: comps) ?? .now
    }

    func applyReminderDate(_ date: Date) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        reminderHour = comps.hour ?? 19
        reminderMinute = comps.minute ?? 0
    }

    // MARK: - System sync

    private func syncSystemReminder() {
        if remindMeToPractise {
            var comps = DateComponents()
            comps.hour = reminderHour
            comps.minute = reminderMinute
            reminderService.scheduleDaily(at: comps) { _ in }
        } else {
            reminderService.cancel()
        }
    }

    /// Отправляем текущие reminder-поля на бэк. Тумблеры «streak/newUnit/emma
    /// writes first/product news» остаются device-local (сервер их не хранит).
    private func syncBackend() {
        let enabled = remindMeToPractise
        let hour = reminderHour
        let minute = reminderMinute
        Task {
            _ = try? await MeAPI.updateSettings(.init(
                reminder: enabled ? .init(hour: hour, minute: minute) : nil,
                disableReminder: !enabled
            ))
        }
    }

    // MARK: - Defaults seeding

    private func seedDefaultsIfNeeded() {
        guard !defaults.bool(forKey: Key.initialized) else { return }
        defaults.set(true,  forKey: Key.remindMeToPractise)
        defaults.set(19,    forKey: Key.reminderHour)
        defaults.set(0,     forKey: Key.reminderMinute)
        defaults.set(ReminderDays.monFri.rawValue, forKey: Key.reminderDays)
        defaults.set(true,  forKey: Key.streakAboutToBreak)
        defaults.set(true,  forKey: Key.newUnitUnlocked)
        defaults.set(false, forKey: Key.emmaWritesFirst)
        defaults.set(false, forKey: Key.productNews)
        defaults.set(true,  forKey: Key.initialized)
    }
}
