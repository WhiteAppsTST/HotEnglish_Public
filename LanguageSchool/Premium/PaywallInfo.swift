import Foundation
import ApphudSDK

struct PaywallInfo {
    let title: String
    let tryFreeButton: String
    let continueButton: String
    let purchaseButton: String?
}

struct PremiumProduct: Identifiable, Equatable {
    var id: String
    var title: String
    var periodly: String
    var includesTrial: Bool
    var trialDays: Int?
    var apphudProduct: ApphudProduct?
    var pricePerPeriod: String
    var priceDecimal: Decimal
    var currencyCode: String
}

extension [PremiumProduct] {
    var weeklyOption: PremiumProduct? {
        first(where: { $0.periodly == "week" })
    }

    /// Ранжирование для пейволов: year → month → week → day → прочее.
    /// Первый в этом списке — дефолтный выбор при открытии пейвола.
    var sortedForPaywall: [PremiumProduct] {
        sorted { rank($0) < rank($1) }
    }

    private func rank(_ p: PremiumProduct) -> Int {
        switch p.periodly {
        case "year":  return 0
        case "month": return 1
        case "week":  return 2
        case "day":   return 3
        default:      return 4
        }
    }
}
