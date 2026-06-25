//
//  ThinkingDotsView.swift
//  kodai-consumer
//
//  Three bouncing dots shown while the model generates. Ported from the
//  chatbot-dev MessageBubble; dependency-free (SwiftUI + Color.secondary).
//  Honors Reduce Motion — the dots hold still when motion is reduced.
//

import SwiftUI

struct ThinkingDotsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                BouncingDot(delay: Double(i) * 0.15, isAnimated: !reduceMotion)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("Thinking")
    }
}

private struct BouncingDot: View {
    let delay: Double
    let isAnimated: Bool
    @State private var isUp = false

    var body: some View {
        Circle()
            .fill(Color.secondary.opacity(0.55))
            .frame(width: 7, height: 7)
            .offset(y: isUp ? -5 : 0)
            .onAppear {
                guard isAnimated else { return }
                withAnimation(
                    .easeInOut(duration: 0.45)
                    .delay(delay)
                    .repeatForever(autoreverses: true)
                ) {
                    isUp = true
                }
            }
    }
}
