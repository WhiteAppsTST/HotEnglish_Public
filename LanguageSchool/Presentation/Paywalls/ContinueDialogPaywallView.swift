import SwiftUI

/// Пейвол «Продолжение свободного диалога» — Figma 762:2625.
/// Триггер: юзер исчерпал free-текстовые сообщения в Talk-чате
/// (`SubscriptionService.showPaywall(.free_chat)`).
///
/// Отличия от unified пейвола (762:2445):
/// - фон `continue_dialog_paywall` (телефон-мокап с показанным чатом);
/// - тайтл слева, 2 строки, без сабтайтла;
/// - буллеты без dark-card (прямо на фоне);
/// - subtitle для Year plan — «per week»;
/// - price справа в 2 строки: цена + billed-note.
struct ContinueDialogPaywallView: View {
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

private extension ContinueDialogPaywallView {

    var heroImage: some View {
        GeometryReader { geo in
            Image("continue_dialog_paywall")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width,
                       height: geo.size.height * 0.58,
                       alignment: .top)
                .clipped()
                .frame(maxWidth: .infinity,
                       maxHeight: .infinity,
                       alignment: .top)
                .background(Color(hex: "#0A0A0D"))
        }
        .allowsHitTesting(false)
    }

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

private extension ContinueDialogPaywallView {

    var content: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            title
                .padding(.horizontal, 20)
            includedList
                .padding(.horizontal, 20)
            plansBlock
                .padding(.horizontal, 20)
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// «Want to keep\nthe conversation going?» — 28pt bold, left-aligned,
    /// 2 строки; вторая с отступом 20pt вниз.
    var title: some View {
        Text(L10n.tr("paywall.continue_dialog.title",
                    "Want to keep\nthe conversation going?"))
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 4 буллета БЕЗ dark-card контейнера — прямо на фоне.
    var includedList: some View {
        VStack(alignment: .leading, spacing: 13) {
            includedItem(L10n.tr("paywall.continue_dialog.item.unlimited_conv",
                                 "Unlimited free conversations"))
            includedItem(L10n.tr("paywall.continue_dialog.item.hints",
                                 "Hints whenever you need them"))
            includedItem(L10n.tr("paywall.continue_dialog.item.teachers",
                                 "All five teachers unlocked"))
            includedItem(L10n.tr("paywall.continue_dialog.item.messages",
                                 "Unlimited messages"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func includedItem(_ text: String) -> some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(Color(hex: "#FF2E7E").opacity(0.18))
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

private extension ContinueDialogPaywallView {

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
            VStack(alignment: .trailing, spacing: 6) {
                Capsule().fill(Color.white.opacity(0.10)).frame(width: 70, height: 14)
                Capsule().fill(Color.white.opacity(0.06)).frame(width: 60, height: 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(height: 68)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#18181D")))
    }

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

            /// Правая колонка: price + billed-note (2 строки).
            VStack(alignment: .trailing, spacing: 2) {
                Text(plan.pricePerPeriod)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(billedNote(for: plan))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(height: 68)
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

    /// Для года — «$X.XX per week» (per-week equivalent). Для остальных —
    /// «billed monthly/weekly» — но реально Figma показывает для месяца тоже
    /// «billed monthly» в subtitle. Оставляем.
    func subtitleFor(_ plan: PremiumProduct) -> String {
        if plan.periodly == "year", let perWeek = perWeekEquivalent(plan) {
            return L10n.tr("paywall.perweek_subtitle", "%@ per week", perWeek)
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

    func perWeekEquivalent(_ plan: PremiumProduct) -> String? {
        guard plan.priceDecimal > 0 else { return nil }
        let weeks: Decimal
        switch plan.periodly {
        case "year":  weeks = 52
        case "month": weeks = 4.33
        case "week":  weeks = 1
        default:      return nil
        }
        return formatPrice(plan.priceDecimal / weeks, currencyCode: plan.currencyCode)
    }

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

private extension ContinueDialogPaywallView {

    /// Кнопка + однострочный футер. Фиксированная высота футера — layout
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
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: 18)

            PaywallLegalFooter()
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 16)
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

    /// «3 days Free, then $199.99 per year. Cancel anytime.» — 1 строка.
    var footerText: String {
        guard let sel = service.selection else { return " " }
        let period = footerPeriod(for: sel.periodly)
        if sel.includesTrial, let days = sel.trialDays {
            return L10n.tr("paywall.continue_dialog.trial_footer",
                          "%1$lld days Free, then %2$@ per %3$@. Cancel anytime.",
                          days, sel.pricePerPeriod, period)
        }
        return L10n.tr("paywall.continue_dialog.default_footer",
                      "%1$@ per %2$@. Cancel anytime.",
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

private extension ContinueDialogPaywallView {

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
