import SwiftUI

/// Единый пейвол по Figma 762:2445. Три триггера: `.onboarding` (premium
/// teacher после онбординга), `.dating` (свап teacher), `.in_lessons`
/// (после исчерпания 3 подсказок в уроке).
///
/// **Верстка:** ZStack фон-картинка `B_Paywall` через весь экран, включая
/// safe area (top). Контент прибит к низу: bottom bar имеет фиксированную
/// высоту (кнопка 56 + лег ~2 строки 32), выше — plans, includedCard,
/// header. Так футер не двигает верхние блоки при смене продукта.
///
/// **Продукты:** первый (Year → Month → Week) выбирается по умолчанию;
/// цены/периоды/save% — из `SubscriptionService.products`.
struct UnifiedPaywallView: View {
    @Environment(SubscriptionService.self) private var service

    var body: some View {
        ZStack(alignment: .top) {
            heroImage
                .ignoresSafeArea()

            heroScrim
                .ignoresSafeArea(edges: [.top, .horizontal])

            content
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#0A0A0D").ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            closeButton
                .padding(.leading, 16)
                .padding(.top, 4)
        }
        .task { autoSelectFirstProduct() }
        .onChange(of: service.products.count) { _, _ in autoSelectFirstProduct() }
    }
}

// MARK: - Hero

private extension UnifiedPaywallView {

    /// Полноэкранный фон: изображение aspect-fill сверху, обрезано по низу.
    /// Занимает ~62% высоты экрана (соответствует Figma-раскладке).
    var heroImage: some View {
        GeometryReader { geo in
            Image("B_Paywall")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width,
                       height: geo.size.height * 0.62,
                       alignment: .top)
                .clipped()
                .frame(maxWidth: .infinity,
                       maxHeight: .infinity,
                       alignment: .top)
                .background(Color(hex: "#0A0A0D"))
        }
        .allowsHitTesting(false)
    }

    /// Тёмный градиент снизу — под контентом всегда солидный #0A0A0D.
    var heroScrim: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "#0A0A0D").opacity(0.0),  location: 0.28),
                .init(color: Color(hex: "#0A0A0D").opacity(0.80), location: 0.50),
                .init(color: Color(hex: "#0A0A0D"),                location: 0.72)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Content

private extension UnifiedPaywallView {

