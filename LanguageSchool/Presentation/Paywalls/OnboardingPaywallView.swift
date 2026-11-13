import SwiftUI

struct OnboardingPaywallView: View {
    let teacher: TeacherProfile
    @Environment(SubscriptionService.self) private var service
    @State private var avatar = AvatarPlayer()

    var body: some View {
        ZStack {
            AvatarPlayerView(player: avatar.videoPlayer)

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.45), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 150)

                Spacer(minLength: 0)

                LinearGradient(
                    stops: [
                        .init(color: Color(red: 10/255, green: 10/255, blue: 12/255).opacity(0), location: 0),
                        .init(color: Color(red: 10/255, green: 10/255, blue: 12/255).opacity(0.78), location: 0.45),
                        .init(color: Color(red: 10/255, green: 10/255, blue: 12/255).opacity(0.98), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 560)
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

    private var closeButton: some View {
        Button {
            service.hidePaywall()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }

    private func configureAvatar() {
        if let idle = teacher.lessonVideo(.idle) {
            avatar.setBase(video: idle)
        }
    }
}

private extension OnboardingPaywallView {

    var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            titleBlock
                .padding(.horizontal, 20)
                .padding(.bottom, 18)

            includedList
                .padding(.horizontal, 20)
                .padding(.bottom, 22)

            plansBlock
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            bottomBar
        }
    }

    /// ТЗ (sec_470, «пример пэйвола после онборда»):
    /// «Давай заниматься вместе. Я найду, чем тебя наградить.»
    var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.tr("paywall.onboarding.title_1", "Let’s do this together."))
            Text(L10n.tr("paywall.onboarding.title_2", "I’ll find a way to reward you."))
        }
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var includedList: some View {
        VStack(alignment: .leading, spacing: 13) {
            includedItem("All five teachers unlocked")
            includedItem("Switch any time, progress carries over")
            includedItem("Unlimited lessons every day")
            includedItem("Dates and story continuation")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func includedItem(_ text: LocalizedStringKey) -> some View {
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

private extension OnboardingPaywallView {

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

    var planSkeletonRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Color.white.opacity(0.10)).frame(width: 80, height: 14)
                Capsule().fill(Color.white.opacity(0.06)).frame(width: 140, height: 10)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                Capsule().fill(Color.white.opacity(0.10)).frame(width: 60, height: 14)
                Capsule().fill(Color.white.opacity(0.06)).frame(width: 70, height: 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(height: 68)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#18181D")))
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
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .frame(height: 21)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.lsPink))
                    }
                }

                Text(subtitle(for: plan))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(plan.pricePerPeriod)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(billedNote(for: plan))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#18181D")))
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

    func subtitle(for plan: PremiumProduct) -> String {
        if plan.periodly == "year", let perWeek = perWeekEquivalent(plan) {
            return L10n.tr("paywall.perweek_subtitle", "%@ per week", perWeek)
        }
        return billedNote(for: plan)
    }

    func billedNote(for plan: PremiumProduct) -> String {
        switch plan.periodly {
        case "year":  return L10n.tr("paywall.billed.yearly", "billed yearly")
        case "month": return L10n.tr("paywall.billed.monthly", "billed monthly")
        case "week":  return L10n.tr("paywall.billed.weekly", "billed weekly")
        case "day":   return L10n.tr("paywall.billed.daily", "billed daily")
        default:      return ""
        }
    }

    func perWeekEquivalent(_ plan: PremiumProduct) -> String? {
        let weeks: Decimal
        switch plan.periodly {
        case "year":  weeks = 52
        case "month": weeks = 4.33
        case "week":  weeks = 1
        default:      return nil
        }
        let value = plan.priceDecimal / weeks
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

private extension OnboardingPaywallView {

    var bottomBar: some View {
        VStack(spacing: 10) {
            Button {
                Task { await service.completePurchase() }
            } label: {
                buttonLabel
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(RoundedRectangle(cornerRadius: 32).fill(Color.lsPink))
            }
            .buttonStyle(.plain)
            .disabled(isButtonDisabled)
            .padding(.horizontal, 20)

            if isLoadingProducts {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 260, height: 14)
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
            return L10n.tr("paywall.onboarding.continue", "Continue & Subscribe")
        }
        if sel.includesTrial, let days = sel.trialDays {
            return L10n.tr("paywall.trial_button", "Start %lld-day free trial", days)
        }
        return L10n.tr("paywall.onboarding.continue", "Continue & Subscribe")
    }

    var footerText: String {
        guard let sel = service.selection else { return "" }
        let period = footerPeriod(for: sel.periodly)
        if sel.includesTrial, let days = sel.trialDays {
            return L10n.tr("paywall.onboarding.trial_footer",
                          "%1$lld days Free, then %2$@ per %3$@. Cancel anytime.",
                          days, sel.pricePerPeriod, period)
        }
        return L10n.tr("paywall.onboarding.default_footer",
                      "%1$@ per %2$@. Cancel anytime.",
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
