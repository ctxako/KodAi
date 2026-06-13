import KodaiKernel
import SwiftUI

struct DrawerSectionHeader: View {
    let title: String
    let onCreate: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                onCreate()
            } label: {
                Image(systemName: "plus")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(ChatPalette.elevatedSurface).interactive(), in: Circle())
            .accessibilityLabel("Add \(title)")
        }
    }
}

struct DrawerEmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .drawerGlassRow(isDimmed: true)
    }
}

struct SummaryPhaseLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)

            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassPanel(tint: ChatPalette.statusSurface, cornerRadius: 14)
    }
}

struct ProjectRow: View {
    let project: KodaiProjectLite
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? ChatPalette.accentBlue.opacity(0.72) : Color.clear)
                    .frame(width: 4, height: 4)

                Image(systemName: isSelected ? "checklist.checked" : "checklist")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? ChatPalette.accentBlue.opacity(0.92) : .secondary.opacity(0.78))

                Text(project.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                if openCount > 0 {
                    Text("\(openCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ChatPalette.accentBlue.opacity(0.42), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.48))
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .drawerGlassRow(isSelected: isSelected)
    }

    private var openCount: Int {
        project.incompleteTasks.count
    }
}

struct ProjectTaskRow: View {
    let task: KodaiTaskLite
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onToggle()
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(task.isCompleted ? ChatPalette.accentBlue.opacity(0.9) : .secondary.opacity(0.62))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark task incomplete" : "Mark task complete")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline)
                    .foregroundStyle(task.isCompleted ? .secondary : Color.white)
                    .strikethrough(task.isCompleted, color: .secondary)
                    .lineLimit(2)

                if let dueDate = task.dueDate, !task.isCompleted {
                    Text(dueLabel(for: dueDate))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(dueColor(for: dueDate))
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .drawerGlassRow(isDimmed: task.isCompleted)
    }

    private func dueLabel(for dueDate: Date) -> String {
        let calendar = Calendar.current
        let formatted = dueDate.formatted(.dateTime.month(.abbreviated).day())
        if dueDate < calendar.startOfDay(for: Date()) {
            return "Overdue · \(formatted)"
        }
        if calendar.isDateInToday(dueDate) {
            return "Today"
        }
        return formatted
    }

    private func dueColor(for dueDate: Date) -> Color {
        let calendar = Calendar.current
        if dueDate < calendar.startOfDay(for: Date()) {
            return .red.opacity(0.82)
        }
        if calendar.isDateInToday(dueDate) {
            return ChatPalette.accentBlue.opacity(0.92)
        }
        return Color.secondary
    }
}

struct TodayTaskRow: View {
    let item: DueTaskItem
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.isOverdue ? "exclamationmark.circle" : "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.isOverdue ? Color.red.opacity(0.85) : ChatPalette.accentBlue.opacity(0.92))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(item.isOverdue ? "Overdue · \(item.projectTitle)" : item.projectTitle)
                        .font(.caption2)
                        .foregroundStyle(item.isOverdue ? Color.red.opacity(0.75) : .secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.48))
            }
            .frame(minHeight: 40)
        }
        .buttonStyle(.plain)
        .drawerGlassRow()
    }
}

struct StreamRow: View {
    let stream: Stream
    let chatCount: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onSelect()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isSelected ? ChatPalette.accentBlue.opacity(0.72) : Color.clear)
                        .frame(width: 4, height: 4)

                    Image(systemName: isSelected ? "folder.fill" : "folder")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? ChatPalette.accentBlue.opacity(0.92) : .secondary.opacity(0.78))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stream.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text("\(chatCount) \(chatCount == 1 ? "chat" : "chats")")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.72))
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary.opacity(0.48))
                }
                .frame(minHeight: 46)
            }
            .buttonStyle(.plain)

            Button {
                onToggleFavorite()
            } label: {
                Image(systemName: stream.isFavorite ? "star.fill" : "star")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stream.isFavorite ? ChatPalette.accentBlue.opacity(0.9) : .secondary.opacity(0.56))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(stream.isFavorite ? "Remove favorite" : "Mark favorite")
        }
        .drawerGlassRow(isSelected: isSelected)
    }
}

struct FavoriteStreamsPanel: View {
    let streams: [Stream]
    let onSelect: (Stream.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start in a Stream")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 4) {
                ForEach(streams) { stream in
                    Button {
                        onSelect(stream.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "folder")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ChatPalette.accentBlue.opacity(0.9))
                                .frame(width: 18)

                            Text(stream.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Spacer(minLength: 12)

                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary.opacity(0.52))
                        }
                        .frame(minHeight: 38)
                        .padding(.horizontal, 10)
                    }
                    .buttonStyle(.plain)
                    .liquidGlassPanel(tint: ChatPalette.inputField.opacity(0.72), cornerRadius: 12)
                }
            }
        }
        .frame(maxWidth: 280)
    }
}

struct AssistantModeSelector: View {
    @Binding var selection: AssistantMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Assistant Mode", systemImage: "brain.head.profile")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Assistant Mode", selection: $selection) {
                ForEach(AssistantMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: 280)
    }
}

struct ChatSessionRow: View {
    let session: ChatSession
    let isActive: Bool
    let isGenerating: Bool
    let onSelect: () -> Void

    var body: some View {
        rowButton
            .drawerGlassRow(isSelected: isActive, isDimmed: isEmptyDraft && !isActive)
            .opacity(isGenerating && !isActive ? 0.65 : 1)
    }

    private var rowButton: some View {
        Button {
            onSelect()
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? ChatPalette.accentBlue.opacity(0.68) : Color.clear)
                .frame(width: 4, height: 4)

            Image(systemName: isActive ? "message.fill" : "message")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? ChatPalette.accentBlue.opacity(0.92) : .secondary.opacity(0.78))

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isEmptyDraft ? Color.secondary : Color.white)
                    .lineLimit(1)

                Text(compactRelativeTimestamp(for: session.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer()

            if session.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(ChatPalette.accentBlue.opacity(0.86))
            }
        }
        .frame(minHeight: 42)
    }

    private var isEmptyDraft: Bool {
        session.title == "New Chat" && session.messages.isEmpty
    }

    private func compactRelativeTimestamp(for date: Date) -> String {
        let elapsed = max(0, Int(Date().timeIntervalSince(date)))

        if elapsed < 60 {
            return "Now"
        }

        let minutes = elapsed / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h"
        }

        return "\(hours / 24)d"
    }
}

struct MessageCommentEditor: Identifiable {
    let messageID: ChatMessage.ID
    let comment: String

    var id: ChatMessage.ID { messageID }
}

struct MessageCommentEditorSheet: View {
    let editor: MessageCommentEditor
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var comment: String

    init(
        editor: MessageCommentEditor,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.editor = editor
        self.onCancel = onCancel
        self.onSave = onSave
        _comment = State(initialValue: editor.comment)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Export Comment")
                        .font(.headline)
                        .foregroundStyle(.white)

                    TextEditor(text: $comment)
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 120)
                        .liquidGlassPanel(tint: ChatPalette.inputField, cornerRadius: 14)

                    HStack {
                        Button("Cancel") {
                            onCancel()
                        }
                        .buttonStyle(.bordered)
                        .tint(.white.opacity(0.72))

                        Spacer()

                        Button("Save") {
                            onSave(comment)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(ChatPalette.accentBlue)
                    }
                }
                .padding(18)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
