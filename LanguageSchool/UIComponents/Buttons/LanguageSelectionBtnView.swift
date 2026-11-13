import SwiftUI

struct LanguageSelectionBtnView: View {
    let language: LanguageCode
    let isSelected: Bool
    let action: (LanguageCode) -> Void

    var body: some View {
        Button {
            action(language)
        } label: {
            Text(language.displayTitle)
                .font(.system(size: 17, weight: .semibold))
        }
        .buttonStyle(
            AdaptiveLanguageBtnStyle(isSelected: isSelected)
        )
    }
}

#Preview {
    LanguageSelectionBtnView(language: .en, isSelected: false, action: { _ in })
}
