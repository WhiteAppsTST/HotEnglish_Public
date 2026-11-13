import SwiftUI
import ApphudSDK
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Cold-start по тапу на пуш: iOS кладёт userInfo в launchOptions.
        // Обрабатываем той же цепочкой, что и hot-start (didReceive).
        // Отправляем чуть позже, чтобы RootView успел смонтировать HomeView
        // и подписаться на `NotificationCenter.awayMessageReceived`.
        if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.handleIncomingPush(userInfo: userInfo)
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Apphud.submitPushNotificationsToken(token: deviceToken, callback: nil)
        Task { @MainActor in
            PushTokenService.shared.didReceive(deviceToken: deviceToken)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    /// Тап по пушу (background/inactive → foreground). SDK Apphud
    /// должен получить apsInfo первым — он зафиксирует `rule_id`,
    /// отправит метрику `$push_opened` и, если задан `screen_id`,
    /// сам покажет свой контроллер. Если Apphud сказал `false` — это
    /// либо не Apphud-пуш, либо Rules без screen'a: пробуем распарсить
    /// наш кастомный payload и открыть `AwayMessageSheet`.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleIncomingPush(userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }

    /// Единая точка обработки входящего push-payload — cold-start и
    /// hot-start сводятся сюда. Порядок: Apphud первым, наш парсер вторым.
    private func handleIncomingPush(userInfo: [AnyHashable: Any]) {
        // Apphud возвращает true если этот payload — его Rule-пуш и он
        // сам отрисует свой screen (по screen_id). Мы всё равно пытаемся
        // распарсить `type: "away"` — гибрид: Apphud шлёт пуш, а sheet
        // рисуем свой (по договорённости — screen_id в rule НЕ задан).
        _ = Apphud.handlePushNotification(apsInfo: userInfo)

        if let data = AwayMessageData.fromApsInfo(userInfo) {
            NotificationCenter.default.post(
                name: .awayMessageReceived,
                object: data
            )
        }
    }
}
