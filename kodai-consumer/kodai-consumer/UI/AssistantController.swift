import Foundation
import KodaiKernel
import Observation

struct PendingConfirmation: Identifiable {
    let id = UUID()
    let call: AssistantToolCall
    let confidence: ParseConfidence
    let resolve: (ConfirmDecision) -> Void
}

struct PendingFilePicker: Identifiable {
    let id = UUID()
    let request: FilePickerRequest
    let resolve: (FilePickerResult) -> Void
}

enum AssistantPhase: Equatable, Hashable {
    case idle
    case loading
    case thinking
    case callingTool(name: String)
    case confirming
    case done
    case failed
    case responded
}

@Observable
final class AssistantController {
    var input: String = ""
    var currentTask: String = ""
    var thinking: String = ""
    var phase: AssistantPhase = .loading
    var summary: String?
    var isRunning = false
    var pendingConfirmation: PendingConfirmation?
    var pendingFilePicker: PendingFilePicker?
    var isModelReady = false

    private let model = RuntimeAgentModel()
    private var runTask: Task<Void, Never>?

    var isResolving: Bool {
        isRunning || pendingConfirmation != nil
    }

    @MainActor
    func dismissOutcome() {
        guard !isRunning else { return }
        summary = nil
        phase = .idle
        thinking = ""
        currentTask = ""
    }

    func prewarm() {
        Task {
            await model.inference.prewarm { [weak self] status in
                guard let self else { return }
                switch status {
                case .ready:
                    self.phase = .idle
                    self.isModelReady = true
                default:
                    self.phase = .loading
                }
            }
            if phase != .idle {
                phase = .idle
                isModelReady = true
            }
        }
    }

    func handleDeepLink(query: String) {
        input = query
        start()
    }

    func start() {
        guard !isRunning else { return }
        runTask = Task { await self.run() }
    }

    func cancel() {
        guard isRunning else { return }
        runTask?.cancel()
        runTask = nil
        Task { await model.cancel() }
        summary = nil
        thinking = ""
        currentTask = ""
        phase = .idle
        isRunning = false
    }

    func run() async {
        let task = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty, !isRunning else { return }

        input = ""
        currentTask = task
        thinking = ""
        summary = nil
        phase = .loading
        isRunning = true
        defer { runTask = nil }

        model.onStatus = { [weak self] status in
            guard let self else { return }
            switch status {
            case .downloading, .loading: self.phase = .loading
            case .thinking:
                self.phase = .thinking
                self.thinking = ""
            }
        }
        model.onToken = { [weak self] chunk in self?.thinking += chunk }

        let system = SystemPromptBuilder().build()

        guard let raw = await emit(system: system, messages: [AgentMessage(.user, task)]) else {
            if Task.isCancelled { return }
            HapticFeedback.error()
            return finish("That took too long — try again.", .failed)
        }
        if Task.isCancelled { return }

        let parser = ToolCallParser()
        guard let (rawCall, confidence) = parser.parse(raw) else {
            HapticFeedback.error()
            return finish("I can only set reminders, calendar events, save files, and manage lists right now.", .failed)
        }

        if rawCall.name == AssistantToolCatalog.respondToolName {
            let reply = rawCall.arguments["message"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = reply?.isEmpty == false ? reply! : Self.capabilitiesMessage
            return finish(message, .responded)
        }

        var currentConfidence = confidence
        var validation = ToolCallValidator().validate(rawCall, userInput: task)
        if case let .failure(error) = validation {
            currentConfidence = .json
            guard let retry = await emit(system: system, messages: [
                AgentMessage(.user, task),
                AgentMessage(.assistant, raw),
                AgentMessage(.user, "That tool call was invalid (\(error)). Re-emit one corrected tool call.")
            ]) else {
                if Task.isCancelled { return }
                HapticFeedback.error()
                return finish("That took too long — try again.", .failed)
            }
            if Task.isCancelled { return }
            if let (retried, retryConf) = parser.parse(retry) {
                validation = ToolCallValidator().validate(retried, userInput: task)
                currentConfidence = retryConf
            }
        }
        guard case let .success(call) = validation else {
            HapticFeedback.error()
            return finish("I couldn't build a valid action from that.", .failed)
        }

        phase = .callingTool(name: Self.kind(of: call))

        let result: ToolResult
        if EventKitToolRouter.isQuery(call) {
            result = await executeQueryTool(call)
        } else if Self.isFileTool(call) {
            result = await executeFileTool(call, confidence: currentConfidence)
        } else {
            result = await executeEventKitTool(call, confidence: currentConfidence)
        }

        handleResult(result, call: call)
        thinking = ""
        isRunning = false
    }

    // MARK: - Tool dispatch

    private func executeEventKitTool(_ call: AssistantToolCall, confidence: ParseConfidence) async -> ToolResult {
        let router = EventKitToolRouter(
            confirm: { [weak self] candidate in
                await self?.confirmWithConfidence(candidate, confidence: confidence) ?? .cancel
            },
            onActivity: { _ in }
        )
        return await router.execute(call)
    }

    private func executeQueryTool(_ call: AssistantToolCall) async -> ToolResult {
        let router = EventKitToolRouter(
            confirm: { _ in .cancel },
            onActivity: { _ in }
        )
        return await router.execute(call)
    }

    private func executeFileTool(_ call: AssistantToolCall, confidence: ParseConfidence) async -> ToolResult {
        let decision = await confirmWithConfidence(call, confidence: confidence)
        guard case let .accept(confirmed) = decision else {
            return .failure(tool: EventKitToolRouter.name(call), error: "cancelled_by_user")
        }
        let router = FileToolRouter(
            presentPicker: { [weak self] request in
                await self?.presentFilePicker(request) ?? .cancelled
            }
        )
        return await router.execute(confirmed)
    }

    private static func isFileTool(_ call: AssistantToolCall) -> Bool {
        switch call {
        case .saveFile, .readFile: return true
        default: return false
        }
    }

    // MARK: - App Intents hand-off

    @MainActor
    func drainPendingIntentActions() {
        guard !isRunning else { return }
        let calls = IntentActionInbox.shared.drain()
        guard !calls.isEmpty else { return }
        Task { @MainActor in
            for call in calls { await runDirectToolCall(call) }
        }
    }

    @MainActor
    func runDirectToolCall(_ call: AssistantToolCall) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        currentTask = "\(Self.kind(of: call).capitalized) (Shortcut)"
        summary = nil
        phase = .loading

        let result: ToolResult
        if Self.isFileTool(call) {
            result = await executeFileTool(call, confidence: .json)
        } else {
            result = await executeEventKitTool(call, confidence: .json)
        }
        handleResult(result, call: call)
    }

