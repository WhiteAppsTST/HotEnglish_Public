import Foundation
import UIKit
import UserNotifications

/// Оркестратор APNs-токенов.
///
/// Два асинхронных события которые должны сойтись перед регистрацией:
///  1. APNs выдал device token — приходит в AppDelegate.
///  2. Юзер залогинен — иначе `POST /v1/me/devices` вернёт 401.
///
/// Держим оба состояния в @Observable + `PushTokenService.tokenHex` кэшим в
/// UserDefaults чтобы переустановка не сбрасывала «уже зарегистрирован» пока
/// APNs выдаёт тот же токен (что бывает почти всегда до переустановки iOS).
@MainActor
@Observable
final class PushTokenService {

    static let shared = PushTokenService()

    private enum Key {
        static let tokenHex = "push.token.hex"
        static let registeredFor = "push.registered.for.userId"
    }

    /// Текущий APNs-токен в hex-виде (нижний регистр). nil пока не пришёл.
    var tokenHex: String? {
        get { UserDefaults.standard.string(forKey: Key.tokenHex) }
        set { UserDefaults.standard.set(newValue, forKey: Key.tokenHex) }
    }

    /// id юзера для которого мы уже отправили текущий токен на бэк. Нужен
    /// чтобы не долбить `POST /me/devices` на каждое открытие приложения —
    /// пока (token + userId) не изменились, регистрация уже действительна.
    private var registeredForUserId: String? {
        get { UserDefaults.standard.string(forKey: Key.registeredFor) }
        set { UserDefaults.standard.set(newValue, forKey: Key.registeredFor) }
    }

    private init() {}

    /// Запрашивает у системы разрешение на пуши и, при `authorized`, зовёт
    /// `registerForRemoteNotifications()`. Вызывать после того как юзер
    /// прошёл онбординговый шаг «включить напоминания» (или из Settings).
    static func requestAuthorizationAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// AppDelegate прокидывает сюда сырые байты токена.
    func didReceive(deviceToken data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        tokenHex = hex
        // При смене токена registered-ключ инвалидируется — форсим повторный
        // POST /devices.
        registeredForUserId = nil
        Task { await syncIfPossible() }
    }

    /// Вызывается из RootView при появлении/смене currentMe. Отправит токен
    /// на бэк если он есть и ещё не отправлен для этого userId.
    func syncIfPossible() async {
        guard let token = tokenHex else { return }
        guard let userId = AuthService.shared.currentMe?.id else { return }
        guard registeredForUserId != userId else { return }

        let locale = Locale.current.identifier
        let tz = TimeZone.current.identifier
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

        do {
            try await DevicesAPI.register(.init(
                apnsToken: token,
                locale: locale,
                timezone: tz,
                appVersion: version
            ))
            registeredForUserId = userId
        } catch {
            // 401 или 5xx — попробуем на следующем событии (login/foreground).
        }
    }

    /// Отвязать устройство при logout. Best-effort: даже если сервер упал,
    /// локально не сбрасываем `tokenHex` чтобы новый юзер мог зарегаться под
    /// тем же токеном (APNs его переиспользует).
    func unregisterCurrent() async {
        guard let token = tokenHex else { return }
        _ = try? await DevicesAPI.unregister(token: token)
        registeredForUserId = nil
    }
}
