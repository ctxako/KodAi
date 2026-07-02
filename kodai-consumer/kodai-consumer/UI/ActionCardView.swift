import SwiftUI
import SwiftData
import UIKit

struct ActionCardView: View {
    let card: ActionCard
    @State private var isExpanded = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: domainIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(domainColor)
                    .frame(width: 24)

                Text(card.summary)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 1)

                Spacer(minLength: 4)

                Text(card.timestamp, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                statusChip
            }

            // A permission failure is recoverable in one tap — offer the jump
            // to this app's Settings page instead of a dead-end "Failed" chip.
            if isPermissionFailure {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 8)
            }

            if isExpanded, !card.details.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(card.details.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(value)
                                .font(.callout)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            guard !card.details.isEmpty else { return }
            withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
        }
        .onAppear { HapticFeedback.cardAppear() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.summary), \(chipLabel), \(card.domain)")
        .accessibilityHint(card.details.isEmpty ? "" : (isExpanded ? "Double tap to hide details" : "Double tap to show details"))
        .accessibilityAddTraits(card.details.isEmpty ? [] : .isButton)
    }

    private var isPermissionFailure: Bool {
        card.status == "failed"
            && (card.details["error"]?.hasSuffix("_access_denied") ?? false)
    }

    private var statusChip: some View {
        Text(chipLabel)
            .font(.caption2.weight(.medium))
            .foregroundStyle(chipColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(chipColor.opacity(0.15), in: Capsule())
            .accessibilityLabel(chipLabel)
    }

    private var chipLabel: String {
        switch card.status {
        case "done": return "Done"
        case "pending": return "Pending"
        case "failed": return "Failed"
        case "cancelled": return "Cancelled"
        default: return card.status.capitalized
        }
    }

    private var chipColor: Color {
        switch card.status {
        case "done": return .green
        case "pending": return .blue
        case "failed": return .red
        case "cancelled": return .gray
        default: return .secondary
        }
    }

    private var domainIcon: String {
        if card.toolName == "files_create_folder" { return "folder.badge.plus" }
        switch card.domain {
        case "calendar": return "calendar.badge.plus"
        case "reminders": return "checklist"
        case "contacts": return "person.crop.circle"
        case "files": return "doc.text"
        case "clipboard": return "doc.on.clipboard"
        case "notifications": return "bell.badge"
        default: return "globe"
        }
    }

    private var domainColor: Color {
        switch card.domain {
        case "calendar": return .red
        case "reminders": return .blue
        case "contacts": return .green
        case "files": return .purple
        case "clipboard": return .orange
        case "notifications": return .yellow
        default: return .gray
        }
    }
}
