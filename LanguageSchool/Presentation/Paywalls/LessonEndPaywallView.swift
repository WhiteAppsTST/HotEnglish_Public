import SwiftUI

/// Пейвол «Конец урока» — Figma 762:2568.
/// Триггер: юзер завершил обычный (не-date) шаг на free-плане.
///
/// Отличия от `DatingContinuePaywallView`:
/// - фон `lesson_end` (лампа, дневник, чашка);
/// - другой тайтл: «You stopped one step\nbefore the good part».
/// Всё остальное (subtitle, benefits, planы, CTA, футер, next-unit hint) —
/// идентично для консистентности пользовательского опыта.
struct LessonEndPaywallView: View {
    @Environment(SubscriptionService.self) private var service

    var body: some View {
        ZStack(alignment: .top) {
            heroImage.ignoresSafeArea()
            heroScrim.ignoresSafeArea(edges: [.top, .horizontal])

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

private extension LessonEndPaywallView {

    var heroImage: some View {
        GeometryReader { geo in
            Image("lesson_end")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width,
                       height: geo.size.height * 0.55,
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
                .init(color: Color(hex: "#0A0A0D").opacity(0.0),  location: 0.25),
                .init(color: Color(hex: "#0A0A0D").opacity(0.80), location: 0.48),
                .init(color: Color(hex: "#0A0A0D"),                location: 0.70)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Content

private extension LessonEndPaywallView {

    var content: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            headerBlock
                .padding(.horizontal, 20)
            includedCard
                .padding(.horizontal, 20)
            plansRow
                .padding(.horizontal, 20)
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    var headerBlock: some View {
        VStack(spacing: 8) {
            Text(L10n.tr("paywall.lesson_end.title",
                        "You stopped one step\nbefore the good part"))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Text(L10n.tr("paywall.lesson_end.subtitle",
                        "Voice messages both ways, no daily cap."))
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .multilineTextAlignment(.center)
        }
    }

    var includedCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            includedItem(L10n.tr("paywall.lesson_end.item.voice",
                                 "Unlimited Voice in Free chat"))
            includedItem(L10n.tr("paywall.lesson_end.item.hints",
                                 "Unlock hints and help"))
            includedItem(L10n.tr("paywall.lesson_end.item.messages",
                                 "Unlimited messages in free talk"))
            includedItem(L10n.tr("paywall.lesson_end.item.teachers",
                                 "Every teacher unlocked"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#19191D")))
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Plans (horizontal 2-column)

private extension LessonEndPaywallView {

    var plansRow: some View {
        HStack(spacing: 10) {
            if isLoadingProducts {
                planSkeletonCard
                planSkeletonCard
            } else if let year = sortedPlans.first(where: { $0.periodly == "year" }),
                      let month = sortedPlans.first(where: { $0.periodly == "month" }) {
                planCard(year)
                    .onTapGesture { service.selection = year }
                planCard(month)
                    .onTapGesture { service.selection = month }
            } else {
                ForEach(sortedPlans.prefix(2)) { plan in
                    planCard(plan)
                        .onTapGesture { service.selection = plan }
                }
            }
        }
    }

    var isLoadingProducts: Bool {
        service.fetchState == .loading || service.products.isEmpty
    }

    var sortedPlans: [PremiumProduct] {
        service.products.sortedForPaywall
    }

    func autoSelectFirstProduct() {
        let plans = sortedPlans
        guard let first = plans.first else { return }
        let stillValid = service.selection.map { s in plans.contains(where: { $0.id == s.id }) } ?? false
        if !stillValid { service.selection = first }
    }

    var planSkeletonCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule().fill(Color.white.opacity(0.10)).frame(width: 60, height: 14)
            Capsule().fill(Color.white.opacity(0.10)).frame(width: 80, height: 20)
            Capsule().fill(Color.white.opacity(0.06)).frame(width: 100, height: 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 104)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#19191D")))
    }

    func planCard(_ plan: PremiumProduct) -> some View {
        let selected = service.selection?.id == plan.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Text(planTitle(plan))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                if let badge = saveBadgeText(for: plan) {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .frame(height: 16)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.lsPink))
                }
            }

            Text(primaryPrice(for: plan))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Text(planSubtitle(for: plan))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 104)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(selected ? Color.lsPink.opacity(0.15) : Color(hex: "#19191D"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(selected ? Color.lsPink : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
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

    func primaryPrice(for plan: PremiumProduct) -> String {
        if plan.periodly == "year", let perMonth = perMonthEquivalent(plan) {
            return perMonth
        }
        return plan.pricePerPeriod
    }

    func planSubtitle(for plan: PremiumProduct) -> String {
        switch plan.periodly {
        case "year":
            return L10n.tr("paywall.dating_continue.year_sub",
                          "per month · %@ billed yearly", plan.pricePerPeriod)
        case "month":
            return L10n.tr("paywall.per.month_prefix", "per month")
        case "week":
            return L10n.tr("paywall.per.week_prefix", "per week")
        default:
            return ""
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

private extension LessonEndPaywallView {

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
                .minimumScaleFactor(0.7)
                .frame(height: 16)

            Button {
                service.hidePaywall()
                // TODO: навигация к следующему юниту — прокинуть через
                // env callback после согласования UX.
            } label: {
                Text(L10n.tr("paywall.lesson_end.next_unit_hint",
                            "Open next unit"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
                    .frame(height: 20)
            }
            .buttonStyle(.plain)

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
            Text(L10n.tr("paywall.lesson_end.cta", "Continue the story?"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    var isButtonDisabled: Bool {
        isLoadingProducts
            || service.selection == nil
            || service.purchaseState == .purchasing
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

private extension LessonEndPaywallView {

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
