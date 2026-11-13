import Foundation
import ApphudSDK
import StoreKit
import SwiftUI
import AdServices

@MainActor
@Observable
final class SubscriptionService {
    @ObservationIgnored
    @AppStorage("FIRST_LAUNCH") private var firstLaunch = true
    
    var appState: AppState = .onboarding
    var products = [PremiumProduct]()
    var selection: PremiumProduct?
    var isActiveSubscription = false
    var isPaywallShown = false
    var purchaseState: PurchaseState = .idle
    var fetchState: FetchState = .loading
    
    var paywall: PaywallInfo?
    var canUseTrial = true

    var currentPaywallId: PaywallId?

    /// Учительница, чью «превью» показывает пейвол (видео/фон/имя).
    /// Устанавливается вызывающим кодом ДО `showPaywall`: онбординг передаёт
    /// выбранную но не купленную premium-teacher; свап-экран — кандидата.
    /// `nil` — пейвол берёт саму selectedTeacher из UserSettings.
    var pendingTeacher: TeacherProfile?

    /// Действие, выполняемое после успешной покупки. Обычно —
    /// «применить выбор учительницы» из точки вызова пейвола. Дёргается
    /// один раз в `success()` перед `hidePaywall()`.
    var onPurchaseSuccess: (@MainActor () -> Void)?
        
    private var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "APHUD_API_KEY") as? String ?? ""
    }
    
    static let shared = SubscriptionService()
    private init() { appState = firstLaunch ? .onboarding : .home }
}

extension SubscriptionService {
    
    var titledText: String {
        guard let prod = selection else { return "" }
        return formatTrialOrSubscription(prod: prod)
    }
    
    var purchaseBtnTitle: String {
        guard let title = selection?.title else {
            return paywall?.continueButton
                ?? L10n.tr("subs.continue_subscribe", "Continue & subscribe")
        }

        if canUseTrial && title.containsCaseInsensitive("free") {
            return paywall?.tryFreeButton
                ?? L10n.tr("subs.try_free_subscribe", "Try free & subscribe")
        }

        return paywall?.continueButton
            ?? L10n.tr("subs.continue_subscribe", "Continue & subscribe")
    }
    
    func hasActiveSubscription() -> Bool {
        return Apphud.hasActiveSubscription()
    }
    
    func isNewUser() -> Bool {
        let subscriptions = Apphud.subscriptions() ?? []
        let purchases = Apphud.nonRenewingPurchases() ?? []

       return subscriptions.isEmpty && purchases.isEmpty
    }

    private func formatTrialOrSubscription(prod: PremiumProduct) -> String {
        if prod.includesTrial && canUseTrial {
            return L10n.tr("subs.trial_hint", "No payment now.\nTry 3 days free")
        }
        return L10n.tr("subs.easy_start_hint",
                       "Easy start with\n%1$@ %2$@",
                       prod.title, prod.pricePerPeriod)
    }
    
    func start() {
        Apphud.start(apiKey: apiKey)
        trackAppleSearchAds()
        Apphud.refreshUserData { [weak self] _ in
            self?.isActiveSubscription = Apphud.hasActiveSubscription()
        }
    }

    /// Fire-and-forget уведомление бэка о покупке — `POST /v1/me/purchases/refresh`.
    /// Нужен ТОЛЬКО чтобы бэкенд снял свои гейты (`/session-attempts`,
    /// `/chat-turn` — они у нас отдают 429/402 пока сервер не увидит подписку).
    /// Локальный `isActiveSubscription` НЕ трогает — источник правды Apphud,
    /// клиентские фичи (мик, подсказки, лимиты Talk через OpenAI, лок юнитов)
    /// работают мгновенно после `Apphud.purchase` вне зависимости от ответа бэка.
    /// Молчаливый — если сервер отказал (в песочнице /purchases/refresh может
    /// отклонить Xcode-signed чек с 401 «Notification chain does not root in
    /// Apple's CA»), просто ретраим позже. В проде на реальных App Store JWS
    /// заведётся само.
    private func notifyBackendOfPurchase() async {
        var jws: String?
        for await result in Transaction.currentEntitlements {
            if case .verified = result {
                jws = result.jwsRepresentation
                break
            }
        }
        guard let jws else { return }
        _ = try? await PremiumAPI.refreshPurchase(.init(signedTransaction: jws))
    }
    
