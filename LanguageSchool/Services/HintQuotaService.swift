import Foundation

/// Глобальный счётчик подсказок для free-юзера: 3 в сутки, rolling 24h окно.
/// Разделяемый между всеми уроками — открытие нового урока НЕ обнуляет квоту.
/// Для premium — сервис не запрашивается вьюмоделью (`user.isPremium` — байпас).
///
/// Хранение: Keychain (`hintQuotaUsed`, `hintQuotaStartedAt`) —
/// переустановка приложения не сбрасывает лимит, защита от абьюза.
@MainActor
@Observable
final class HintQuotaService {

    // MARK: - Config

    static let dailyLimit: Int = 3
    static let window: TimeInterval = 24 * 3600

    // MARK: - State (observable)

    private(set) var usedToday: Int = 0
    /// Момент когда квота была впервые использована в текущем окне.
    /// От него отсчитывается 24h. `nil` — окно ещё не открыто.
    private(set) var startedAt: Date?

    // MARK: - Init

    init() {
        loadFromKeychain()
        refreshIfExpired()
    }

    // MARK: - Derived

    var remaining: Int { max(0, Self.dailyLimit - usedToday) }
    var isExhausted: Bool { usedToday >= Self.dailyLimit }

    func secondsRemaining(at now: Date = .now) -> TimeInterval? {
        guard let startedAt else { return nil }
        return max(0, Self.window - now.timeIntervalSince(startedAt))
    }

    // MARK: - Mutations

    /// Списать одну подсказку. Возвращает `true` если после этого квота
    /// исчерпалась. Возвращает `false` также если квота уже была исчерпана
    /// и подсказку списать не удалось.
    @discardableResult
    func consumeHint() -> Bool {
        refreshIfExpired()
        guard !isExhausted else { return false }
        if startedAt == nil { startedAt = .now }
        usedToday += 1
        saveToKeychain()
        return isExhausted
    }

    func reset() {
        usedToday = 0
        startedAt = nil
        saveToKeychain()
    }

    /// Обнуляет счётчик если 24-часовое окно истекло.
    func refreshIfExpired() {
        guard let startedAt else { return }
        if Date().timeIntervalSince(startedAt) >= Self.window {
            usedToday = 0
            self.startedAt = nil
            saveToKeychain()
        }
    }

    // MARK: - Persistence

    private func loadFromKeychain() {
        let usedString = KeychainStore.get(.hintQuotaUsed)
        self.usedToday = Int(usedString ?? "") ?? 0
        if let ts = KeychainStore.get(.hintQuotaStartedAt).flatMap(Double.init), ts > 0 {
            self.startedAt = Date(timeIntervalSince1970: ts)
        } else {
            self.startedAt = nil
        }
    }

    private func saveToKeychain() {
        KeychainStore.set("\(usedToday)", for: .hintQuotaUsed)
        if let ts = startedAt?.timeIntervalSince1970 {
            KeychainStore.set("\(ts)", for: .hintQuotaStartedAt)
        } else {
            KeychainStore.set(nil, for: .hintQuotaStartedAt)
        }
    }
}
