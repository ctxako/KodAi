import SwiftUI

struct LiquidGlassBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                ChatPalette.canvasGlow.opacity(0.60),
                ChatPalette.mainCanvas,
                Color.black.opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct LiquidGlassPanel: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(tint.opacity(0.62), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .glassEffect(.regular.tint(tint.opacity(0.62)), in: shape)
            .overlay {
                shape.stroke(ChatPalette.glassStroke, lineWidth: 0.7)
            }
    }
}

struct DrawerGlassRow: ViewModifier {
    let isSelected: Bool
    let isDimmed: Bool
    let verticalPadding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let tint = isSelected ? ChatPalette.statusSurface : ChatPalette.inputField
        let fillOpacity = isSelected ? 0.28 : 0.14
        let strokeOpacity = isSelected ? 0.09 : 0.04

        content
            .padding(.horizontal, 10)
            .padding(.vertical, verticalPadding)
            .background(tint.opacity(fillOpacity), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .glassEffect(.regular.tint(tint.opacity(fillOpacity)), in: shape)
            .overlay {
                shape.stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.45)
            }
            .opacity(isDimmed ? 0.58 : 1)
    }
}

struct MessageBubbleGlass: ViewModifier {
    let tint: Color
    let isUser: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let tintOpacity = isUser ? 0.56 : 0.24

        content
            .background(tint.opacity(tintOpacity), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .glassEffect(.regular.tint(tint.opacity(tintOpacity)), in: shape)
            .overlay {
                shape.stroke(Color.white.opacity(isUser ? 0.08 : 0.10), lineWidth: 0.45)
            }
            .shadow(color: Color.black.opacity(isUser ? 0.14 : 0.18), radius: 10, x: 0, y: 6)
    }
}

extension View {
    func liquidGlassPanel(tint: Color, cornerRadius: CGFloat) -> some View {
        modifier(LiquidGlassPanel(tint: tint, cornerRadius: cornerRadius))
    }

    func drawerGlassRow(
        isSelected: Bool = false,
        isDimmed: Bool = false,
        verticalPadding: CGFloat = 8
    ) -> some View {
        modifier(DrawerGlassRow(isSelected: isSelected, isDimmed: isDimmed, verticalPadding: verticalPadding))
    }

    func messageBubbleGlass(tint: Color, isUser: Bool) -> some View {
        modifier(MessageBubbleGlass(tint: tint, isUser: isUser))
    }
}
