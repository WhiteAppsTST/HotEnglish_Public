import Foundation
@preconcurrency import ApphudSDK
import StoreKit

extension ApphudProduct {
    func toPremiumProduct() async -> PremiumProduct {
        let sk = try? await product()
        return await PremiumProduct(
            id: productId,
            title: sk?.displayName ?? name ?? productId,
            periodly: Self.periodString(from: sk),
            includesTrial: Self.hasEligibleTrial(sk: sk),
            trialDays: Self.trialDays(from: sk),
            apphudProduct: self,
            pricePerPeriod: sk?.displayPrice ?? "",
            priceDecimal: sk?.price ?? 0,
            currencyCode: sk?.priceFormatStyle.currencyCode ?? "USD"
        )
    }

    var nonConsumable: Bool {
        get async {
            guard let product = try? await product() else { return false }
            return product.type == .nonConsumable
        }
    }

    var productWithTrial: Bool {
        get async {
            let sk = try? await product()
            return await Self.hasEligibleTrial(sk: sk)
        }
    }

    func introOfferPrice() async -> String {
        let sk = try? await product()
        return sk?.subscription?.introductoryOffer?.displayPrice ?? ""
    }

    private static func periodString(from sk: Product?) -> String {
        guard let unit = sk?.subscription?.subscriptionPeriod.unit else { return "" }
        switch unit {
        case .day:   return "day"
        case .week:  return "week"
        case .month: return "month"
        case .year:  return "year"
        @unknown default: return ""
        }
    }

    private static func hasEligibleTrial(sk: Product?) async -> Bool {
        guard let subscription = sk?.subscription,
              subscription.introductoryOffer != nil
        else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    private static func trialDays(from sk: Product?) -> Int? {
        guard let offer = sk?.subscription?.introductoryOffer else { return nil }
        let period = offer.period
        switch period.unit {
        case .day:   return period.value
        case .week:  return period.value * 7
        case .month: return period.value * 30
        case .year:  return period.value * 365
        @unknown default: return nil
        }
    }
}

extension ApphudPaywall {
    func toPresentationPaywall() -> PaywallInfo {
        PaywallInfo(
            title: "Premium",
            tryFreeButton: "Try free & subscribe",
            continueButton: "Continue & subscribe",
            purchaseButton: nil
        )
    }

    func convertProducts() async -> [PremiumProduct] {
        var results = Array<PremiumProduct?>(repeating: nil, count: self.products.count)
        await withTaskGroup(of: (Int, PremiumProduct).self) { group in
            for (index, item) in self.products.enumerated() {
                group.addTask {
                    (index, await item.toPremiumProduct())
                }
            }
            for await (index, product) in group {
                results[index] = product
            }
        }
        return results.compactMap { $0 }
    }
}
