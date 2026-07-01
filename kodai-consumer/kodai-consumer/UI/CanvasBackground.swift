//
//  CanvasBackground.swift
//  kodai-consumer
//
//  The app's dark canvas gradient: a soft blue glow in the top-leading corner
//  that fades diagonally down into near-black. Layer it as the bottom of a
//  ZStack behind everything (and pair it with a dark color scheme so the glass
//  and text read correctly against it).
//

import SwiftUI

struct CanvasBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                ConsumerPalette.canvasGlow.opacity(0.60),
                ConsumerPalette.mainCanvas,
                Color.black.opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

/// The "kodAI" wordmark rendered as a Liquid Glass capsule — drop it into the
/// header in place of a plain navigation title.
struct KodaiTitleBadge: View {
    var body: some View {
        Text("kodAI")
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassEffect(.regular.tint(ConsumerPalette.elevatedSurface), in: Capsule())
            .accessibilityLabel("kodAI")
            .accessibilityAddTraits(.isHeader)
    }
}
