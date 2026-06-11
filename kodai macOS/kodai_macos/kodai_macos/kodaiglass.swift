//
//  kodaiglass.swift
//  kodai_macos
//

import SwiftUI

extension View {
    @ViewBuilder
    func kodaiGlass(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .glassEffect(
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            self
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
        }
    }
}
