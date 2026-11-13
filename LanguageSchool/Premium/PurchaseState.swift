import Foundation

enum PurchaseState {
    case idle
    case purchasing
    case success
    case failure(LocalizedStringResource)
}

enum FetchState {
    case loading
    case success
}

extension PurchaseState: Equatable {
    static func == (lhs: PurchaseState, rhs: PurchaseState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.purchasing, .purchasing),
             (.success, .success):
            return true
        case (.failure, .failure):
            return true
        default:
            return false
        }
    }
}
