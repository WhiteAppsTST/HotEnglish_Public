import SwiftUI
import PhotosUI

extension View {
    var isSmallScreen: Bool {
        UIScreen.main.bounds.height < 700
    }
    
    var isLargeScreen: Bool {
        UIScreen.main.bounds.height > 900
    }
    
    var isIos26: Bool {
        if #available(iOS 26, *) {
            return true
        } else {
            return false
        }
    }
    
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}

extension View {
    @ViewBuilder
    func glassedEffect(
        in shape: some Shape,
        interactive: Bool = false) -> some View {
            
            if #available(iOS 26, *) {
                if interactive {
                    self.glassEffect(.regular.interactive(), in: shape)
                } else {
                    self.glassEffect(in: shape)
                }
            } else {
                self.background {
                    shape.glassed()
                }
            }
    }
    
    @ViewBuilder
    func mainButtonStyle(tint: Color = .accentColor) -> some View {
        if #available(iOS 26, *) {
            self
                .tint(tint)
                .buttonStyle(.glassProminent)
        } else {
            self
                .background(tint)
                .clipShape(.capsule)
                .background { Capsule().glassed() }
        }
    }
    
    func textEditorBackground<Background: View>(_ content: Background) -> some View {
        return self
            .scrollContentBackground(.hidden)
            .background(content)
    }
    
    func stretchy() -> some View {
        visualEffect { effect, geometry in
            let currentHeight = geometry.size.height
            let scrollOffset = geometry.frame(in: .scrollView).minY
            let positiveOffset = max(0, scrollOffset)
            
            let newHeight = currentHeight + positiveOffset
            let scaleFactor = newHeight / currentHeight
            
            return effect.scaleEffect(
                x: scaleFactor,
                y: scaleFactor,
                anchor: .bottom
            )
        }
    }
    
    func detailLyricalStyle() -> some View {
        self
            .font(.system(size: 18))
            .fontWeight(.semibold)
            .fontDesign(.rounded)
            .foregroundStyle(.white.opacity(0.9))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineSpacing(8)
    }
    
    
    func concentricShape() -> some Shape {
        if #available(iOS 26.0, *) {
            return ConcentricRectangle()
        } else {
            return RoundedRectangle(cornerRadius: 16)
        }
    }
}

extension View {
    @ViewBuilder
    func glassedEffect(
        in shape: some Shape,
        isClear: Bool = false,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
            if #available(iOS 26, *) {
                if interactive {
                    self.glassEffect(isClear ? .clear.interactive().tint(tint) : .regular.interactive().tint(tint), in: shape)
                } else {
                    self.glassEffect(isClear ? .clear.tint(tint) : .regular.tint(tint), in: shape)
                }
            } else {
                self
                    .background(tint)
                    .clipShape(shape)
                    .background {
                    shape.glassed()
                }
            }
    }

    
    @ViewBuilder
    func minimizeTabBarSize() -> some View {
        if #available(iOS 26, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func clipShapeConcentric() -> some View {
        if #available(iOS 26.0, *) {
            self
                .clipShape(.rect(corners: .concentric, isUniform: true))
        } else {
            self
                .clipShape(.rect(cornerRadius: 16))
        }
    }
    
    func mainShapeRadius(_ color: Color = .white.opacity(0.2)) -> some View {
        self
            .background(color)
            .background(.ultraThinMaterial)
            .containerShape(.rect(cornerRadius: 24))
    }
}

extension View {
    @ViewBuilder
    func matchedTransitionSourceIfAvailable(id: String, in ns: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            self.matchedTransitionSource(id: id, in: ns)
        } else {
            self
        }
    }

    @ViewBuilder
    func navigationTransitionIfAvailable(sourceID: String, in ns: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            self.navigationTransition(.zoom(sourceID: sourceID, in: ns))
        } else {
            self
        }
    }
}
