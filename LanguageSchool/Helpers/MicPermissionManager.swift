import AVFoundation
import UIKit

// MARK: - Public model
enum MicPermissionStatus {
    case granted, denied, undetermined
}

// MARK: - Protocol
@MainActor
protocol MicPermissionManaging {
    var current: MicPermissionStatus { get }
    func ensureAccess(completion: @escaping @MainActor (Bool) -> Void)
}

// MARK: - MicPermissionManager
@MainActor
final class MicPermissionManager: MicPermissionManaging {
    
    var current: MicPermissionStatus {
        if #available(iOS 17, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .undetermined
            @unknown default: return .undetermined
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .undetermined
            @unknown default: return .undetermined
            }
        }
    }
    
    func ensureAccess(completion: @escaping @MainActor (Bool) -> Void) {
        switch current {
        case .granted:
            completion(true)
        case .undetermined:
            requestSystem(completion: completion)
        case .denied:
            openSettings()
            completion(false)
        }
    }
    
    // MARK: - Private
    private func requestSystem(completion: @escaping @MainActor (Bool) -> Void) {
        if #available(iOS 17, *) {
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in completion(granted) }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                Task { @MainActor in completion(granted) }
            }
        }
    }
    
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
