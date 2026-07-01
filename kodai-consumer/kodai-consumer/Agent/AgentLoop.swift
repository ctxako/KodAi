//
//  AgentLoop.swift
//  kodai-consumer
//
//  The agentic loop: infer → parse → validate → execute → feed result back,
//  repeating until the model terminates or the step budget is hit. The state
//  anchor is re-injected every turn; invalid calls get one silent retry before
//  being recorded as an error step.
//
//  The primer forces every model turn to open a tool call, so the terminal
//  turn of a chain is a `respond` call — intercepted at the raw layer (it is
//  not an executable `AssistantToolCall`). A user declining a confirm card
//  ends the chain: feeding "cancelled_by_user" back to the model would just
//  make it retry the write the user said no to.
//
//  `AgentModel` and `ToolRouter` are protocols so the loop is fully testable
//  with mocks. `onToolStart`/`onStep` let the UI show live progress and log
//  one action card per completed step.
//

import Foundation
import KodaiKernel

/// One conversation message as seen by the loop. `.tool` carries a structured
/// `ToolResult` JSON line back to the model.
struct AgentMessage: Equatable, Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
        case tool
    }

    let role: Role
    let text: String

    init(_ role: Role, _ text: String) {
        self.role = role
        self.text = text
    }
}

/// Produces the assistant's raw text for one model turn.
protocol AgentModel {
    func complete(systemPrompt: String, messages: [AgentMessage]) async throws -> String
}

/// Executes a validated call (confirming writes in the real implementation)
/// and returns a structured result.
protocol ToolRouter {
    func execute(_ call: AssistantToolCall) async -> ToolResult
}

enum AgentOutcome: Equatable, Sendable {
    /// Model terminated with a `respond` call — the normal primed terminal.
    /// `message` may be empty (the UI substitutes its own copy).
    case responded(message: String, steps: [String])
    /// Model emitted text that parsed as no tool call. With the primer this is
    /// the garble path — the UI must not show `summary` verbatim to the user.
    case completed(summary: String, steps: [String])
    /// User declined a confirm card mid-chain; completed steps stand.
    case cancelled(steps: [String])
    /// Hit `maxSteps` without terminating — surfaced to the user, never looped on.
    case budgetExceeded(steps: [String])

    var steps: [String] {
        switch self {
        case let .responded(_, steps), let .completed(_, steps),
             let .cancelled(steps), let .budgetExceeded(steps):
            return steps
        }
    }
}

struct AgentLoop {
    let model: any AgentModel
    let router: any ToolRouter
    var parser = ToolCallParser()
    var validator = ToolCallValidator()
    var promptBuilder = SystemPromptBuilder()
    var maxSteps = 6
    /// Fires after a call validates, before it executes. Carries the parse
    /// confidence so a confirm card can show a verify nudge on shaky calls.
    var onToolStart: ((AssistantToolCall, ParseConfidence) -> Void)?
    /// Fires after each executed step with its structured result — the hook
    /// the UI uses to log one action card per step, live.
    var onStep: ((AssistantToolCall, ToolResult) -> Void)?
    /// Live progress hook (retry, error). Defaulted off so headless tests are
    /// unaffected.
    var onActivity: ((String) -> Void)?

    func run(task: String) async throws -> AgentOutcome {
        let system = promptBuilder.build()
        var state = StateAnchor(originalTask: task)
        var messages: [AgentMessage] = [AgentMessage(.user, task)]
        var step = 0
        var retriedThisStep = false

        while step < maxSteps {
            let turnMessages = messages + [AgentMessage(.user, "[TASK STATE]\n" + state.asContextJSON())]
            let output = try await model.complete(systemPrompt: system, messages: turnMessages)
            try Task.checkCancellation()
            messages.append(AgentMessage(.assistant, output))

            guard let (raw, confidence) = parser.parse(output) else {
                let summary = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return .completed(summary: summary, steps: state.stepsCompleted)
            }

            if raw.name == ConsumerToolRouting.respondToolName {
                let message = raw.arguments["message"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return .responded(message: message, steps: state.stepsCompleted)
            }

            switch validator.validate(raw, userInput: task) {
            case .failure(let error):
                if !retriedThisStep {
                    retriedThisStep = true
                    onActivity?("Re-trying an invalid tool call…")
                    messages.append(AgentMessage(.user,
                        "Your previous tool call was invalid (\(error)). Re-emit one corrected tool call as JSON."))
                    continue
                }
                let result = ToolResult.failure(tool: raw.name, error: "\(error)")
                messages.append(AgentMessage(.tool, result.asContextJSON()))
                state.record("\(raw.name) → error")
                onActivity?("⚠︎ \(raw.name) couldn’t be completed")
                step += 1
                retriedThisStep = false

            case .success(let call):
                // A call that needed a correction gets a verify nudge.
                let effective: ParseConfidence =
                    retriedThisStep && confidence == .native ? .json : confidence
                onToolStart?(call, effective)
                let result = await router.execute(call)
                messages.append(AgentMessage(.tool, result.asContextJSON()))
                state.record("\(Self.label(for: call)) → \(result.status.rawValue)")
                onStep?(call, result)

                if result.status == .error, result.fields["error"] == "cancelled_by_user" {
                    return .cancelled(steps: state.stepsCompleted)
                }
                try Task.checkCancellation()
                step += 1
                retriedThisStep = false
            }
        }

        return .budgetExceeded(steps: state.stepsCompleted)
    }

    static func label(for call: AssistantToolCall) -> String {
        switch call {
        case let .calendarCreateEvent(title, _, _, _, _, _, _):
            return "calendar_create_event: \(title)"
        case let .calendarListEvents(start, _, _):
            return "calendar_list_events: \(start)"
        case let .calendarDeleteEvent(eventId):
            return "calendar_delete_event: \(eventId)"
        case let .remindersCreate(title, _, _, _, _):
            return "reminders_create: \(title)"
        case let .remindersList(list, _):
            return "reminders_list: \(list ?? "all")"
        case let .remindersComplete(reminderId):
            return "reminders_complete: \(reminderId)"
        case let .contactsSearch(query):
            return "contacts_search: \(query)"
        case let .contactsCreate(firstName, _, _, _, _, _):
            return "contacts_create: \(firstName)"
        case let .filesList(path):
            return "files_list: \(path)"
        case let .filesRead(path):
            return "files_read: \(path)"
        case let .filesCreate(path, _):
            return "files_create: \(path)"
        case let .filesCreateFolder(path):
            return "files_create_folder: \(path)"
        case let .filesDelete(path):
            return "files_delete: \(path)"
        case .clipboardRead:
            return "clipboard_read"
        case let .clipboardWrite(content):
            let preview = content.count > 20 ? String(content.prefix(20)) + "…" : content
            return "clipboard_write: \(preview)"
        case let .notificationSchedule(title, _, _, _):
            return "notification_schedule: \(title)"
        case let .notificationCancel(identifier):
            return "notification_cancel: \(identifier)"
        case let .webFetch(url):
            return "web_fetch: \(url)"
        case let .openUrl(url):
            return "open_url: \(url)"
        }
    }
}
