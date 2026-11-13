import SwiftUI

struct LanguageReasonBtnView: View {
    let title: LocalizedStringResource
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    isSelected ? .lsPink : .white.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 16)
                )
        }
    }
}

#Preview {
    LanguageReasonBtnView(title: "test", isSelected: true, action: {})
}