    /// VStack прибит к низу через `.frame(maxHeight: .infinity, alignment: .bottom)`.
    /// Header / includedCard появляются сверху и не двигаются при смене плана
    /// — потому что footer имеет резервированную высоту.
    var content: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            header
                .padding(.horizontal, 20)
            includedCard
                .padding(.horizontal, 20)
            plansBlock
                .padding(.horizontal, 20)
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// Title 28/semibold, subtitle 15/regular #9A9AA3 — оба центрированы.
    var header: some View {
        VStack(spacing: 8) {
            Text(L10n.tr("paywall.unified.title", "Unlock unlimited AI experiences"))
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Text(L10n.tr("paywall.unified.subtitle",
                        "Chat, create and meet your favorite AI\ncompanions without limits."))
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }

    /// 4 буллета в dark card #18181D, cr=16.
    var includedCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            includedItem(L10n.tr("paywall.unified.item.hints",     "Unlimited hints in every lesson"))
            includedItem(L10n.tr("paywall.unified.item.translate", "Instant translation, any line"))
            includedItem(L10n.tr("paywall.unified.item.steps",     "All four lesson steps a day"))
            includedItem(L10n.tr("paywall.unified.item.dates",     "Dates and story continuation"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#18181D")))
    }

    func includedItem(_ text: String) -> some View {
        HStack(spacing: 11) {
            ZStack {
                // Круг: #FF2E7E @ 18% прозрачности.
                Circle().fill(Color(hex: "#FF2E7E").opacity(0.18))
                // Галочка: #FF2E7E solid.
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: "#FF2E7E"))
            }
            .frame(width: 22, height: 22)

            Text(text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Plans

private extension UnifiedPaywallView {

    var plansBlock: some View {
        VStack(spacing: 10) {
            if isLoadingProducts {
                planSkeletonRow
                planSkeletonRow
            } else {
                ForEach(sortedPlans) { plan in
                    planRow(plan)
                        .onTapGesture { service.selection = plan }
                }
            }
        }
    }

    var isLoadingProducts: Bool {
        service.fetchState == .loading || service.products.isEmpty
    }

    var sortedPlans: [PremiumProduct] {
        service.products.sorted { rank($0) < rank($1) }
    }

    func rank(_ p: PremiumProduct) -> Int {
        switch p.periodly {
        case "year":  return 0
        case "month": return 1
        case "week":  return 2
        default:      return 3
        }
    }

    /// Первый доступный (Year) выбирается по умолчанию, если ничего не
    /// выбрано — так CTA всегда активна.
    /// Гарантируем что после загрузки продуктов всегда есть selection.
    /// Если текущий selection — nil или не принадлежит списку —
    /// подставляем первый по ранжированию.
    func autoSelectFirstProduct() {
        let plans = sortedPlans
        guard let first = plans.first else { return }
        let stillValid = service.selection.map { s in plans.contains(where: { $0.id == s.id }) } ?? false
        if !stillValid { service.selection = first }
    }

    var planSkeletonRow: some View {
        HStack(spacing: 12) {
            Circle().fill(Color.white.opacity(0.08)).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Color.white.opacity(0.10)).frame(width: 80, height: 14)
                Capsule().fill(Color.white.opacity(0.06)).frame(width: 140, height: 10)
            }
            Spacer(minLength: 0)
            Capsule().fill(Color.white.opacity(0.10)).frame(width: 60, height: 14)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(height: 67)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#18181D")))
    }

    /// Row: radio + (Title + Save badge) над subtitle / Цена справа.
    /// Selected: pink border 1.5pt.
    func planRow(_ plan: PremiumProduct) -> some View {
        let selected = service.selection?.id == plan.id
        return HStack(alignment: .center, spacing: 12) {
            radio(selected: selected)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 8) {
                    Text(planTitle(plan))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)

                    if let badge = saveBadgeText(for: plan) {
                        Text(badge)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.lsPink))
                    }
                }

                Text(subtitleFor(plan))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }

            Spacer(minLength: 0)

            Text(plan.pricePerPeriod)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(height: 67)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#18181D")))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(selected ? Color.lsPink : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }

    func radio(selected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(selected ? Color.lsPink : .clear)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle().stroke(selected ? .clear : Color.white.opacity(0.28), lineWidth: 1.5)
                )
            if selected {
                Circle().fill(.white).frame(width: 8, height: 8)
            }
        }
    }

    func planTitle(_ plan: PremiumProduct) -> String {
        switch plan.periodly {
        case "year":  return L10n.tr("paywall.plan.year", "Year")
        case "month": return L10n.tr("paywall.plan.month", "Month")
        case "week":  return L10n.tr("paywall.plan.week", "Week")
        case "day":   return L10n.tr("paywall.plan.day", "Day")
        default:      return plan.title
        }
    }

    func subtitleFor(_ plan: PremiumProduct) -> String {
        if plan.periodly == "year", let perMonth = perMonthEquivalent(plan) {
            return L10n.tr("paywall.permonth_slash_subtitle", "%@ / month", perMonth)
        }
        return billedNote(for: plan)
    }

    func billedNote(for plan: PremiumProduct) -> String {
        switch plan.periodly {
        case "year":  return L10n.tr("paywall.billed.yearly",  "billed yearly")
        case "month": return L10n.tr("paywall.billed.monthly", "billed monthly")
        case "week":  return L10n.tr("paywall.billed.weekly",  "billed weekly")
        case "day":   return L10n.tr("paywall.billed.daily",   "billed daily")
        default:      return ""
        }
    }

    func perMonthEquivalent(_ plan: PremiumProduct) -> String? {
        guard plan.priceDecimal > 0 else { return nil }
        let months: Decimal
        switch plan.periodly {
        case "year":  months = 12
        case "month": months = 1
        default:      return nil
        }
        return formatPrice(plan.priceDecimal / months, currencyCode: plan.currencyCode)
    }

    /// Показываем «SAVE N%» на Year плане, если есть Month плана. Считаем
    /// от 12× месячной цены; если Month priceDecimal нулевой (Apphud не
    /// всегда прокидывает StoreKit-цену) — парсим цифру из локализованной
    /// `pricePerPeriod` строки как fallback.
    func saveBadgeText(for plan: PremiumProduct) -> String? {
        guard plan.periodly == "year", plan.priceDecimal > 0 else { return nil }
        guard let monthly = service.products.first(where: { $0.periodly == "month" }) else {
            return nil
        }
        var monthlyPrice = monthly.priceDecimal
        if monthlyPrice <= 0 {
            monthlyPrice = parsePriceDecimal(monthly.pricePerPeriod) ?? 0
        }
        guard monthlyPrice > 0 else { return nil }
        let yearBaseline = monthlyPrice * 12
        let savings = (yearBaseline - plan.priceDecimal) / yearBaseline * 100
        let percent = NSDecimalNumber(decimal: savings).intValue
        guard percent > 0 else { return nil }
        return L10n.tr("paywall.save_badge", "SAVE %lld%%", percent)
    }

    /// Достаём десятичное значение из строки цены («$14.99», «14,99 €», …).
    /// Игнорим всё что не цифра/точка/запятая; запятую → точку.
    func parsePriceDecimal(_ s: String) -> Decimal? {
        let allowed: Set<Character> = ["0","1","2","3","4","5","6","7","8","9",".",","]
        var digits = String(s.filter { allowed.contains($0) })
        digits = digits.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: digits)
    }

    func formatPrice(_ value: Decimal, currencyCode: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.maximumFractionDigits = 2
        return f.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }
}