    // MARK: - Result handling

    private func handleResult(_ result: ToolResult, call: AssistantToolCall) {
        if EventKitToolRouter.isQuery(call) {
            if result.status == .ok {
                summary = result.fields["summary"] ?? "No results."
                phase = .responded
                HapticFeedback.success()
            } else {
                summary = "Couldn't check — \(Self.reason(result.fields["error"]))."
                phase = .failed
                HapticFeedback.error()
            }
            return
        }

        switch result.status {
        case .ok:
            summary = Self.successLine(for: call, result: result)
            phase = .done
            HapticFeedback.success()
        case .error where result.fields["error"] == "cancelled_by_user":
            summary = nil
            phase = .idle
            HapticFeedback.cancel()
        case .error:
            summary = "Couldn't complete — \(Self.reason(result.fields["error"]))."
            phase = .failed
            HapticFeedback.error()
        }
    }

    // MARK: - Watchdog

    private static let turnTimeout: UInt64 = 45

    private func emit(system: String, messages: [AgentMessage]) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                (try? await self.model.complete(systemPrompt: system, messages: messages)) ?? ""
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.turnTimeout * 1_000_000_000)
                return nil
            }
            defer { group.cancelAll() }
            let outcome = await group.next() ?? ""
            if outcome == nil { await self.model.cancel() }
            return outcome
        }
    }

    // MARK: - Confirm + file picker

    private func confirmWithConfidence(_ call: AssistantToolCall, confidence: ParseConfidence) async -> ConfirmDecision {
        phase = .confirming
        HapticFeedback.cardAppear()
        return await withCheckedContinuation { continuation in
            pendingConfirmation = PendingConfirmation(call: call, confidence: confidence) { [weak self] decision in
                self?.pendingConfirmation = nil
                continuation.resume(returning: decision)
            }
        }
    }

    private func presentFilePicker(_ request: FilePickerRequest) async -> FilePickerResult {
        phase = .loading
        return await withCheckedContinuation { continuation in
            pendingFilePicker = PendingFilePicker(request: request) { [weak self] result in
                self?.pendingFilePicker = nil
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Helpers

    private func finish(_ message: String, _ phase: AssistantPhase) {
        summary = message
        self.phase = phase
        thinking = ""
        isRunning = false
    }

    static let capabilitiesMessage = "I can set reminders, add calendar events, manage lists, save or read files, and check your calendar or reminders — what would you like to do?"

    static func kind(of call: AssistantToolCall) -> String {
        switch call {
        case .createCalendarEvent: return "event"
        case .createReminder: return "reminder"
        case .addToList: return "list item"
        case .saveFile: return "file"
        case .readFile: return "file read"
        case .queryCalendar: return "calendar check"
        case .queryReminders: return "reminders check"
        }
    }

    static func successLine(for call: AssistantToolCall, result: ToolResult? = nil) -> String {
        switch call {
        case let .createReminder(title, due, _, _):
            if let due { return "Reminder set — \(title), \(format(due))" }
            return "Reminder set — \(title)"
        case let .createCalendarEvent(title, start, _, _, _):
            return "Event added — \(title), \(format(start))"
        case let .addToList(list, item):
            return "Added to \(list) — \(item)"
        case let .saveFile(name, _):
            return "File saved — \(name)"
        case .readFile:
            let name = result?.fields["name"] ?? "file"
            return "Read — \(name)"
        case .queryCalendar:
            return result?.fields["summary"] ?? "Calendar checked."
        case .queryReminders:
            return result?.fields["summary"] ?? "Reminders checked."
        }
    }

    private static func reason(_ error: String?) -> String {
        switch error {
        case "calendar_access_denied": return "calendar access is off (Settings › Privacy › Calendars)"
        case "reminders_access_denied": return "reminders access is off (Settings › Privacy › Reminders)"
        case "no_reminder_list_available": return "no Reminders list found — open Reminders once"
        case "no_calendar_available": return "no calendar found — set a default in Settings › Calendar"
        case "access_denied": return "file access was denied"
        default: return error ?? "unknown error"
        }
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
