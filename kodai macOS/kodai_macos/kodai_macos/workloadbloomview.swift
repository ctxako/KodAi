//
//  workloadbloomview.swift
//  kodai_macos
//

import SwiftUI

struct WorkloadBloomView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.kodaiTheme) private var theme

    let isActive: Bool
    let activityLevel: Double

    private var normalizedActivity: Double {
        min(max(activityLevel, 0), 1)
    }

    var body: some View {
        Group {
            if reduceMotion {
                bloom(at: 0)
            } else {
                TimelineView(.periodic(from: .now, by: isActive ? 1.0 / 15.0 : 1.0 / 8.0)) { context in
                    bloom(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isActive ? "Kodai is responding" : "Kodai is idle")
    }

    private func bloom(at time: TimeInterval) -> some View {
        let activity = normalizedActivity
        let baseScale = 0.96 + activity * 0.05
        let breath = sin(time * (isActive ? 1.15 : 0.28)) * (isActive ? 0.025 : 0.008)

        return ZStack {
            ForEach(0..<8, id: \.self) { index in
                let phase = Double(index) * 0.73
                let pulse = sin(time * (1.0 + Double(index % 3) * 0.08) + phase)
                let petalScale = baseScale + breath + pulse * (0.008 + activity * 0.035)
                let petalOffset = 25.0 + activity * 2.5 + pulse * activity * 1.6

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                theme.primaryText.opacity(0.52),
                                theme.primaryAccent.opacity(0.34)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 20, height: 48)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(theme.primaryText.opacity(0.12), lineWidth: 0.7)
                    }
                    .scaleEffect(x: 0.94 + activity * 0.04, y: petalScale)
                    .offset(y: -petalOffset)
                    .rotationEffect(.degrees(Double(index) * 45 + pulse * activity * 1.4))
            }

            Circle()
                .fill(theme.primaryAccent.opacity(0.26))
                .frame(width: 31, height: 31)

            Circle()
                .fill(theme.primaryText.opacity(0.72))
                .frame(width: 13, height: 13)
                .scaleEffect(1 + breath * 0.7)
        }
        .frame(width: 112, height: 112)
    }
}
