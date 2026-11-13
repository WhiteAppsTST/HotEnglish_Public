import Foundation

nonisolated
enum LanguageCode: String, Codable, CaseIterable, Identifiable, Sendable {
    case en
    case es

    var id: Self { self }

    var displayTitle: String {
        switch self {
        case .en: L10n.tr("lang.en", "English")
        case .es: L10n.tr("lang.es", "Spanish")
        }
    }

    var flagAssetName: String {
        switch self {
        case .en: "flag_en"
        case .es: "flag_es"
        }
    }
}
