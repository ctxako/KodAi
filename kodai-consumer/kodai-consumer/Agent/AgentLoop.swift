//
//  AgentLoop.swift
//  kodai-consumer
//
//  The agentic loop: infer → parse → validate → execute → feed result back,
//  repeating until the model emits a terminal (non-tool-call) response or the
//  step budget is hit. The state anchor is re-injected every turn; invalid
//  calls get one silent retry before being recorded as an error step.
//
//  `AgentModel` and `ToolRouter` are protocols so the loop is fully testable
//  with mocks. Phase 3 supplies the real EventKit-backed router + a runtime
//  adapter that collects streamed tokens into one turn.
//

import Foundation

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
    /// Model finished with a plain-language response. `steps` is what it did.
    case completed(summary: String, steps: [String])
    /// Hit `maxSteps` without terminating — surfaced to the user, never looped on.
    case budgetExceeded(steps: [String])
}

struct AgentLoop {
    let model: any AgentModel
    let router: any ToolRouter
    var parser = ToolCallParser()
    var validator = ToolCallValidator()
    var promptBuilder = SystemPromptBuilder()
    var maxSteps = 6
    /// Live progress hook (step completed, retry, error). Defaulted off so
    /// headless tests are unaffected.
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
            messages.append(AgentMessage(.assistant, output))

            guard let (raw, _) = parser.parse(output) else {
                let summary = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return .completed(summary: summary, steps: state.stepsCompleted)
            }

            switch validator.validate(raw) {
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
                let result = await router.execute(call)
                messages.append(AgentMessage(.tool, result.asContextJSON()))
                state.record("\(Self.label(for: call)) → \(result.status.rawValue)")
                onActivity?("✓ \(Self.label(for: call))")
                step += 1
                retriedThisStep = false
            }
        }

        return .budgetExceeded(steps: state.stepsCompleted)
    }

    static func label(for call: AssistantToolCall) -> String {
        switch call {
        case let .createCalendarEvent(title, _, _, _, _):
            return "create_calendar_event: \(title)"
        case let .createReminder(title, _, _, _):
            return "create_reminder: \(title)"
        case let .addToList(list, item):
            return "add_to_list: \(item) → \(list)"
        case let .saveFile(name, _):
            return "save_file: \(name)"
        case let .readFile(purpose):
            return "read_file: \(purpose)"
        }
    }
}
