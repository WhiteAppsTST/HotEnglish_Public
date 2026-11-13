import Foundation

/// Хранилище токенов авторизации. accessToken живёт 15 минут, refreshToken —
/// 60 дней. Оба лежат в Keychain (`kSecAttrAccessibleAfterFirstUnlock`), чтобы
/// переустановка приложения не сбрасывала сессию.
enum TokenStore {

    static var access: String? {
        get { KeychainStore.get(.backendAccessToken) }
        set { KeychainStore.set(newValue, for: .backendAccessToken) }
    }

    static var refresh: String? {
        get { KeychainStore.get(.backendRefreshToken) }
        set { KeychainStore.set(newValue, for: .backendRefreshToken) }
    }

    static var hasSession: Bool {
        refresh != nil
    }

    static func save(access: String, refresh: String) {
        self.access = access
        self.refresh = refresh
    }

    static func clear() {
        access = nil
        refresh = nil
    }
}
