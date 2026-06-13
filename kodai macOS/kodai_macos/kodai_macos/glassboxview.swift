//
//  glassboxview.swift
//  kodai_macos
//

import SwiftUI

struct GlassBoxView: View {
    @Environment(\.kodaiTheme) private var theme

    let signalState: LiveEntitySignalState
    let onClose: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 34) {
                        liveEntity
                        signalGrid
                    }

                    VStack(spacing: 20) {
                        liveEntity
                        signalGrid
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Text("The bloom reflects local activity, context, tasks, project focus, and tool readiness.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(34)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("glassBox.detail")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Glass Box")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.primaryText)

                Text("Local model visibility")
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
                isActive: signalState.isActive,
                activityLevel: signalState.activityLevel
            )
            .scaleEffect(2.05)
            .frame(width: 250, height: 250)

            HStack(spacing: 7) {
                Circle()
                    .fill(theme.primaryAccent.opacity(signalState.isActive ? 0.9 : 0.55))
                    .frame(width: 7, height: 7)

                Text(signalState.status.rawValue)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityIdentifier("glassBox.status")
            }
        }
        .padding(24)
        .frame(width: 300, height: 340)
        .kodaiGlass(cornerRadius: 22)
    }

    private var signalGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            signalCard(
                title: "Model activity",
                value: signalState.status.rawValue,
                detail: modelActivityDetail,
                isActivityCard: true
            )
            signalCard(
                title: "Context load",
                value: "\(signalState.contextPercent)%",
                detail: contextDetail
            )
            signalCard(
                title: "Tasks due",
                value: "\(signalState.tasksDueCount)",
                detail: signalState.tasksDueCount == 1 ? "One task needs attention" : "Due today or overdue"
            )
            signalCard(
                title: "Selected project",
                value: signalState.selectedProjectName ?? "None",
                detail: signalState.selectedProjectName == nil ? "No project focus" : "Current thread focus"
            )
            signalCard(
                title: "Memory + context",
                value: signalState.memoryReady ? "Ready" : "Waiting",
                detail: signalState.memoryReady ? "Thread context available" : "Select or create a thread"
            )
            signalCard(
                title: "Tools + actions",
                value: signalState.toolActionReady ? "Ready" : "Review needed",
                detail: signalState.toolActionReady ? "Available when requested" : "Action awaiting confirmation"
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

    private var modelActivityDetail: String {
        switch signalState.status {
        case .idle:
            return "Model is standing by"
        case .thinking:
            return "Preparing the local response"
        case .responding:
            return "Streaming the local response"
        }
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
