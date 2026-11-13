import Foundation

struct AppConstants {
    struct Core {
        static let gogleAuth: String = "192110905807-3bc21mkit38901cje9fgdjctv5t1vv9k.apps.googleusercontent.com"
    }

    struct K {
        static let privacyURL: String = "https://sites.google.com/view/halo-hub-gateway-manager/privacy-policy?authuser=1"
        static let termsURL: String = "https://sites.google.com/view/halo-hub-gateway-manager/terms-of-use?authuser=1"
    }

    enum API {
        static let baseURL = URL(string: "https://api.aurorabvb.online")!
    }
}
