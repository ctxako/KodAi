//
//  workloadbloomview.swift
//  kodai_macos
//

import SwiftUI

struct WorkloadBloomView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.kodaiTheme) private var theme

    let signalState: LiveEntitySignalState

    private let petals = [
        PetalProfile(sign: .modelPulse, angle: -4, width: 28, length: 55, phase: 0.2),
        PetalProfile(sign: .contextPressure, angle: 55, width: 26, length: 49, phase: 1.3),
        PetalProfile(sign: .responseHeat, angle: 116, width: 29, length: 52, phase: 2.1),
        PetalProfile(sign: .focusLock, angle: 178, width: 27, length: 50, phase: 3.7),
        PetalProfile(sign: .taskPressure, angle: 237, width: 25, length: 54, phase: 4.6),
        PetalProfile(sign: .readiness, angle: 302, width: 28, length: 51, phase: 5.8)
    ]

    var body: some View {
        Group {
            if reduceMotion {
                bloom(at: 0)
            } else {
                TimelineView(.periodic(from: .now, by: signalState.isActive ? 1.0 / 15.0 : 1.0 / 8.0)) { context in
                    bloom(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kodai is \(signalState.status.rawValue.lowercased())")
    }

    private func bloom(at time: TimeInterval) -> some View {
        let breath = sin(time * (signalState.isActive ? 0.82 : 0.3))
        let activeGlow = signalState.isActive ? (sin(time * 1.05) + 1) * 0.5 : 0
        let coreEnergy = max(signalState.modelPulse * 0.58, signalState.responseHeat)

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            theme.primaryText.opacity(0.05 + coreEnergy * 0.1 + activeGlow * 0.035),
                            theme.primaryText.opacity(0.035 + signalState.readiness * 0.035),
                            theme.primaryText.opacity(0)
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 42
                    )
                )
                .frame(width: 86, height: 86)
                .scaleEffect(1 + breath * (signalState.isActive ? 0.045 : 0.018))

            ForEach(Array(petals.enumerated()), id: \.offset) { index, petal in
                petalLayer(petal, index: index, time: time, breath: breath)
            }

            nucleus(breath: breath, time: time)
        }
        .scaleEffect(1 + breath * (signalState.isActive ? 0.012 : 0.005))
        .frame(width: 112, height: 112)
        .animation(.easeInOut(duration: 0.42), value: signalState)
    }

    private func petalLayer(
        _ petal: PetalProfile,
        index: Int,
        time: TimeInterval,
        breath: Double
    ) -> some View {
        let energy = energy(for: petal.sign)
        let independentPulse = sin(time * pulseSpeed(for: petal.sign) + petal.phase)
        let motion = motionAmount(for: petal.sign)
        let lengthScale = 0.94 + energy * 0.075 + breath * 0.008 + independentPulse * motion
        let tension = petal.sign == .taskPressure ? energy * 0.025 : 0
        let widthScale = 0.98 + energy * 0.025 - tension
        let reach = 24 + energy * 2.1 + independentPulse * motion * 13
        let flex = independentPulse * motion * 18
        let pathEnergy = signalState.readiness * 0.5 + signalState.contextPressure * 0.28 + energy * 0.22

        return ZStack {
            OrganicPetal()
                .fill(
                    LinearGradient(
                        colors: [
                            theme.primaryText.opacity(0.31 + energy * 0.25),
                            theme.primaryText.opacity(0.22 + energy * 0.16),
                            theme.primaryText.opacity(0.11 + energy * 0.09)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    OrganicPetal()
                        .stroke(theme.primaryText.opacity(0.09 + energy * 0.13), lineWidth: 0.7)
                }
                .shadow(color: theme.primaryText.opacity(0.025 + energy * 0.04), radius: 4)

            PetalChannelPath(bend: index.isMultiple(of: 2) ? 0.1 : -0.1)
                .stroke(
                    theme.primaryText.opacity(0.11 + pathEnergy * 0.31),
                    style: StrokeStyle(
                        lineWidth: 0.75 + signalState.readiness * 0.2,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .padding(.horizontal, petal.width * 0.27)
                .padding(.vertical, petal.length * 0.12)
        }
        .frame(width: petal.width, height: petal.length)
        .scaleEffect(x: widthScale, y: lengthScale, anchor: .bottom)
        .offset(y: -reach)
        .rotationEffect(.degrees(petal.angle + flex))
    }

    private func nucleus(breath: Double, time: TimeInterval) -> some View {
        let pulse = sin(time * (signalState.isActive ? 1.14 : 0.46))
        let heat = signalState.responseHeat
        let readiness = signalState.readiness
        let coreScale = 1 + pulse * (0.012 + heat * 0.055)

        return ZStack {
            Circle()
                .fill(theme.primaryText.opacity(0.045 + heat * 0.13))
                .frame(width: 38, height: 38)
                .scaleEffect(1 + pulse * (0.012 + heat * 0.04))

            Circle()
                .stroke(theme.primaryText.opacity(0.15 + readiness * 0.22), lineWidth: 0.75)
                .frame(width: 25, height: 25)

            CoreCircuitPath()
                .stroke(
                    theme.primaryText.opacity(0.12 + readiness * 0.43),
                    style: StrokeStyle(lineWidth: 0.72, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 29, height: 29)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            theme.primaryText.opacity(0.96),
                            theme.primaryText.opacity(0.48 + heat * 0.3)
                        ],
                        center: UnitPoint(x: 0.42, y: 0.38),
                        startRadius: 1,
                        endRadius: 8
                    )
                )
                .frame(width: 14, height: 14)
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(theme.primaryText.opacity(0.75))
                        .frame(width: 2.5, height: 2.5)
                        .offset(x: 3.5, y: 3.5)
                }
                .scaleEffect(coreScale + breath * 0.018)
        }
    }

    private func energy(for sign: LifeSign) -> Double {
        switch sign {
        case .modelPulse:
            return signalState.modelPulse
        case .contextPressure:
            return signalState.contextPressure
        case .responseHeat:
            return signalState.responseHeat
        case .focusLock:
            return signalState.focusLock
        case .taskPressure:
            return signalState.taskPressure
        case .readiness:
            return 0.12 + signalState.readiness * 0.24
        }
    }

    private func motionAmount(for sign: LifeSign) -> Double {
        switch sign {
        case .modelPulse:
            return 0.01 + signalState.modelPulse * 0.045
        case .responseHeat:
            return 0.008 + signalState.responseHeat * 0.025
        case .taskPressure:
            return 0.006 + signalState.taskPressure * 0.009
        case .contextPressure, .readiness:
            return 0.006
        case .focusLock:
            return 0.002
        }
    }

    private func pulseSpeed(for sign: LifeSign) -> Double {
        switch sign {
        case .modelPulse:
            return signalState.isActive ? 0.92 : 0.42
        case .responseHeat:
            return signalState.isActive ? 1.08 : 0.5
        case .taskPressure:
            return 0.68
        case .contextPressure:
            return 0.54
        case .readiness:
            return 0.48
        case .focusLock:
            return 0.34
        }
    }
}

private enum LifeSign: Equatable {
    case modelPulse
    case contextPressure
    case responseHeat
    case focusLock
    case taskPressure
    case readiness
}

private struct PetalProfile {
    let sign: LifeSign
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

private struct CoreCircuitPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let midY = rect.midY

        path.move(to: CGPoint(x: midX, y: rect.minY))
        path.addLine(to: CGPoint(x: midX, y: rect.minY + rect.height * 0.24))
        path.addLine(to: CGPoint(x: midX + rect.width * 0.14, y: midY - rect.height * 0.12))

        path.move(to: CGPoint(x: rect.maxX, y: midY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.24, y: midY))
        path.addLine(to: CGPoint(x: midX + rect.width * 0.12, y: midY + rect.height * 0.14))

        path.move(to: CGPoint(x: midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: midX, y: rect.maxY - rect.height * 0.22))
        path.addLine(to: CGPoint(x: midX - rect.width * 0.13, y: midY + rect.height * 0.12))

        path.move(to: CGPoint(x: rect.minX, y: midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.23, y: midY))
        path.addLine(to: CGPoint(x: midX - rect.width * 0.12, y: midY - rect.height * 0.13))

        return path
    }
}
