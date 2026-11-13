import SwiftUI

struct MainPinkBtnStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 15.5)
            .frame(maxWidth: .infinity)
            .background(Color.lsPink)
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.linear(duration: 0.15), value: isEnabled)
    }
}

struct MainPinkBorderedBtnStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.lsPink)
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .background(
                Capsule()
                    .stroke(Color(hex: "#FF96BE"),lineWidth: 1)
            )
            .contentShape(Capsule())
    }
}

struct MainCapsuleGlassedBtnStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .glassedEffect(
                in: Capsule(),
                isClear: false,
                tint: .white.opacity(0.16),
                interactive: false
            )
            .contentShape(Capsule())
    }
}

struct AdaptiveLanguageBtnStyle: ButtonStyle {
    let isSelected: Bool

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if isSelected {
            MainPinkBorderedBtnStyle().makeBody(configuration: configuration)
        } else {
            MainCapsuleGlassedBtnStyle().makeBody(configuration: configuration)
        }
    }
}

struct HomeTalkPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.black.opacity(0.35)))
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct HomeContinuePillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.lsPink))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
