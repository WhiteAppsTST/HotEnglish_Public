import SwiftUI

struct FreeChatPaywallView: View {
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }
}

private extension FreeChatPaywallView {

    var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            titleBlock
                .padding(.horizontal, 20)
                .padding(.bottom, 18)

            benefitsCard
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            plansBlock
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            bottomBar
        }
    }

    /// ТЗ (sec_470, «при попытке свободного диалога»):
    /// «Я умею говорить не только про грамматику»
    var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("paywall.free_chat.title",
                        "I can talk about more\nthan just grammar"))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)

            Text(L10n.tr("paywall.free_chat.subtitle",
                        "Voice messages both ways, no daily cap."))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            benefit("Unlimited Voice in Free chat", pinkOpacity: 0.28)
            benefit("Unlock hints and help", pinkOpacity: 0.28)
            benefit("Unlimited messages in free talk", pinkOpacity: 0.18)
            benefit("Every teacher unlocked", pinkOpacity: 0.18)
            benefit("Dates in voice, not text", pinkOpacity: 0.18)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.10))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    func benefit(_ text: LocalizedStringKey, pinkOpacity: Double) -> some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(Color.lsPink.opacity(pinkOpacity))
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

private extension FreeChatPaywallView {

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

    var planSkeletonRow: some View {
        HStack(alignment: .center, spacing: 12) {
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
                            .frame(height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
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

                Text(subtitle(for: plan))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(hex: "#9A9AA3"))
            }

            Spacer(minLength: 0)

            Text(plan.pricePerPeriod)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
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
        if plan.periodly == "year", let perMonth = perMonthEquivalent(plan) {
            return L10n.tr("paywall.permonth_slash_subtitle", "%@ / month", perMonth)
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

private extension FreeChatPaywallView {

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
