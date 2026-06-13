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

    private let petals = [
        PetalProfile(angle: -3, width: 25, length: 52, phase: 0.2),
        PetalProfile(angle: 48, width: 28, length: 48, phase: 1.1),
        PetalProfile(angle: 101, width: 24, length: 54, phase: 2.4),
        PetalProfile(angle: 153, width: 27, length: 49, phase: 3.5),
        PetalProfile(angle: 207, width: 25, length: 53, phase: 4.7),
        PetalProfile(angle: 260, width: 29, length: 47, phase: 5.6),
        PetalProfile(angle: 312, width: 24, length: 51, phase: 6.5)
    ]

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
        let breath = sin(time * (isActive ? 0.86 : 0.34))
        let bodyScale = 1 + breath * (isActive ? 0.014 : 0.007)

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            theme.primaryText.opacity(0.13 + activity * 0.04),
                            theme.primaryText.opacity(0)
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 37
                    )
                )
                .frame(width: 76, height: 76)
                .scaleEffect(1 + breath * 0.04)

            ForEach(Array(petals.enumerated()), id: \.offset) { index, petal in
                petalLayer(petal, index: index, time: time, activity: activity, breath: breath)
            }

            nucleus(breath: breath, activity: activity, time: time)
        }
        .scaleEffect(bodyScale)
        .frame(width: 112, height: 112)
    }

    private func petalLayer(
        _ petal: PetalProfile,
        index: Int,
        time: TimeInterval,
        activity: Double,
        breath: Double
    ) -> some View {
        let independentPulse = sin(time * (0.62 + Double(index % 3) * 0.055) + petal.phase)
        let activeMotion = isActive ? activity : 0.16
        let lengthScale = 1 + breath * 0.012 + independentPulse * (0.006 + activeMotion * 0.026)
        let widthScale = 1 - independentPulse * activeMotion * 0.012
        let reach = 24.5 + independentPulse * activeMotion * 1.15
        let flex = independentPulse * activeMotion * 1.25
        let channelEnergy = (sin(time * 0.92 + petal.phase * 0.8) + 1) * 0.5

        return ZStack {
            OrganicPetal()
                .fill(
                    LinearGradient(
                        colors: [
                            theme.primaryText.opacity(0.48 + activity * 0.05),
                            theme.primaryText.opacity(0.29),
                            theme.primaryText.opacity(0.16)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    OrganicPetal()
                        .stroke(theme.primaryText.opacity(0.13), lineWidth: 0.65)
                }

            PetalChannelPath(bend: index.isMultiple(of: 2) ? 0.1 : -0.1)
                .stroke(
                    theme.primaryText.opacity(
                        0.22 + activity * 0.12 + (isActive ? channelEnergy * 0.10 : 0)
                    ),
                    style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round)
                )
                .padding(.horizontal, petal.width * 0.27)
                .padding(.vertical, petal.length * 0.12)
        }
        .frame(width: petal.width, height: petal.length)
        .scaleEffect(x: widthScale, y: lengthScale, anchor: .bottom)
        .offset(y: -reach)
        .rotationEffect(.degrees(petal.angle + flex))
    }

    private func nucleus(breath: Double, activity: Double, time: TimeInterval) -> some View {
        let pulse = sin(time * (isActive ? 1.18 : 0.5))

        return ZStack {
            Circle()
                .fill(theme.primaryText.opacity(0.08 + activity * 0.04))
                .frame(width: 33, height: 33)
                .scaleEffect(1 + pulse * (isActive ? 0.045 : 0.018))

            Circle()
                .stroke(theme.primaryText.opacity(0.28), lineWidth: 0.8)
                .frame(width: 23, height: 23)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            theme.primaryText.opacity(0.92),
                            theme.primaryText.opacity(0.58)
                        ],
                        center: UnitPoint(x: 0.42, y: 0.38),
                        startRadius: 1,
                        endRadius: 8
                    )
                )
                .frame(width: 14, height: 14)
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(theme.primaryText.opacity(0.72))
                        .frame(width: 2.5, height: 2.5)
                        .offset(x: 3.5, y: 3.5)
                }
                .scaleEffect(1 + breath * 0.06)
        }
    }
}

private struct PetalProfile {
    let angle: Double
    let width: CGFloat
    let length: CGFloat
    let phase: Double
}

private struct OrganicPetal: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centerX = rect.midX

        path.move(to: CGPoint(x: centerX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.height * 0.42),
            control1: CGPoint(x: rect.width * 0.34, y: rect.height * 0.83),
            control2: CGPoint(x: rect.width * 0.07, y: rect.height * 0.62)
        )
        path.addCurve(
            to: CGPoint(x: centerX, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.height * 0.19),
            control2: CGPoint(x: rect.width * 0.28, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.height * 0.46),
            control1: CGPoint(x: rect.width * 0.76, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.height * 0.22)
        )
        path.addCurve(
            to: CGPoint(x: centerX, y: rect.maxY),
            control1: CGPoint(x: rect.width * 0.91, y: rect.height * 0.68),
            control2: CGPoint(x: rect.width * 0.66, y: rect.height * 0.87)
        )
        path.closeSubpath()
        return path
    }
}

private struct PetalChannelPath: Shape {
    let bend: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centerX = rect.midX

        path.move(to: CGPoint(x: centerX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: centerX + rect.width * bend, y: rect.height * 0.12),
            control1: CGPoint(x: centerX - rect.width * 0.12, y: rect.height * 0.72),
            control2: CGPoint(x: centerX + rect.width * (0.28 + bend), y: rect.height * 0.43)
        )

        path.move(to: CGPoint(x: centerX + rect.width * 0.02, y: rect.height * 0.59))
        path.addCurve(
            to: CGPoint(x: centerX - rect.width * 0.21, y: rect.height * 0.39),
            control1: CGPoint(x: centerX - rect.width * 0.03, y: rect.height * 0.51),
            control2: CGPoint(x: centerX - rect.width * 0.16, y: rect.height * 0.47)
        )

        return path
    }
}
