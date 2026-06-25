//
//  glassboxview.swift
//  kodai_macos
//

import SwiftUI
import KodaiCore

struct GlassBoxView: View {
    @Environment(\.kodaiTheme) private var theme

    let signalState: LiveEntitySignalState
    let latestTurn: TurnRecord?
    let onClose: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                contextSection
                liveSignalsSection
            }
            .padding(34)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("glassBox.detail")
    }

    // The honest macOS glass box: Foundation Models is sealed at the token
    // level, but the context we assemble *into* it is fully inspectable.
    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What shaped the last answer")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.primaryText)

            if let turn = latestTurn {
                WhyThisAnswerPanel(turn: turn)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kodaiGlass(cornerRadius: 18)
            } else {
                Text("Send a message — its model, timing, and the exact context blocks that shaped it (included, truncated, or excluded, each with a token cost) appear here.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .kodaiGlass(cornerRadius: 18)
            }
        }
    }

    private var liveSignalsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live signals")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.primaryText)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 28) {
                    liveEntity
                    signalGrid
                }
                VStack(spacing: 18) {
                    liveEntity
                    signalGrid
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Glass Box")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.primaryText)

                Text("Context inspector")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer()

            Button(action: onClose) {
                Label("Back to chat", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .accessibilityIdentifier("glassBox.backToChat")
            .buttonStyle(.plain)
            .foregroundStyle(theme.secondaryText)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .contentShape(Capsule())
            .background(theme.glassSurface, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(theme.glassBorder, lineWidth: 1)
            }
        }
    }

    private var liveEntity: some View {
        VStack(spacing: 18) {
            WorkloadBloomView(
                signalState: signalState
            )
            .scaleEffect(1.25)
            .frame(width: 150, height: 150)

            HStack(spacing: 7) {
                Circle()
                    .fill(theme.primaryText.opacity(signalState.isActive ? 0.9 : 0.55))
                    .frame(width: 7, height: 7)

                Text(signalState.status.rawValue)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityIdentifier("glassBox.status")
            }
        }
        .padding(20)
        .frame(width: 220, height: 230)
        .kodaiGlass(cornerRadius: 22)
    }

    private var signalGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            signalCard(
                title: "Model Pulse",
                value: signalState.status.rawValue,
                detail: modelPulseDetail,
                isActivityCard: true
            )
            signalCard(
                title: "Context Pressure",
                value: "\(signalState.contextPercent)%",
                detail: contextDetail
            )
            signalCard(
                title: "Response Heat",
                value: signalState.isActive ? "Elevated" : "Low",
                detail: responseHeatDetail
            )
            signalCard(
                title: "Focus Lock",
                value: signalState.selectedProjectName ?? "None",
                detail: signalState.selectedProjectName == nil ? "No project focus" : "Current thread focus"
            )
            signalCard(
                title: "Task Pressure",
                value: "\(signalState.tasksDueCount)",
                detail: signalState.tasksDueCount == 0 ? "Nothing due today" : signalState.tasksDueCount == 1 ? "One task needs attention" : "Due today or overdue"
            )
            signalCard(
                title: "Readiness",
                value: readinessValue,
                detail: readinessDetail
            )
        }
        .frame(maxWidth: 520)
    }

    private func signalCard(
        title: String,
        value: String,
        detail: String,
        isActivityCard: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)

            Text(detail)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(theme.secondaryText.opacity(0.75))
                .lineLimit(2)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .kodaiGlass(cornerRadius: 14)
        .overlay {
            if isActivityCard && signalState.isActive {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.primaryAccent.opacity(0.045))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(theme.primaryAccent.opacity(0.24), lineWidth: 1)
                    }
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: signalState.status)
    }

    private var modelPulseDetail: String {
        switch signalState.status {
        case .idle:
            return "Model is standing by"
        case .thinking:
            return "Preparing the local response"
        case .responding:
            return "Streaming the local response"
        }
    }

    private var responseHeatDetail: String {
        signalState.isActive ? "Generation energy is awake" : "Core glow is resting"
    }

    private var readinessValue: String {
        if signalState.memoryReady && signalState.toolActionReady {
            return "Ready"
        }
        if signalState.memoryReady || signalState.toolActionReady {
            return "Partial"
        }
        return "Waiting"
    }

    private var readinessDetail: String {
        if !signalState.memoryReady {
            return "Select or create a thread"
        }
        if !signalState.toolActionReady {
            return "Action review in progress"
        }
        return "Context and actions available"
    }

    private var contextDetail: String {
        if signalState.contextPercent == 0 {
            return "Light context"
        }
        if signalState.contextPercent < 70 {
            return "Within the working range"
        }
        return "Approaching the context limit"
    }
}
