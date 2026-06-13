//
//  kodaiglass.swift
//  kodai_macos
//

import SwiftUI

private struct KodaiGlassModifier: ViewModifier {
    @Environment(\.kodaiTheme) private var theme

    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .background(theme.glassSurface)
                .glassEffect(
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(theme.glassBorder, lineWidth: 1)
                }
        } else {
            content
                .background(.ultraThinMaterial)
                .background(theme.glassSurface)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(theme.glassBorder, lineWidth: 1)
                }
        }
    }
}

extension View {
    func kodaiGlass(cornerRadius: CGFloat) -> some View {
        modifier(KodaiGlassModifier(cornerRadius: cornerRadius))
    }
}
