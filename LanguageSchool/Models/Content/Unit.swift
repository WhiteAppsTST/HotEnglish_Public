import Foundation

nonisolated
enum UnitUnlockRule: Hashable, Sendable {
    case afterUnit(String)
}

nonisolated
struct Unit: Identifiable, Hashable, Sendable {
    let id: String
    let order: Int
    let title: String
    /// SF-Symbol name или emoji-строка. См. `isIconEmoji`.
    let iconName: String
    let isPremium: Bool
    let grade: LangGrade
    let unlockRule: UnitUnlockRule?
    let steps: [Step]
}

extension Unit {
    /// `true` если `iconName` содержит emoji-символ, `false` для SF-Symbol.
    /// Используется вью-слоем чтобы выбрать между `Text(icon)` и
    /// `Image(systemName: icon)`.
    var isIconEmoji: Bool {
        iconName.unicodeScalars.first?.properties.isEmoji ?? false
    }
}
