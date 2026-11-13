import Foundation

struct PremiumStatusDTO: Decodable {
    let isPremium: Bool
    let premiumUntil: String?
    let productId: String?
    let status: String?
    let expiresAt: String?
}

@MainActor
enum PremiumAPI {

    static func status() async throws -> PremiumStatusDTO {
        try await APIClient.shared.send(.GET, "/v1/me/premium")
    }

    struct PurchaseSyncRequest: Encodable {
        let signedTransaction: String
    }
    static func refreshPurchase(_ body: PurchaseSyncRequest) async throws -> PremiumStatusDTO {
        try await APIClient.shared.send(.POST, "/v1/me/purchases/refresh", body: body)
    }
}
