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
    var isRunning = false
    var pendingConfirmation: PendingConfirmation?
    var pendingFilePicker: PendingFilePicker?
    var isModelReady = false

    var store: ActionStore?
    private var activeSessionID: UUID?

    private let model = RuntimeAgentModel()
    private var runTask: Task<Void, Never>?

    var isResolving: Bool {
        isRunning || pendingConfirmation != nil
    }

    @MainActor
    func dismissOutcome() {
        guard !isRunning else { return }
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
        phase = .loading
        isRunning = true
        defer { runTask = nil }

        if let prev = activeSessionID {
            store?.archiveSession(id: prev)
        }

        let sessionID = store?.startSession(prompt: task) ?? UUID()
        activeSessionID = sessionID
        store?.logPrompt(text: task, sessionID: sessionID)

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

        // Per-step state the loop hooks feed; confirm cards read the latest
        // parse confidence (execution is strictly sequential, so it's current).
        var latestConfidence: ParseConfidence = .native
        var lastCall: AssistantToolCall?
        var lastResult: ToolResult?
        var successCount = 0

        let dispatch = ToolRouterDispatch(
            confirm: { [weak self] candidate in
                await self?.confirmWithConfidence(candidate, confidence: latestConfidence) ?? .cancel
            },
            presentFilePicker: { [weak self] request in
                await self?.presentFilePicker(request) ?? .cancelled
            }
        )

        var loop = AgentLoop(
            model: WatchdogAgentModel(base: model, timeout: DeviceTier.current.turnTimeoutSeconds),
            router: dispatch
        )
        loop.maxSteps = DeviceTier.current.maxAgentSteps
        loop.onToolStart = { [weak self] call, confidence in
            latestConfidence = confidence
            self?.phase = .callingTool(name: Self.kind(of: call))
        }
        loop.onStep = { [weak self] call, result in
            guard let self else { return }
            lastCall = call
            lastResult = result
            if result.status == .ok { successCount += 1 }
            self.logToolResult(result, call: call, sessionID: sessionID)
            self.thinking = ""
            if result.status == .ok { HapticFeedback.cardAppear() }
        }

        do {
            let outcome = try await loop.run(task: task)
            conclude(outcome, lastCall: lastCall, lastResult: lastResult,
                     successCount: successCount, sessionID: sessionID)
        } catch is CancellationError {
            // cancel() already reset the UI; completed step cards stand.
            store?.endSession(id: sessionID)
        } catch is AgentTurnTimeout {
            HapticFeedback.error()
            store?.logNote(text: "That took too long — try again.", sessionID: sessionID)
            store?.endSession(id: sessionID)
            finish(.failed)
        } catch is AgentThermalCritical {
            HapticFeedback.error()
            store?.logNote(
                text: "Your phone is running hot — give it a minute to cool down, then try again.",
                sessionID: sessionID
            )
            store?.endSession(id: sessionID)
            finish(.failed)
        } catch {
            HapticFeedback.error()
            store?.logNote(text: "Something went wrong with the model — try again.", sessionID: sessionID)
            store?.endSession(id: sessionID)
            finish(.failed)
        }
    }

    /// Maps a loop outcome to the terminal phase, note card, and haptic.
    private func conclude(
        _ outcome: AgentOutcome,
        lastCall: AssistantToolCall?,
        lastResult: ToolResult?,
        successCount: Int,
        sessionID: UUID
    ) {
        let terminal: AssistantPhase
        switch outcome {
        case let .responded(message, steps):
            store?.logNote(text: message.isEmpty ? Self.capabilitiesMessage : message, sessionID: sessionID)
            terminal = steps.isEmpty
                ? .responded
                : Self.terminalPhase(lastCall: lastCall, lastResult: lastResult)

        case let .completed(_, steps):
            // With the primer this is the garble path — never surface raw output.
            if steps.isEmpty {
                store?.logNote(text: "I didn’t understand that — try rephrasing.", sessionID: sessionID)
                terminal = .failed
            } else {
                terminal = Self.terminalPhase(lastCall: lastCall, lastResult: lastResult)
            }

        case .cancelled:
            terminal = .idle

        case let .budgetExceeded(steps):
            store?.logNote(
                text: "That was getting long — I stopped after \(steps.count) steps.",
                sessionID: sessionID
            )
            terminal = successCount > 0 ? .done : .failed
        }

        switch terminal {
        case .done, .responded: HapticFeedback.success()
        case .failed: HapticFeedback.error()
        case .idle: HapticFeedback.cancel()
        default: break
        }

        store?.endSession(id: sessionID)
        finish(terminal)
    }

    private static func terminalPhase(lastCall: AssistantToolCall?, lastResult: ToolResult?) -> AssistantPhase {
        guard let lastResult, lastResult.status == .ok else { return .failed }
        if let lastCall, isReadOnly(lastCall) { return .responded }
        return .done
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

        let label = "\(Self.kind(of: call).capitalized) (Shortcut)"
        currentTask = label
        phase = .loading

        if let prev = activeSessionID {
            store?.archiveSession(id: prev)
        }

        let sessionID = store?.startSession(prompt: label) ?? UUID()
        activeSessionID = sessionID

        let dispatch = ToolRouterDispatch(
            confirm: { [weak self] candidate in
                await self?.confirmWithConfidence(candidate, confidence: .json) ?? .cancel
            },
            presentFilePicker: { [weak self] request in
                await self?.presentFilePicker(request) ?? .cancelled
            }
        )
        let result = await dispatch.execute(call)
        logToolResult(result, call: call, sessionID: sessionID)
        handleResult(result, call: call)
        store?.endSession(id: sessionID)
    }

    // MARK: - Result handling

    private static func isReadOnly(_ call: AssistantToolCall) -> Bool {
        switch call {
        case .calendarListEvents, .remindersList, .contactsSearch,
             .filesList, .filesRead, .clipboardRead, .webFetch:
            return true
        default:
            return false
        }
    }

    private func handleResult(_ result: ToolResult, call: AssistantToolCall) {
        if Self.isReadOnly(call) {
            if result.status == .ok {
                phase = .responded
                HapticFeedback.success()
            } else {
                phase = .failed
                HapticFeedback.error()
            }
            return
        }

        switch result.status {
        case .ok:
            phase = .done
            HapticFeedback.success()
        case .error where result.fields["error"] == "cancelled_by_user":
            phase = .idle
            HapticFeedback.cancel()
        case .error:
            phase = .failed
            HapticFeedback.error()
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

    // MARK: - Store logging

    private func logToolResult(_ result: ToolResult, call: AssistantToolCall, sessionID: UUID) {
        let toolName = call.toolName
        let domain = ActionStore.domain(for: toolName)
        let status = result.status == .ok ? "done" : (result.fields["error"] == "cancelled_by_user" ? "cancelled" : "failed")
        let summaryText = result.status == .ok
            ? Self.successLine(for: call, result: result)
            : "Failed — \(Self.reason(result.fields["error"]))"
        store?.logAction(
            toolName: toolName,
            domain: domain,
            summary: summaryText,
            status: status,
            details: result.fields,
            sessionID: sessionID,
            relatedDate: Self.relatedDate(for: call)
        )
    }

    private static func relatedDate(for call: AssistantToolCall) -> Date? {
        switch call {
        case let .calendarCreateEvent(_, start, _, _, _, _, _): return start
        case let .remindersCreate(_, due, _, _, _): return due
        case let .notificationSchedule(_, _, trigger, _): return trigger
        default: return nil
        }
    }

    // MARK: - Helpers

    private func finish(_ phase: AssistantPhase) {
        self.phase = phase
        thinking = ""
        isRunning = false
    }

    static let capabilitiesMessage = "I can manage calendar events, reminders, contacts, files, clipboard, notifications, and open URLs — what would you like to do?"

    static func kind(of call: AssistantToolCall) -> String {
        switch call {
        case .calendarCreateEvent: return "event"
        case .calendarListEvents: return "calendar check"
        case .calendarDeleteEvent: return "event delete"
        case .remindersCreate: return "reminder"
        case .remindersList: return "reminders check"
        case .remindersComplete: return "reminder complete"
        case .contactsSearch: return "contact search"
        case .contactsCreate: return "contact"
        case .filesList: return "file list"
        case .filesRead: return "file read"
        case .filesCreate: return "file"
        case .filesCreateFolder: return "folder"
        case .filesDelete: return "file delete"
        case .clipboardRead: return "clipboard read"
        case .clipboardWrite: return "clipboard write"
        case .notificationSchedule: return "notification"
        case .notificationCancel: return "notification cancel"
        case .webFetch: return "web fetch"
        case .openUrl: return "open url"
        }
    }

    static func successLine(for call: AssistantToolCall, result: ToolResult? = nil) -> String {
        switch call {
        case let .calendarCreateEvent(title, start, _, _, _, _, _):
            return "Event added — \(title), \(format(start))"
        case .calendarListEvents:
            return result?.fields["summary"] ?? "Calendar checked."
        case .calendarDeleteEvent:
            return "Event deleted."
        case let .remindersCreate(title, due, _, _, _):
            if let due { return "Reminder set — \(title), \(format(due))" }
            return "Reminder set — \(title)"
        case .remindersList:
            return result?.fields["summary"] ?? "Reminders checked."
        case .remindersComplete:
            return "Reminder completed."
        case let .contactsSearch(query):
            return result?.fields["summary"] ?? "Searched contacts for \(query)."
        case let .contactsCreate(firstName, _, _, _, _, _):
            return "Contact created — \(firstName)."
        case .filesList:
            return result?.fields["summary"] ?? "Files listed."
        case .filesRead:
            let name = result?.fields["name"] ?? "file"
            return "Read — \(name)"
        case let .filesCreate(path, _):
            return "File saved — \(path)"
        case let .filesCreateFolder(path):
            return "Folder created — \(path)"
        case .filesDelete:
            return "File deleted."
        case .clipboardRead:
            return "Clipboard read."
        case let .clipboardWrite(content):
            let preview = content.count > 40 ? String(content.prefix(40)) + "…" : content
            return "Copied — \(preview)"
        case let .notificationSchedule(title, _, _, _):
            return "Notification scheduled — \(title)"
        case .notificationCancel:
            return "Notification cancelled."
        case .webFetch:
            return result?.fields["summary"] ?? "Content fetched."
        case let .openUrl(url):
            return "Opened — \(url)"
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