    func fetchProductBy(paywall paywallId: PaywallId) async {
        guard let placement = await Apphud.placement(paywallId.rawValue) else { return }
        guard let paywall = placement.paywall else {
            print("No paywall associated with placement: \(paywallId)")
            return
        }

        self.products = await paywall.convertProducts()
        updatePaywallInfo(from: paywall)
    }
    
    func completePurchase() async {
        guard let product = selection?.apphudProduct else { return }
        purchaseState = .purchasing
        let result = await Apphud.purchase(product)
        if result.success {
            success()
            // Fire-and-forget пинг бэку, чтобы он снял свои гейты.
            // На `isActiveSubscription` НЕ влияет.
            Task { await notifyBackendOfPurchase() }
        } else {
            failure()
        }
    }

    func restore() async {
        let error = await Apphud.restorePurchases()
        if error == nil {
            success()
            Task { await notifyBackendOfPurchase() }
        }
    }
    
    func showPaywall(_ id: PaywallId) {
        currentPaywallId = id
        fetchState = .loading
        isPaywallShown = true
        Task { @MainActor in
            await fetchProductBy(paywall: id)
            fetchState = .success
        }
    }

    /// Overload: показать пейвол с превью конкретной учительницы (видео + фон)
    /// и опциональным `onSuccess`-callback'ом, который сработает после
    /// успешной покупки — до `hidePaywall`. Отмена (кросс) — callback не идёт.
    func showPaywall(
        _ id: PaywallId,
        teacher: TeacherProfile?,
        onSuccess: (@MainActor () -> Void)? = nil
    ) {
        pendingTeacher = teacher
        onPurchaseSuccess = onSuccess
        showPaywall(id)
    }

    func hidePaywall() {
        isPaywallShown = false
        currentPaywallId = nil
        pendingTeacher = nil
        onPurchaseSuccess = nil
        // Сбрасываем выбор — следующий пейвол должен стартовать с
        // дефолтным продуктом из своей `sortedForPaywall.first`.
        selection = nil
    }
}

private extension SubscriptionService {
    private func success() {
        firstLaunch = false
        if !isPaywallShown {
            appState = .home
        }

        // Вызываем колбэк ДО hidePaywall, потому что hidePaywall
        // очищает `onPurchaseSuccess`. Колбэк применяет побочный эффект
        // покупки — обычно «сохранить выбранную учительницу».
        let callback = onPurchaseSuccess
        if isPaywallShown {
            hidePaywall()
        }
        callback?()

        isActiveSubscription = hasActiveSubscription()
        purchaseState = .success
    }
    
    private func failure(_ errorText: LocalizedStringResource = "subs.purchase_error") {
        purchaseState = .failure(errorText)
    }
    
    private func trackAppleSearchAds() {
        Task {
            if let asaToken = try? AAAttribution.attributionToken() {
                Apphud.setAttribution(data: .init(rawData: [:]), from: .appleAdsAttribution, identifer: asaToken, callback: nil)
            }
        }
    }
    
    private func updatePaywallInfo(from paywall: ApphudPaywall) {
        self.canUseTrial = products.contains(where: \.includesTrial)
        self.paywall = paywall.toPresentationPaywall()
        // Дефолт-выбор: первый продукт по нашему ранжированию
        // (year → month → week → day). Раньше брали только weeklyOption —
        // если week-плана не было, selection оставался nil и юзер видел
        // паейвол без выбора.
        self.selection = products.sortedForPaywall.first
    }
}

enum AppState: String {
    case onboarding, home
}

enum PaywallId: String {
    case onboarding
    case free_chat
    case in_lessons
    case dating
    /// Пейвол «Конец урока» — Figma 762:2568. Показывается фри-юзеру
    /// после закрытия обычного (не-date) шага.
    case lesson_end
}


extension Decimal {
    func round(
        scale: Int,
        mode: NSDecimalNumber.RoundingMode = .plain
    ) -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }
}
