import KodaiKernel
import SwiftUI
import UIKit

struct SummaryEditor: Identifiable {
    enum Target {
        case chat(ChatSession.ID)
        case stream(Stream.ID)
    }

    let id = UUID()
    let title: String
    let summary: String
    let updateTitle: String?
    let target: Target
}

struct SummaryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialSummary: String
    let isUpdating: Bool
    let onUpdate: (() -> Void)?
    let updateTitle: String?
    let onSave: (String) -> Void

    @State private var summary: String

    init(
        title: String,
        initialSummary: String,
        isUpdating: Bool,
        onUpdate: (() -> Void)?,
        updateTitle: String?,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.initialSummary = initialSummary
        self.isUpdating = isUpdating
        self.onUpdate = onUpdate
        self.updateTitle = updateTitle
        self.onSave = onSave
        _summary = State(initialValue: initialSummary)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                VStack(alignment: .leading, spacing: 14) {
                    TextEditor(text: $summary)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(summary.isEmpty ? Color.secondary : Color.white)
                        .padding(12)
                        .frame(minHeight: 220)
                        .overlay(alignment: .topLeading) {
                            if summary.isEmpty {
                                Text("No summary yet.")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 20)
                                    .allowsHitTesting(false)
                            }
                        }
                        .liquidGlassPanel(tint: ChatPalette.inputField, cornerRadius: 16)

                    if let onUpdate, let updateTitle {
                        Button {
                            onUpdate()
                        } label: {
                            HStack {
                                if isUpdating {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }

                                Text(updateTitle)
                            }
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .liquidGlassPanel(tint: ChatPalette.elevatedSurface, cornerRadius: 14)
                        }
                        .buttonStyle(.plain)
                        .disabled(isUpdating)
                    }
                }
                .padding(18)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(summary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

struct SummaryCompactionSheet: View {
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var summary: String

    init(
        initialSummary: String,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (String) -> Void
    ) {
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _summary = State(initialValue: initialSummary)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                TextEditor(text: $summary)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(summary.isEmpty ? Color.secondary : Color.white)
                    .padding(12)
                    .frame(minHeight: 260)
                    .overlay(alignment: .topLeading) {
                        if summary.isEmpty {
                            Text("No summary yet.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                    }
                    .liquidGlassPanel(tint: ChatPalette.inputField, cornerRadius: 16)
                    .padding(18)
            }
            .navigationTitle("Confirm Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        onConfirm(summary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

struct ProjectDeadlineSheet: View {
    let initialDeadline: Date?
    let onSave: (Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var deadline = Date()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                    .datePickerStyle(.graphical)

                if initialDeadline != nil {
                    Button("Clear Deadline", role: .destructive) {
                        onSave(nil)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Project Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(Calendar.current.startOfDay(for: deadline))
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let initialDeadline {
                    deadline = initialDeadline
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ExportChatSheet: View {
    let snapshot: ChatExportSnapshot
    let onCancel: () -> Void

    @State private var title: String
    @State private var description = ""
    @State private var includeComments = true
    @State private var errorMessage: String?
    @State private var shareItem: ExportShareItem?

    private let log = AppLog(category: "Export")

    init(snapshot: ChatExportSnapshot, onCancel: @escaping () -> Void) {
        self.snapshot = snapshot
        self.onCancel = onCancel
        _title = State(initialValue: Self.defaultTitle(for: snapshot))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Export Chat")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)

                    TextField("Title", text: $title)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .liquidGlassPanel(tint: ChatPalette.inputField, cornerRadius: 14)

                    TextEditor(text: $description)
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 110)
                        .liquidGlassPanel(tint: ChatPalette.inputField, cornerRadius: 14)
                        .overlay(alignment: .topLeading) {
                            if description.isEmpty {
                                Text("Description")
                                    .foregroundStyle(.white.opacity(0.42))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }

                    Text("Chat Contents")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Toggle("Include comments", isOn: $includeComments)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .tint(ChatPalette.accentBlue)

                    chatPreview

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack(spacing: 10) {
                        Button("Cancel") {
                            onCancel()
                        }
                        .buttonStyle(.bordered)
                        .tint(.white.opacity(0.72))

                        Spacer()

                        Button("Save/Export") {
                            saveAndShare()
                        }
                        .buttonStyle(.glassProminent)
                        .tint(ChatPalette.accentBlue)
                    }
                }
                .padding(18)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $shareItem) { item in
                ActivityView(activityItems: [item.fileURL])
            }
        }
    }

    private var chatPreview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if snapshot.messages.isEmpty {
                    Text("No messages yet.")
                        .foregroundStyle(.white.opacity(0.62))
                } else {
                    ForEach(snapshot.messages) { message in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(message.role.previewTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.68))

                            Text(message.text.isEmpty ? " " : message.text)
                                .font(.callout)
                                .foregroundStyle(.white)
                                .textSelection(.enabled)

                            if includeComments,
                               let exportComment = message.exportComment,
                               !exportComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("// Comment: \(exportComment)")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.68))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(minHeight: 160, maxHeight: 260)
        .liquidGlassPanel(tint: ChatPalette.assistantBubble, cornerRadius: 14)
    }

    private func saveAndShare() {
        do {
            let result = try ChatExportService.export(
                title: title,
                description: description,
                snapshot: snapshot,
                includeComments: includeComments
            )
            _ = result.markdown
            log.event("share sheet presented")
            shareItem = ExportShareItem(fileURL: result.fileURL)
            errorMessage = nil
        } catch {
            errorMessage = "Export failed. Please try again."
            log.event("export failed error=\(error.localizedDescription)")
        }
    }

    private static func defaultTitle(for snapshot: ChatExportSnapshot) -> String {
        guard let chatTitle = snapshot.chatTitle,
              !chatTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              chatTitle != "New Chat" else {
            return "Exported Chat"
        }

        return chatTitle
    }
}

private struct ExportShareItem: Identifiable {
    let id = UUID()
    let fileURL: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension ChatRole {
    var previewTitle: String {
        switch self {
        case .user:
            return "User"
        case .assistant:
            return "Assistant"
        case .system:
            return "System"
        }
    }
}
