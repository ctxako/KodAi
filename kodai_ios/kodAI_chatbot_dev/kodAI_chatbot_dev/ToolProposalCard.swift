import KodaiKernel
import SwiftUI

struct ToolProposalCard: View {
    let proposal: PendingToolProposalLite
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatPalette.accentBlue)
                Text(proposal.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }

            if let createTask = proposal.createTask {
                VStack(alignment: .leading, spacing: 4) {
                    Text(createTask.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(3)

                    if let details = createTask.details, !details.isEmpty {
                        Text(details)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    }

                    HStack(spacing: 12) {
                        if let projectTitle = createTask.projectTitle {
                            Label(projectTitle, systemImage: "folder")
                        }
                        if let dueDate = createTask.dueDate {
                            Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        }
                        if createTask.priority != .normal {
                            Label(createTask.priority.rawValue.capitalized, systemImage: "flag")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                }
            }

            HStack(spacing: 10) {
                Button(role: .cancel, action: onCancel) {
                    Text("Cancel")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                Button(action: onConfirm) {
                    Text("Confirm")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(ChatPalette.accentBlue)
            }
        }
        .padding(14)
        .liquidGlassPanel(tint: ChatPalette.elevatedSurface, cornerRadius: 18)
    }
}
