//
//  toolproposalconfirmationcard.swift
//  kodai_macos
//

import SwiftUI

struct ToolProposalConfirmationCard: View {
    @Environment(\.kodaiTheme) private var theme

    let proposal: PendingToolProposal
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var taskProposal: CreateTaskProposal? {
        switch proposal.kind {
        case .createTask(let p): return p
        }
    }

    var body: some View {
        if let task = taskProposal {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.badge.questionmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.primaryAccent.opacity(0.9))
                    Text("Create task?")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

                if task.dueDate != nil || task.projectName != nil || task.rationale != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        if let due = task.dueDate {
                            detailRow("calendar", formatDate(due))
                        }
                        if let project = task.projectName {
                            detailRow("folder", project)
                        }
                        if let rationale = task.rationale, !rationale.isEmpty {
                            detailRow("text.quote", rationale)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }

                    Button(action: onConfirm) {
                        Text("Create Task")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                    .background(theme.primaryAccent.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(theme.primaryAccent.opacity(0.4), lineWidth: 1)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: 560, alignment: .leading)
            .kodaiGlass(cornerRadius: 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func detailRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.7))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
