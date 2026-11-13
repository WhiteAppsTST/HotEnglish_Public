import Foundation
import Security

enum KeychainKey: String {
    case appleUserIdentifier
    case backendAccessToken
    case backendRefreshToken

    /// Сколько бесплатных step-ов юзер прошёл в текущем 24-часовом окне.
    /// Храним в Keychain, чтобы переустановка приложения не сбрасывала лимит.
    case lessonQuotaUsed

    /// UNIX-timestamp момента, когда сегодняшний лимит был достигнут.
    /// От него отсчитываем 24 часа до сброса.
    case lessonQuotaStartedAt

    /// Сколько подсказок юзер потратил в текущем 24-часовом окне.
    /// Общий счётчик across всех уроков — не сбрасывается при открытии
    /// нового урока. Для premium — игнорируется.
    case hintQuotaUsed

    /// UNIX-timestamp первого использования подсказки в текущем окне —
    /// точка отсчёта для 24h сброса.
    case hintQuotaStartedAt
}

enum KeychainStore {
    private static let service = "com.languageschool.app"

    static func set(_ value: String?, for key: KeychainKey) {
        guard let value else { remove(key); return }
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(_ key: KeychainKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    static func remove(_ key: KeychainKey) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}
