import SwiftUI
import KodaiKernel

struct AssistantView: View {
    @State private var controller = AssistantController()
    @FocusState private var inputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var controller = controller

        ZStack {
            CanvasBackground()

            VStack(spacing: 0) {
                Spacer()

                if controller.isRunning || controller.summary != nil {
                    statusArea
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
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
        }
        .animation(.smooth(duration: 0.3), value: controller.isRunning)
        .animation(.smooth(duration: 0.3), value: controller.summary != nil)
        .preferredColorScheme(.dark)
        .sheet(item: $controller.pendingConfirmation) { pending in
            SimpleConfirmView(
                call: pending.call,
                confidence: pending.confidence,
                onConfirm: {
                    HapticFeedback.confirm()
                    pending.resolve(.accept(pending.call))
                },
                onCancel: {
                    HapticFeedback.cancel()
                    pending.resolve(.cancel)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
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
        .task { controller.prewarm() }
        .onAppear {
            IntentActionInbox.shared.onDeposit = { [weak controller] in
                controller?.drainPendingIntentActions()
            }
            controller.drainPendingIntentActions()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.drainPendingIntentActions() }
        }
    }

    // MARK: - Status area

    @ViewBuilder
    private var statusArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            if controller.isRunning {
                thinkingView
            }

            if let summary = controller.summary {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: controller.phase == .done ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(controller.phase == .done ? .green : .secondary)
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture { controller.dismissOutcome() }
            }
        }
    }

    private var thinkingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ThinkingDotsView()
                Text(phaseLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let live = controller.thinking.strippingModelTokens()
            if !live.isEmpty {
                ScrollView {
                    Text(live)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary.opacity(0.7))
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .scrollIndicators(.hidden)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black, .black, .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
        }
    }

    private var phaseLabel: String {
        switch controller.phase {
        case .loading: return controller.isModelReady ? "Working…" : "Loading model…"
        case .thinking: return "Thinking…"
        case .callingTool(let name): return name.capitalized + "…"
        case .confirming: return "Waiting for confirmation…"
        default: return "Working…"
        }
    }
}

// MARK: - Simple confirm sheet

private struct SimpleConfirmView: View {
    let call: AssistantToolCall
    let confidence: ParseConfidence
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.title3.bold())
                if confidence == .low {
                    Text("Double-check this looks right")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 12) {
                Button(role: .cancel, action: onCancel) {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onConfirm) {
                    Text("Confirm").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .preferredColorScheme(.dark)
    }

    private var icon: String {
        switch call {
        case .createCalendarEvent: return "calendar.badge.plus"
        case .createReminder: return "checklist"
        case .addToList: return "list.bullet"
        case .saveFile: return "doc.text"
        case .readFile: return "doc.text.magnifyingglass"
        case .queryCalendar: return "calendar"
        case .queryReminders: return "checklist.checked"
        }
    }

    private var iconColor: Color {
        switch call {
        case .createCalendarEvent, .queryCalendar: return .red
        case .createReminder, .addToList, .queryReminders: return .blue
        case .saveFile: return .purple
        case .readFile: return .teal
        }
    }

    private var title: String {
        switch call {
        case .createCalendarEvent: return "New calendar event"
        case .createReminder: return "New reminder"
        case .addToList: return "Add to list"
        case .saveFile: return "Save file"
        case .readFile: return "Read file"
        case .queryCalendar: return "Check calendar"
        case .queryReminders: return "Check reminders"
        }
    }

    private var details: [String] {
        switch call {
        case let .createCalendarEvent(t, start, end, location, notes):
            var lines = [t, "Starts \(format(start))"]
            if let end { lines.append("Ends \(format(end))") }
            if let location { lines.append("At \(location)") }
            if let notes { lines.append(notes) }
            return lines
        case let .createReminder(t, due, list, notes):
            var lines = [t]
            if let due { lines.append("Due \(format(due))") }
            if let list { lines.append("List: \(list)") }
            if let notes { lines.append(notes) }
            return lines
        case let .addToList(list, item): return [item, "List: \(list)"]
        case let .saveFile(name, content):
            let preview = content.count > 80 ? String(content.prefix(80)) + "…" : content
            return [name, preview]
        case let .readFile(purpose): return [purpose]
        case let .queryCalendar(range): return ["Checking \(range)"]
        case let .queryReminders(list, status):
            var lines = [status ?? "pending"]
            if let list { lines.append("List: \(list)") }
            return lines
        }
    }

    private func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
