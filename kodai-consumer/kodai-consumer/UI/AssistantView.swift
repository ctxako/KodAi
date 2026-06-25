import SwiftUI
import SwiftData

struct AssistantView: View {
    @State private var controller = AssistantController()
    @FocusState private var inputFocused: Bool
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        @Bindable var controller = controller

        NavigationStack {
            VStack(spacing: 10) {
                if controller.phase != .idle || !controller.isModelReady {
                    StatusHeader(phase: controller.phase, startedAt: controller.thinkingStartedAt, isModelReady: controller.isModelReady)
                        .padding(.horizontal)
                }

                activityLog

                if controller.phase == .thinking {
                    let live = controller.thinking.strippingModelTokens()
                    if !live.isEmpty {
                        ThinkingPanel(text: live)
                            .padding(.horizontal)
                    }
                }

                if let summary = controller.summary {
                    Text(summary)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }

                if !controller.rawDebug.isEmpty {
                    Text(controller.rawDebug)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

                ConsumerInputBar(
                    text: $controller.input,
                    isGenerating: controller.isRunning,
                    isInputFocused: $inputFocused,
                    isDisabled: !controller.isModelReady,
                    onSend: {
                        HapticFeedback.send()
                        controller.start()
                    },
                    onStop: { controller.cancel() }
                )
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("kodAI")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $controller.pendingConfirmation) { pending in
                ConfirmSheet(
                    call: pending.call,
                    confidence: pending.confidence,
                    onConfirm: { editedCall in
                        HapticFeedback.confirm()
                        pending.resolve(.accept(editedCall))
                    },
                    onCancel: {
                        HapticFeedback.cancel()
                        pending.resolve(.cancel)
                    }
                )
                .interactiveDismissDisabled()
            }
            .sheet(item: $controller.pendingFilePicker) { pending in
                DocumentPickerView(request: pending.request) { result in
                    pending.resolve(result)
                }
            }
            .onOpenURL { url in
                guard url.scheme == "kodai",
                      url.host == "task",
                      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "q" })?.value
                else { return }
                controller.handleDeepLink(query: query)
            }
            .task {
                controller.actionLogger = ActionLogger(
                    container: modelContext.container
                )
                controller.prewarm()
            }
        }
    }

    private var activityLog: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if controller.activity.isEmpty && controller.isModelReady {
                    Text("Ask me to set a reminder, add a calendar event, save a file, or manage a list.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
                ForEach(controller.activity) { line in
                    ActivityRow(line: line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .frame(maxHeight: .infinity)
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = false }
    }
}

// MARK: - Status header

private struct StatusHeader: View {
    let phase: AssistantPhase
    let startedAt: Date?
    let isModelReady: Bool

    var body: some View {
        HStack(spacing: 8) {
            if phase == .thinking {
                ThinkingDotsView()
            } else if phase.showsSpinner {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: phase.symbol).foregroundStyle(phase.tint)
            }

            if phase == .thinking, let startedAt {
                TimelineView(.periodic(from: startedAt, by: 1.0)) { context in
                    let elapsed = max(1, Int(context.date.timeIntervalSince(startedAt)))
                    Text("Thinking… \(elapsed)s")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(countsDown: false))
                        .animation(.easeInOut(duration: 0.4), value: elapsed)
                }
            } else if phase == .loading && !isModelReady {
                Text("Loading model…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(phase.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Thinking panel

private struct ThinkingPanel: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 120)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Activity row

private struct ActivityRow: View {
    let line: ActivityLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint)
            Text(line.text)
                .font(line.kind == .task ? .headline : .callout)
                .foregroundStyle(line.kind == .info ? .secondary : .primary)
        }
    }

    private var symbol: String {
        switch line.kind {
        case .task: return "target"
        case .info: return "ellipsis.circle"
        case .step: return "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        line.kind == .step ? .green : .secondary
    }
}

// MARK: - Phase extensions

private extension AssistantPhase {
    var label: String {
        switch self {
        case .idle: return ""
        case .downloading: return "Downloading model — one-time, ~700 MB. This takes a few minutes…"
        case .loading: return "Loading model…"
        case .thinking: return "Thinking…"
        case .confirming: return "Waiting for your confirmation…"
        case .saving: return "Saving…"
        case .pickingFile: return "Choose a file…"
        case .done: return "Done"
        case .failed: return "Something went wrong"
        }
    }

    var symbol: String {
        switch self {
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .confirming: return "hand.tap"
        case .pickingFile: return "doc.badge.ellipsis"
        default: return "circle"
        }
    }

    var tint: Color {
        switch self {
        case .done: return .green
        case .failed: return .orange
        default: return .secondary
        }
    }

    var showsSpinner: Bool {
        switch self {
        case .downloading, .loading, .thinking, .saving: return true
        default: return false
        }
    }
}

// MARK: - Confirm sheet

private struct ConfirmSheet: View {
    let call: AssistantToolCall
    let confidence: ParseConfidence
    let onConfirm: (AssistantToolCall) -> Void
    let onCancel: () -> Void

    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var editStart = Date()
    @State private var editEnd = Date()
    @State private var editHasEnd = false
    @State private var editLocation = ""
    @State private var editNotes = ""
    @State private var editList = ""
    @State private var editItem = ""
    @State private var editDue = Date()
    @State private var editHasDue = false
    @State private var editFileName = ""
    @State private var editFileContent = ""
    @State private var editPurpose = ""

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: Self.icon(for: call))
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Self.iconColor(for: call), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Confirm action")
                        .font(.headline)
                    if confidence == .pythonic {
                        Text("Double-check this looks right")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }

            if isEditing {
                editFields
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.title(for: call)).font(.title3).bold()
                    ForEach(Array(Self.details(for: call).enumerated()), id: \.offset) { _, detail in
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 12) {
                Button(role: .cancel, action: onCancel) {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if !isEditing {
                    Button { beginEditing() } label: {
                        Text("Edit").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    let final = isEditing ? buildEditedCall() : call
                    onConfirm(final)
                } label: {
                    Text("Confirm").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Edit fields

    @ViewBuilder
    private var editFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch call {
            case .createCalendarEvent:
                TextField("Title", text: $editTitle)
                    .textFieldStyle(.roundedBorder)
                DatePicker("Start", selection: $editStart)
                if editHasEnd {
                    DatePicker("End", selection: $editEnd)
                }
                TextField("Location", text: $editLocation)
                    .textFieldStyle(.roundedBorder)
                TextField("Notes", text: $editNotes)
                    .textFieldStyle(.roundedBorder)

            case .createReminder:
                TextField("Title", text: $editTitle)
                    .textFieldStyle(.roundedBorder)
                if editHasDue {
                    DatePicker("Due", selection: $editDue)
                }
                TextField("List", text: $editList)
                    .textFieldStyle(.roundedBorder)
                TextField("Notes", text: $editNotes)
                    .textFieldStyle(.roundedBorder)

            case .addToList:
                TextField("List", text: $editList)
                    .textFieldStyle(.roundedBorder)
                TextField("Item", text: $editItem)
                    .textFieldStyle(.roundedBorder)

            case .saveFile:
                TextField("File name", text: $editFileName)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $editFileContent)
                    .frame(minHeight: 80, maxHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.tertiary))

            case .readFile:
                TextField("Purpose", text: $editPurpose)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func beginEditing() {
        switch call {
        case let .createCalendarEvent(title, start, end, location, notes):
            editTitle = title
            editStart = start
            editEnd = end ?? start.addingTimeInterval(3600)
            editHasEnd = end != nil
            editLocation = location ?? ""
            editNotes = notes ?? ""
        case let .createReminder(title, due, list, notes):
            editTitle = title
            editDue = due ?? Date()
            editHasDue = due != nil
            editList = list ?? ""
            editNotes = notes ?? ""
        case let .addToList(list, item):
            editList = list
            editItem = item
        case let .saveFile(name, content):
            editFileName = name
            editFileContent = content
        case let .readFile(purpose):
            editPurpose = purpose
        }
        isEditing = true
    }

    private func buildEditedCall() -> AssistantToolCall {
        switch call {
        case .createCalendarEvent:
            return .createCalendarEvent(
                title: editTitle,
                start: editStart,
                end: editHasEnd ? editEnd : nil,
                location: editLocation.isEmpty ? nil : editLocation,
                notes: editNotes.isEmpty ? nil : editNotes
            )
        case .createReminder:
            return .createReminder(
                title: editTitle,
                due: editHasDue ? editDue : nil,
                list: editList.isEmpty ? nil : editList,
                notes: editNotes.isEmpty ? nil : editNotes
            )
        case .addToList:
            return .addToList(list: editList, item: editItem)
        case .saveFile:
            return .saveFile(name: editFileName, content: editFileContent)
        case .readFile:
            return .readFile(purpose: editPurpose)
        }
    }

    // MARK: - Display

    static func icon(for call: AssistantToolCall) -> String {
        switch call {
        case .createCalendarEvent: return "calendar.badge.plus"
        case .createReminder: return "checklist"
        case .addToList: return "list.bullet"
        case .saveFile: return "doc.text"
        case .readFile: return "doc.text.magnifyingglass"
        }
    }

    static func iconColor(for call: AssistantToolCall) -> Color {
        switch call {
        case .createCalendarEvent: return .red
        case .createReminder: return .blue
        case .addToList: return .orange
        case .saveFile: return .purple
        case .readFile: return .teal
        }
    }

    static func title(for call: AssistantToolCall) -> String {
        switch call {
        case .createCalendarEvent: return "New calendar event"
        case .createReminder: return "New reminder"
        case .addToList: return "Add to list"
        case .saveFile: return "Save file"
        case .readFile: return "Read file"
        }
    }

    static func details(for call: AssistantToolCall) -> [String] {
        switch call {
        case let .createCalendarEvent(title, start, end, location, notes):
            var lines = [title, "Starts \(format(start))"]
            if let end { lines.append("Ends \(format(end))") }
            if let location { lines.append("At \(location)") }
            if let notes { lines.append(notes) }
            return lines
        case let .createReminder(title, due, list, notes):
            var lines = [title]
            if let due { lines.append("Due \(format(due))") }
            if let list { lines.append("List: \(list)") }
            if let notes { lines.append(notes) }
            return lines
        case let .addToList(list, item):
            return [item, "List: \(list)"]
        case let .saveFile(name, content):
            let preview = content.count > 100 ? String(content.prefix(100)) + "…" : content
            return [name, preview]
        case let .readFile(purpose):
            return [purpose]
        }
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
