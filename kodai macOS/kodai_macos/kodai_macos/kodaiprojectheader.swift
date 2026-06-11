//
//  kodaiprojectheader.swift
//  kodai_macos
//

import SwiftUI
import KodaiCore

struct KodaiProjectHeader: View {
    let project: KodaiProject
    let session: KodaiChatSession?
    let isGenerating: Bool
    let onUpdateSummary: (String) -> Void
    let onGenerateSummary: () -> Void

    @State private var editingSummary = false
    @State private var summaryDraft = ""
    @FocusState private var summaryFocused: Bool

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var lastActivity: Date {
        session?.updatedAt ?? project.updatedAt
    }

    private var isSummaryStale: Bool {
        let msgs = session?.messages ?? []
        guard !msgs.isEmpty else { return false }
        guard let updatedAt = project.summaryUpdatedAt else {
            return msgs.count > 10
        }
        return msgs.filter { $0.createdAt > updatedAt }.count > 10
    }

    private var statusColor: Color {
        switch project.status {
        case .active:   return .green
        case .paused:   return .orange
        case .archived: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))

                Text(project.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                statusBadge

                Spacer()

                Text(Self.dateFormatter.string(from: lastActivity))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))

                openTasksChip
            }

            // Summary row
            HStack(alignment: .top, spacing: 6) {
                if editingSummary {
                    TextField(
                        "Summarize this project…",
                        text: $summaryDraft,
                        axis: .vertical
                    )
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($summaryFocused)
                    .onSubmit { commitSummary() }

                    Button("Save") { commitSummary() }
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .buttonStyle(.plain)
                } else {
                    Text(project.summary ?? "No summary — tap to add")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(project.summary == nil ? .white.opacity(0.3) : .white.opacity(0.65))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { beginEditingSummary() }

                    if isSummaryStale {
                        Label("stale", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.orange.opacity(0.8))
                            .labelStyle(.titleAndIcon)
                    }

                    Button {
                        onGenerateSummary()
                    } label: {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white.opacity(0.45))
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isGenerating)
                    .help("Generate project summary with AI")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.2)
        }
        .onChange(of: editingSummary) { _, editing in
            if editing { summaryFocused = true }
        }
    }

    private var statusBadge: some View {
        Text(project.status.rawValue)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var openTasksChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11))
            Text("0")
                .font(.system(size: 11, weight: .regular, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.35))
    }

    private func beginEditingSummary() {
        summaryDraft = project.summary ?? ""
        editingSummary = true
    }

    private func commitSummary() {
        onUpdateSummary(summaryDraft)
        editingSummary = false
    }
}
