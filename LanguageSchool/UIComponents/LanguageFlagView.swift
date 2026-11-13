import SwiftUI

/// Стилизованный флаг в круге. Одна точка правды для языковых флагов
/// (Profile, Settings, LanguagePicker).
struct LanguageFlagView: View {
    let language: LanguageCode
    var size: CGFloat = 28

    var body: some View {
        switch language {
        case .es:
            Circle()
                .fill(Color(hex: "#E53838"))
                .frame(width: size, height: size)
                .overlay(
                    Rectangle()
                        .fill(Color(hex: "#FFCC33"))
                        .frame(height: size * 11 / 28)
                )
                .clipShape(Circle())
        case .en:
            Circle()
                .fill(Color(hex: "#162870"))
                .frame(width: size, height: size)
                .overlay(
                    Group {
                        Rectangle().fill(Color.white).frame(width: size, height: size * 6 / 28)
                        Rectangle().fill(Color.white).frame(width: size * 6 / 28, height: size)
                        Rectangle().fill(Color(hex: "#CC1E2D")).frame(width: size, height: size * 3 / 28)
                        Rectangle().fill(Color(hex: "#CC1E2D")).frame(width: size * 3 / 28, height: size)
                    }
                )
                .clipShape(Circle())
        }
    }
}
