import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct LanguageSchoolApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var premiumService: SubscriptionService = .shared
    @AppStorage("app.uiLanguage") private var uiLanguage: String = ""

    init() {
        AuthService.configure(
            googleClientID: AppConstants.Core.gogleAuth
        )
        premiumService.start()

        if UserDefaults.standard.string(forKey: "app.uiLanguage")?.isEmpty ?? true {
            let device = Locale.current.language.languageCode?.identifier ?? "en"
            let seeded = (device == "es") ? "es" : "en"
            UserDefaults.standard.set(seeded, forKey: "app.uiLanguage")
        }
        _ = Bundle.installAppLanguageSwizzle
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .environment(premiumService)
                .environment(\.locale, Locale(identifier: uiLanguage.isEmpty ? "en" : uiLanguage))
        }
        .modelContainer(AppModelContainer.shared)
    }
}
