import Foundation
import KodaiKernel
import Observation
import SwiftData

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

struct ActivityLine: Identifiable {
    enum Kind {
        case task
        case info
        case step
    }

    let id = UUID()
    let kind: Kind
    let text: String
}

enum AssistantPhase: Equatable {
    case idle
    case downloading
    case loading
    case thinking
    case confirming
    case saving
    case pickingFile
    case done
    case failed
}

@Observable
final class AssistantController {
    var input: String = ""
    var activity: [ActivityLine] = []
    var thinking: String = ""
    var rawDebug: String = ""
    var phase: AssistantPhase = .loading
    var summary: String?
    var isRunning = false
    var pendingConfirmation: PendingConfirmation?
    var pendingFilePicker: PendingFilePicker?
    var thinkingStartedAt: Date?
    var isModelReady = false

    private let model = RuntimeAgentModel()
    private var runTask: Task<Void, Never>?
    var actionLogger: ActionLogger?

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
        finish("Stopped.", .idle)
    }

    func run() async {
        let task = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty, !isRunning else { return }

        input = ""
        activity = [ActivityLine(kind: .task, text: task)]
        thinking = ""
        rawDebug = ""
        summary = nil
        thinkingStartedAt = nil
        phase = .loading
        isRunning = true
        defer { runTask = nil }

        model.onStatus = { [weak self] status in
            guard let self else { return }
            switch status {
            case .downloading: self.phase = .downloading
            case .loading: self.phase = .loading
            case .thinking:
                self.phase = .thinking
                self.thinking = ""
                self.thinkingStartedAt = Date()
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
        rawDebug = raw

        let parser = ToolCallParser()
        guard let (rawCall, confidence) = parser.parse(raw) else {
            HapticFeedback.error()
            return finish("I can only set reminders, calendar events, save files, and manage lists right now.", .failed)
        }

        var currentConfidence = confidence
        var validation = ToolCallValidator().validate(rawCall)
        if case let .failure(error) = validation {
            append(.info, "Adjusting the details…")
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
            rawDebug = retry
            if let (retried, retryConf) = parser.parse(retry) {
                validation = ToolCallValidator().validate(retried)
                currentConfidence = retryConf
            }
        }
        guard case let .success(call) = validation else {
            HapticFeedback.error()
            return finish("I couldn't build a valid action from that.", .failed)
        }

        append(.info, "Preparing \(Self.kind(of: call))…")

        let result: ToolResult
        if Self.isFileTool(call) {
            result = await executeFileTool(call)
        } else {
            result = await executeEventKitTool(call, confidence: currentConfidence)
        }

        await logAction(originalInput: task, call: call, result: result)

        if result.status == .error,
           result.fields["error"] != "cancelled_by_user" {
            append(.info, "Retrying…")
            let retryResult: ToolResult
            if Self.isFileTool(call) {
                retryResult = await executeFileTool(call)
            } else {
                retryResult = await executeEventKitTool(call, confidence: currentConfidence)
            }
            await logAction(originalInput: task, call: call, result: retryResult)
            handleResult(retryResult, call: call)
        } else {
            handleResult(result, call: call)
        }

        thinking = ""
        thinkingStartedAt = nil
        isRunning = false
    }

    // MARK: - Tool dispatch

    private func executeEventKitTool(_ call: AssistantToolCall, confidence: ParseConfidence) async -> ToolResult {
        let router = EventKitToolRouter(
            confirm: { [weak self] candidate in
                await self?.confirmWithConfidence(candidate, confidence: confidence) ?? .cancel
            },
            onActivity: { [weak self] line in if line.hasPrefix("Saving") { self?.phase = .saving } }
        )
        return await router.execute(call)
    }

    private func executeFileTool(_ call: AssistantToolCall) async -> ToolResult {
        let router = FileToolRouter(
            presentPicker: { [weak self] request in
                await self?.presentFilePicker(request) ?? .cancelled
            }
        )
        return await router.execute(call)
    }

    private static func isFileTool(_ call: AssistantToolCall) -> Bool {
        switch call {
        case .saveFile, .readFile: return true
        default: return false
        }
    }

    // MARK: - Result handling

    private func handleResult(_ result: ToolResult, call: AssistantToolCall) {
        switch result.status {
        case .ok:
            let line = Self.successLine(for: call, result: result)
            append(.step, line)
            summary = line
            phase = .done
            HapticFeedback.success()
        case .error where result.fields["error"] == "cancelled_by_user":
            summary = "Cancelled."
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
        phase = .pickingFile
        return await withCheckedContinuation { continuation in
            pendingFilePicker = PendingFilePicker(request: request) { [weak self] result in
                self?.pendingFilePicker = nil
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Logging

    private func logAction(originalInput: String, call: AssistantToolCall, result: ToolResult) async {
        guard let logger = actionLogger else { return }
        var params: [String: String] = [:]
        switch call {
        case let .createCalendarEvent(title, start, _, location, _):
            params = ["title": title, "start": Self.format(start)]
            if let location { params["location"] = location }
        case let .createReminder(title, due, list, _):
            params = ["title": title]
            if let due { params["due"] = Self.format(due) }
            if let list { params["list"] = list }
        case let .addToList(list, item):
            params = ["list": list, "item": item]
        case let .saveFile(name, _):
            params = ["name": name]
        case let .readFile(purpose):
            params = ["purpose": purpose]
        }
        await logger.log(
            originalInput: originalInput,
            toolName: result.tool,
            parameters: params,
            status: result.status.rawValue,
            errorMessage: result.fields["error"]
        )
    }

    // MARK: - Helpers

    private func finish(_ message: String, _ phase: AssistantPhase) {
        summary = message
        self.phase = phase
        thinking = ""
        thinkingStartedAt = nil
        isRunning = false
    }

    private func append(_ kind: ActivityLine.Kind, _ text: String) {
        activity.append(ActivityLine(kind: kind, text: text))
    }

    static func kind(of call: AssistantToolCall) -> String {
        switch call {
        case .createCalendarEvent: return "event"
        case .createReminder: return "reminder"
        case .addToList: return "list item"
        case .saveFile: return "file"
        case .readFile: return "file read"
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
        }
    }

    private static func reason(_ error: String?) -> String {
        switch error {
        case "calendar_access_denied": return "calendar access is off (Settings › Privacy › Calendars)"
        case "reminders_access_denied": return "reminders access is off (Settings › Privacy › Reminders)"
        case "no_reminder_list_available": return "no Reminders list found — open Reminders once, or turn it on in iCloud settings"
        case "access_denied": return "file access was denied"
        default: return error ?? "unknown error"
        }
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
