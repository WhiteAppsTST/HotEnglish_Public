import SwiftUI

struct InLessonsPaywallView: View {
    let teacher: TeacherProfile
    @Environment(SubscriptionService.self) private var service
    @State private var avatar = AvatarPlayer()

    var body: some View {
        ZStack {
            AvatarPlayerView(player: avatar.videoPlayer)

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.5), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 120)

                Spacer(minLength: 0)

                LinearGradient(
                    stops: [
                        .init(color: Color(red: 10/255, green: 10/255, blue: 12/255).opacity(0), location: 0),
                        .init(color: Color(red: 10/255, green: 10/255, blue: 12/255).opacity(0.78), location: 0.45),
                        .init(color: Color(red: 10/255, green: 10/255, blue: 12/255).opacity(0.98), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 527)
            }
            .allowsHitTesting(false)

            content
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            closeButton
                .padding(.top, 20)
                .padding(.leading, 16)
        }
        .onAppear { configureAvatar() }
        .onDisappear { avatar.stop() }
    }

    private func configureAvatar() {
        if let idle = teacher.lessonVideo(.idle) {
            avatar.setBase(video: idle)
        }
    }

    private var closeButton: some View {
        Button {
            service.hidePaywall()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }
}

private extension InLessonsPaywallView {

    var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            titleBlock
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            benefitsCard
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            plansBlock
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            bottomBar
        }
    }

    /// ТЗ (sec_470, «пример пэйвола при попытке приступить ко второму заданию за день»):
    /// «Следующее задание нам очень понравится»
    var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("paywall.in_lessons.title",
                        "The next task —\nwe’ll really enjoy it"))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)

            Text(L10n.tr("paywall.in_lessons.subtitle",
                        "Unlimited lessons, no daily cap."))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefit("Unlimited hints in every lesson")
            benefit("Instant translation, any line")
            benefit("All four lesson steps a day")
            benefit("Dates and story continuation")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: "#18181D")))
    }

    func benefit(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(Color.lsPink.opacity(0.18))
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.lsPink)
            }
            .frame(width: 22, height: 22)

            Text(text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white)
        }
    }
}

private extension InLessonsPaywallView {

    var plansBlock: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if isLoadingProducts {
                    planSkeletonCard
                    planSkeletonCard
                } else {
                    ForEach(sortedPlans) { plan in
                        planCard(plan)
                            .onTapGesture { service.selection = plan }
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    var planCardWidth: CGFloat { 171.5 }

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

    var planSkeletonCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule().fill(Color.white.opacity(0.10)).frame(width: 60, height: 14)
            Spacer(minLength: 0)
            Capsule().fill(Color.white.opacity(0.10)).frame(width: 80, height: 20)
            Capsule().fill(Color.white.opacity(0.06)).frame(width: 120, height: 12)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(width: planCardWidth, alignment: .leading)
        .frame(height: 104)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#18181D")))
    }

    func planCard(_ plan: PremiumProduct) -> some View {
        let selected = service.selection?.id == plan.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Text(planTitle(plan))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                if let badge = saveBadgeText(for: plan) {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        stops: [
                                            .init(color: Color(red: 255/255, green: 45/255, blue: 125/255), location: 0),
                                            .init(color: Color(red: 254/255, green: 134/255, blue: 180/255), location: 0.34),
                                            .init(color: Color(red: 255/255, green: 46/255, blue: 126/255), location: 1),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
            }

            Spacer(minLength: 6)

            Text(bigPrice(for: plan))
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)

            Text(subtitle(for: plan))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(width: planCardWidth, alignment: .leading)
        .frame(height: 104)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(selected ? Color.lsPink.opacity(0.14) : Color(hex: "#18181D"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(selected ? Color.lsPink : .clear, lineWidth: 1.5)
        )
        .shadow(
            color: selected ? Color.lsPink.opacity(0.45) : .clear,
            radius: 12,
            x: 0,
            y: 0
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

    func bigPrice(for plan: PremiumProduct) -> String {
        if plan.periodly == "year", let perMonth = perMonthEquivalent(plan) {
            return perMonth
        }
        return plan.pricePerPeriod
    }

    func subtitle(for plan: PremiumProduct) -> String {
        switch plan.periodly {
        case "year":
            return L10n.tr("paywall.year_subtitle",
                           "per month · %@ billed yearly",
                           plan.pricePerPeriod)
        case "month": return L10n.tr("paywall.subtitle.per_month", "per month")
        case "week":  return L10n.tr("paywall.subtitle.per_week", "per week")
        case "day":   return L10n.tr("paywall.subtitle.per_day", "per day")
        default:      return ""
        }
    }

    func perMonthEquivalent(_ plan: PremiumProduct) -> String? {
        let months: Decimal
        switch plan.periodly {
        case "year":  months = 12
        case "month": months = 1
        case "week":  months = 0.23
        default:      return nil
        }
        let value = plan.priceDecimal / months
        return formatPrice(value, currencyCode: plan.currencyCode)
    }

    func saveBadgeText(for plan: PremiumProduct) -> String? {
        guard plan.periodly == "year" else { return nil }
        guard let monthly = service.products.first(where: { $0.periodly == "month" }),
              monthly.priceDecimal > 0
        else { return nil }
        let yearBaseline = monthly.priceDecimal * 12
        guard yearBaseline > 0 else { return nil }
        let savings = (yearBaseline - plan.priceDecimal) / yearBaseline * 100
        let percent = NSDecimalNumber(decimal: savings).intValue
        guard percent > 0 else { return nil }
        return L10n.tr("paywall.save_badge", "SAVE %lld%%", percent)
    }

    func formatPrice(_ value: Decimal, currencyCode: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.maximumFractionDigits = 2
        return f.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }
}

private extension InLessonsPaywallView {

    var bottomBar: some View {
        VStack(spacing: 10) {
            Button {
                Task { await service.completePurchase() }
            } label: {
                buttonLabel
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 28).fill(Color.lsPink))
            }
            .buttonStyle(.plain)
            .disabled(isButtonDisabled)
            .padding(.horizontal, 20)

            if isLoadingProducts {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 260, height: 15)
            } else {
                Text(footerText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            PaywallLegalFooter()
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    var buttonLabel: some View {
        if service.purchaseState == .purchasing || isLoadingProducts {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
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
            return L10n.tr("paywall.freechat.continue", "Unlock her voice")
        }
        if sel.includesTrial, let days = sel.trialDays {
            return L10n.tr("paywall.trial_button", "Start %lld-day free trial", days)
        }
        return L10n.tr("paywall.freechat.continue", "Unlock her voice")
    }

    var footerText: String {
        guard let sel = service.selection else { return "" }
        let period = footerPeriod(for: sel.periodly)
        if sel.includesTrial, let days = sel.trialDays {
            return L10n.tr("paywall.trial_footer_apple",
                          "%1$lld days free, then %2$@/%3$@. Cancel anytime in Apple ID settings.",
                          days, sel.pricePerPeriod, period)
        }
        return L10n.tr("paywall.default_footer_apple",
                      "%1$@/%2$@. Cancel anytime in Apple ID settings.",
                      sel.pricePerPeriod, period)
    }

    func footerPeriod(for periodly: String) -> String {
        switch periodly {
        case "year":  return L10n.tr("paywall.per.year", "year")
        case "month": return L10n.tr("paywall.per.month", "month")
        case "week":  return L10n.tr("paywall.per.week", "week")
        case "day":   return L10n.tr("paywall.per.day", "day")
        default:      return periodly
        }
    }
}