// MARK: - Bottom bar

private extension UnifiedPaywallView {

    /// Фиксированная высота 108pt (кнопка 56 + spacing 8 + резервированные
    /// 2 строки футера ≈ 32pt + отступ 12pt снизу). Стабильный низ — верх
    /// не двигается при смене плана.
    var bottomBar: some View {
        VStack(spacing: 8) {
            Button {
                Task { await service.completePurchase() }
            } label: {
                buttonLabel
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Capsule().fill(Color.lsPink))
            }
            .buttonStyle(.plain)
            .disabled(isButtonDisabled)
            .padding(.horizontal, 20)

            Text(footerText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .lineLimit(2)
                .frame(height: 32, alignment: .top)

            PaywallLegalFooter()
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    var buttonLabel: some View {
        if service.purchaseState == .purchasing || isLoadingProducts {
            ProgressView().progressViewStyle(.circular).tint(.white)
        } else {
            Text(continueButtonText)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    var isButtonDisabled: Bool {
        isLoadingProducts
            || service.selection == nil
            || service.purchaseState == .purchasing
    }

    var continueButtonText: String {
        guard let sel = service.selection else {
            return L10n.tr("paywall.unified.continue", "Continue & Subscribe")
        }
        if sel.includesTrial, let days = sel.trialDays {
            return L10n.tr("paywall.trial_button", "Start %lld-day free trial", days)
        }
        return L10n.tr("paywall.unified.continue", "Continue & Subscribe")
    }

    var footerText: String {
        guard let sel = service.selection else { return " " }
        let period = footerPeriod(for: sel.periodly)
        if sel.includesTrial, let days = sel.trialDays {
            return L10n.tr("paywall.unified.trial_footer",
                          "%1$lld days free, then %2$@/%3$@. Cancel anytime in Apple ID settings.",
                          days, sel.pricePerPeriod, period)
        }
        return L10n.tr("paywall.unified.default_footer",
                      "%1$@/%2$@. Cancel anytime in Apple ID settings.",
                      sel.pricePerPeriod, period)
    }

    func footerPeriod(for periodly: String) -> String {
        switch periodly {
        case "year":  return L10n.tr("paywall.per.year",  "year")
        case "month": return L10n.tr("paywall.per.month", "month")
        case "week":  return L10n.tr("paywall.per.week",  "week")
        case "day":   return L10n.tr("paywall.per.day",   "day")
        default:      return periodly
        }
    }
}

// MARK: - Close

private extension UnifiedPaywallView {

    var closeButton: some View {
        Button {
            service.hidePaywall()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .buttonStyle(.plain)
    }
}
