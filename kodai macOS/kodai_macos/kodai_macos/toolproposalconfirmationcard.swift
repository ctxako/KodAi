//
//  toolproposalconfirmationcard.swift
//  kodai_macos
//
//  Inline confirmation card for a tool call suspended on ConfirmBroker.
//  Approving or canceling resumes the tool with the decision.
//

import SwiftUI

struct ToolConfirmationCard: View {
    @Environment(\.kodaiTheme) private var theme

    let request: ToolConfirmationRequest
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.badge.questionmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryAccent.opacity(0.9))
                Text(request.heading)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Text(request.subject)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)

            if !request.details.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(request.details, id: \.text) { detail in
                        detailRow(detail.icon, detail.text)
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
                    Text(request.confirmLabel)
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
}
