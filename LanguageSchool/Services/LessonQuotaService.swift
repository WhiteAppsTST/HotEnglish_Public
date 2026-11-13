import Foundation

/// Счётчик пройденных бесплатных упражнений с окном 24 часа.
/// Считаем только полностью завершённые step-ы. Хранится в Keychain,
/// чтобы переустановка приложения не сбрасывала окно (защита от абьюза).
/// Точка подключения будущего SubscriptionService: если `user.isPremium == true`,
/// вьюмодель просто не спрашивает у сервиса — лимит игнорируется.
@MainActor
@Observable
final class LessonQuotaService {

    /// Глобальный экземпляр квоты. Свою инстанцию оставляем инициализируемой
    /// (для тестов и HomeViewModel(init:), но живой enforcement по всему
    /// приложению должен идти через `.shared` — иначе Home и LessonView
    /// увидят разные счётчики и sheet «daily limit» не сработает.
    static let shared: LessonQuotaService = LessonQuotaService()

    // MARK: - Config

    /// ТЗ: **1 задание/день** для free-юзера (sec_470 — пэйвол при попытке
    /// приступить ко второму заданию за день). Сервер — единственный
    /// источник истины (возвращает 402 на 2-й `POST /session-attempts`),
    /// клиент держит локальный счётчик только для UI hint и офлайн-guard.
    static let dailyLimit: Int = 1
    static let window: TimeInterval = 24 * 3600

    // MARK: - State (observable)

    private(set) var completedToday: Int = 0
    /// Момент когда сегодняшний лимит был достигнут. `nil` если лимит ещё не достигнут.
    private(set) var limitStartedAt: Date?

    // MARK: - Init

    init() {
        loadFromKeychain()
        refreshIfExpired()
    }

    // MARK: - Derived

    var remaining: Int { max(0, Self.dailyLimit - completedToday) }
    var isExhausted: Bool { completedToday >= Self.dailyLimit }

    /// Секунды до сброса окна. `nil` если лимит ещё не исчерпан.
    func secondsRemaining(at now: Date = .now) -> TimeInterval? {
        guard let limitStartedAt else { return nil }
        return max(0, Self.window - now.timeIntervalSince(limitStartedAt))
    }

    /// Форматирует оставшееся время как "14h 20m" или "45m".
    /// Возвращает `nil` если лимит не исчерпан или уже истёк.
    func timeRemainingString(at now: Date = .now) -> String? {
        guard let seconds = secondsRemaining(at: now), seconds > 0 else { return nil }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }

    // MARK: - Mutations

    /// Записать, что юзер завершил один step. Возвращает true, если этот вызов
    /// исчерпал лимит.
    @discardableResult
    func recordStepCompleted() -> Bool {
        refreshIfExpired()
        guard !isExhausted else { return false }
        completedToday += 1
        if completedToday >= Self.dailyLimit {
            limitStartedAt = .now
        }
        saveToKeychain()
        return isExhausted
    }

    /// Сбросить окно вручную. Дёргается автоматически при истечении 24 часов.
    func reset() {
        completedToday = 0
        limitStartedAt = nil
        saveToKeychain()
    }

    /// Проверяет, не истекло ли 24-часовое окно, и обнуляет счётчик если да.
    /// Дёргаем на onAppear Home и перед каждым `recordStepCompleted`.
    func refreshIfExpired() {
        guard let startedAt = limitStartedAt else { return }
        if Date().timeIntervalSince(startedAt) >= Self.window {
            completedToday = 0
            limitStartedAt = nil
            saveToKeychain()
        }
    }

    // MARK: - Persistence

    private func loadFromKeychain() {
        let usedString = KeychainStore.get(.lessonQuotaUsed)
        self.completedToday = Int(usedString ?? "") ?? 0

        if let startedString = KeychainStore.get(.lessonQuotaStartedAt),
           let ts = Double(startedString), ts > 0 {
            self.limitStartedAt = Date(timeIntervalSince1970: ts)
        } else {
            self.limitStartedAt = nil
        }
    }

    private func saveToKeychain() {
        KeychainStore.set("\(completedToday)", for: .lessonQuotaUsed)
        if let ts = limitStartedAt?.timeIntervalSince1970 {
            KeychainStore.set("\(ts)", for: .lessonQuotaStartedAt)
        } else {
            KeychainStore.set(nil, for: .lessonQuotaStartedAt)
        }
    }
}
