import Foundation
import Network

/// Отслеживает статус сети через `NWPathMonitor`. Публикует `isOnline`
/// как `@Observable`-свойство. Используется в LessonView (373:4639) для
/// показа offline-banner-а и очереди сообщений.
@MainActor
@Observable
final class NetworkMonitor {

    private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.languageschool.network-monitor")

    init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
