import SwiftUI

/// Общий низ пейвольных экранов: три ссылки маленьким серым текстом —
/// Restore | Terms | Privacy. Требование App Review (App Store guidelines
/// 3.1.1 / 3.1.2): на любом экране покупки должны быть видимые Restore
/// Purchases и ссылки на Terms of Use и Privacy Policy.
///
/// Restore зовёт `SubscriptionService.restore()` — тот же путь что и в
/// Settings → «Restore purchases». Terms/Privacy открывают внешний
/// браузер (Link) по URL'ам из `AppConstants.K`.
struct PaywallLegalFooter: View {
    @Environment(SubscriptionService.self) private var service

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Task { await service.restore() }
            } label: {
                Text(L10n.tr("paywall.legal.restore", "Restore"))
            }
            .buttonStyle(.plain)

            Text("·").foregroundStyle(Color(hex: "#5A5A63"))

            if let url = URL(string: AppConstants.K.termsURL) {
                Link(destination: url) {
                    Text(L10n.tr("paywall.legal.terms", "Terms"))
                }
            }

            Text("·").foregroundStyle(Color(hex: "#5A5A63"))

            if let url = URL(string: AppConstants.K.privacyURL) {
                Link(destination: url) {
                    Text(L10n.tr("paywall.legal.privacy", "Privacy"))
                }
            }
        }
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(Color(hex: "#9A9AA3"))
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}
