import Foundation
import ObjectiveC

private final class AppLanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        L10n.langBundle().localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    static let installAppLanguageSwizzle: Void = {
        object_setClass(Bundle.main, AppLanguageBundle.self)
    }()
}

nonisolated enum L10n {

    static func langBundle() -> Bundle {
        let uiLang = UserDefaults.standard.string(forKey: "app.uiLanguage") ?? "en"
        if let path = Bundle.main.path(forResource: uiLang, ofType: "lproj"),
           let b = Bundle(path: path) {
            return b
        }
        return Bundle.main
    }

    static func tr(_ key: String, _ defaultValue: String) -> String {
        langBundle().localizedString(forKey: key, value: defaultValue, table: nil)
    }

    static func tr(_ key: String, _ defaultValue: String, _ args: any CVarArg...) -> String {
        let template = langBundle().localizedString(forKey: key, value: defaultValue, table: nil)
        return String(format: template, arguments: args)
    }
}
