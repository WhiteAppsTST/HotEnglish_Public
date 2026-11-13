import Foundation
import UserNotifications
import UIKit

enum LessonReminderStatus {
    case granted, denied, undetermined
}

@MainActor
protocol LessonReminderScheduling {
    func status(completion: @escaping @MainActor (LessonReminderStatus) -> Void)
    
    /// Запланировать ежедневное напоминание в указанное время.
    /// Если пермишенов нет — сначала попросит, потом запланирует.
    /// Если denied — откроет Настройки.
    func scheduleDaily(at time: DateComponents, completion: @escaping @MainActor (Bool) -> Void)
    
    /// Запросить пермишн на уведомления без планирования (для UX где алерт
    /// должен появиться на конкретном шаге, а расписание — по кнопке).
    /// Если пермишн уже granted/denied — просто вернёт результат.
    func requestAccess(completion: @escaping @MainActor (Bool) -> Void)

    /// Отменить активное напоминание.
    func cancel()
    
    /// Текущее запланированное время (nil если ничего не стоит).
    func pendingTime(completion: @escaping @MainActor (DateComponents?) -> Void)
}

@MainActor
final class LessonReminderService: LessonReminderScheduling {
    
    private let center = UNUserNotificationCenter.current()
    private let reminderId = "daily_lesson_reminder"
    
    // MARK: - Status
    
    func status(completion: @escaping @MainActor (LessonReminderStatus) -> Void) {
        center.getNotificationSettings { settings in
            let result: LessonReminderStatus
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: result = .granted
            case .denied:                                result = .denied
            case .notDetermined:                         result = .undetermined
            @unknown default:                            result = .undetermined
            }
            Task { @MainActor in completion(result) }
        }
    }
    
    // MARK: - Schedule
    
    func scheduleDaily(at time: DateComponents, completion: @escaping @MainActor (Bool) -> Void) {
        ensureAccess { [weak self] granted in
            guard let self, granted else { completion(false); return }
            self.setup(time: time, completion: completion)
        }
    }
    
    // MARK: - Request access (no scheduling)

    func requestAccess(completion: @escaping @MainActor (Bool) -> Void) {
        ensureAccess(completion: completion)
    }

    // MARK: - Cancel

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [reminderId])
    }
    
    // MARK: - Introspection
    func pendingTime(completion: @escaping @MainActor (DateComponents?) -> Void) {
        center.getPendingNotificationRequests { requests in
            let request = requests.first { $0.identifier == self.reminderId }
            let trigger = request?.trigger as? UNCalendarNotificationTrigger
            let comps = trigger?.dateComponents
            Task { @MainActor in completion(comps) }
        }
    }
    
    // MARK: - Private
    private func ensureAccess(completion: @escaping @MainActor (Bool) -> Void) {
        status { [weak self] currentStatus in
            switch currentStatus {
            case .granted:
                Self.registerForRemote()
                completion(true)
            case .undetermined:
                self?.center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    Task { @MainActor in
                        if granted { Self.registerForRemote() }
                        completion(granted)
                    }
                }
            case .denied:
                self?.openSettings()
                completion(false)
            }
        }
    }

    /// APNs-регистрация. Локальные уведомления и remote push используют один
    /// и тот же авторизационный статус — как только грант есть, дёргаем
    /// `registerForRemoteNotifications` чтобы получить device token в
    /// `AppDelegate.didRegisterForRemote…` → `PushTokenService`.
    private static func registerForRemote() {
        Task { @MainActor in
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    
    private func setup(time: DateComponents, completion: @escaping @MainActor (Bool) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = "Time for your English lesson"
        content.body = "Your AI tutor is waiting — a few minutes today keeps your streak alive."
        content.sound = .default
        content.interruptionLevel = .timeSensitive   // если хочешь показывать при DND — иначе убери
        
        // Берём только hour + minute — календарный триггер с repeats=true сработает каждый день
        var trigger = DateComponents()
        trigger.hour = time.hour
        trigger.minute = time.minute
        
        let request = UNNotificationRequest(
            identifier: reminderId,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: true)
        )
        
        // Убираем предыдущее — иначе будут дубли при перепланировании
        center.removePendingNotificationRequests(withIdentifiers: [reminderId])
        
        center.add(request) { error in
            Task { @MainActor in completion(error == nil) }
        }
    }
    
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
