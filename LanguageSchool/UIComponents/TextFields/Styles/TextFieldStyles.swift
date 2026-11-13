import SwiftUI

struct OnboardingFieldStyle: TextFieldStyle {
    var cornerRadius: CGFloat = 16
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .foregroundStyle(Color(hex: "#C7C7D1"))
            .glassedEffect(
                in: RoundedRectangle(cornerRadius: cornerRadius),
                isClear: false,
                tint: .white.opacity(0.14),
                interactive: false
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(0.3),lineWidth: 1)
            )
    }
}
