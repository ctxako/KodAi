import Testing
import Foundation
import KodaiKernel
@testable import kodai_consumer

private final class ScriptedModel: AgentModel {
    private let outputs: [String]
    private(set) var calls = 0
    private(set) var lastMessages: [AgentMessage] = []

    init(_ outputs: [String]) { self.outputs = outputs }

    func complete(systemPrompt: String, messages: [AgentMessage]) async throws -> String {
        lastMessages = messages
        let output = calls < outputs.count ? outputs[calls] : "All done."
        calls += 1
        return output
    }
}

private struct OKRouter: ToolRouter {
    func execute(_ call: AssistantToolCall) async -> ToolResult {
        .ok(tool: call.toolName, result: ["created": "true"])
    }
}

private struct FailingRouter: ToolRouter {
    let failOn: String
    func execute(_ call: AssistantToolCall) async -> ToolResult {
        if call.toolName == failOn {
            return .failure(tool: call.toolName, error: "permission_denied")
        }
        return .ok(tool: call.toolName, result: ["created": "true"])
    }
}

private let reminderCall = #"<|tool_call_start|>[{"name":"reminders_create","arguments":{"title":"Call mom"}}]<|tool_call_end|>"#
private let addMilkCall = #"[{"name":"reminders_create","arguments":{"title":"Milk","list_name":"Groceries"}}]"#
private let calendarListCall = #"[{"name":"calendar_list_events","arguments":{"start_date":"2026-06-26T00:00","end_date":"2026-06-26T23:59"}}]"#
private let respondCall = #"[respond(message="I can help with calendars and reminders!")]"#

struct AgentLoopTests {

    // MARK: - Single tool

    @Test func singleStepThenTerminal() async throws {
        let model = ScriptedModel([reminderCall, "Done — reminder set."])
        let loop = AgentLoop(model: model, router: OKRouter())
        let outcome = try await loop.run(task: "remind me to call mom")
        #expect(outcome == .completed(summary: "Done — reminder set.", steps: ["reminders_create: Call mom → ok"]))
        #expect(model.calls == 2)
    }

    // MARK: - Chained tools

    @Test func chainedToolsRunEachStep() async throws {
        let model = ScriptedModel([calendarListCall, reminderCall, "Done — checked calendar and set reminder."])
        let loop = AgentLoop(model: model, router: OKRouter())
        let outcome = try await loop.run(task: "check my calendar for tomorrow and create a reminder to prep")
        guard case let .completed(_, steps) = outcome else {
            Issue.record("expected completed")
            return
        }
        #expect(steps.count == 2)
        #expect(steps[0].contains("calendar_list_events"))
        #expect(steps[1].contains("reminders_create"))
    }

    // MARK: - Mid-chain failure

    @Test func midChainFailureContinues() async throws {
        let model = ScriptedModel([calendarListCall, reminderCall, "Partial success."])
        let router = FailingRouter(failOn: "calendar_list_events")
        let loop = AgentLoop(model: model, router: router)
        let outcome = try await loop.run(task: "check calendar then remind me")
        guard case let .completed(_, steps) = outcome else {
            Issue.record("expected completed")
            return
        }
        #expect(steps.count == 2)
        #expect(steps[0].contains("calendar_list_events") && steps[0].contains("error"))
        #expect(steps[1].contains("reminders_create") && steps[1].contains("ok"))
    }

    // MARK: - Multi-step

    @Test func multiStepTaskRunsEachStep() async throws {
        let model = ScriptedModel([addMilkCall, addMilkCall, "Added both items."])
        let loop = AgentLoop(model: model, router: OKRouter())
        let outcome = try await loop.run(task: "add milk to groceries twice")
        guard case let .completed(_, steps) = outcome else {
            #expect(Bool(false), "expected completed")
            return
        }
        #expect(steps.count == 2)
    }

    // MARK: - Budget exceeded

    @Test @MainActor func enforcesStepBudget() async throws {
        let model = ScriptedModel(Array(repeating: addMilkCall, count: 10))
        var loop = AgentLoop(model: model, router: OKRouter())
        loop.maxSteps = 3
        let outcome = try await loop.run(task: "never terminate")
        guard case let .budgetExceeded(steps) = outcome else {
            #expect(Bool(false), "expected budgetExceeded")
            return
        }
        #expect(steps.count == 3)
        #expect(model.calls == 3)
    }

    @Test func defaultBudgetIsSix() async throws {
        let model = ScriptedModel(Array(repeating: addMilkCall, count: 10))
        let loop = AgentLoop(model: model, router: OKRouter())
        let outcome = try await loop.run(task: "keep going forever")
        guard case let .budgetExceeded(steps) = outcome else {
            #expect(Bool(false), "expected budgetExceeded at default budget")
            return
        }
        #expect(steps.count == 6)
        #expect(model.calls == 6)
    }

    // MARK: - Invalid call + retry

    @Test func retriesOnceThenRecovers() async throws {
        let invalid = #"[{"name":"reminders_create","arguments":{"notes":"no title here"}}]"#
        let model = ScriptedModel([invalid, reminderCall, "Done."])
        let loop = AgentLoop(model: model, router: OKRouter())
        let outcome = try await loop.run(task: "remind me to call mom")
        guard case let .completed(_, steps) = outcome else {
            #expect(Bool(false), "expected completed")
            return
        }
        #expect(steps == ["reminders_create: Call mom → ok"])
        #expect(model.calls == 3)
    }

    @Test func recordsErrorStepWhenRetryAlsoInvalid() async throws {
        let invalid = #"[{"name":"reminders_create","arguments":{"notes":"still no title"}}]"#
        let model = ScriptedModel([invalid, invalid, "Giving up."])
        let loop = AgentLoop(model: model, router: OKRouter())
        let outcome = try await loop.run(task: "remind me")
        guard case let .completed(_, steps) = outcome else {
            #expect(Bool(false), "expected completed")
            return
        }
        #expect(steps == ["reminders_create → error"])
    }

    // MARK: - Respond tool

    @Test func respondToolTerminatesLoopWithMessage() async throws {
        let model = ScriptedModel([respondCall])
        let loop = AgentLoop(model: model, router: OKRouter())
        let outcome = try await loop.run(task: "what can you do?")
        guard case let .responded(message, steps) = outcome else {
            Issue.record("expected responded for respond tool")
            return
        }
        #expect(steps.isEmpty)
        #expect(message == "I can help with calendars and reminders!")
        #expect(model.calls == 1)
    }

    @Test func respondTerminatesChainAfterSteps() async throws {
        let model = ScriptedModel([calendarListCall, respondCall])
        let loop = AgentLoop(model: model, router: OKRouter())
        let outcome = try await loop.run(task: "what's on my calendar tomorrow?")
        guard case let .responded(message, steps) = outcome else {
            Issue.record("expected responded terminal after a step")
            return
        }
        #expect(steps.count == 1)
        #expect(steps[0].contains("calendar_list_events"))
        #expect(!message.isEmpty)
    }

    // MARK: - Step hooks (live card logging)

    @Test @MainActor func onStepFiresPerExecutedStep() async throws {
        let model = ScriptedModel([calendarListCall, reminderCall, respondCall])
        var loop = AgentLoop(model: model, router: OKRouter())
        var stepEvents: [(String, ToolResult.Status)] = []
        var startEvents: [String] = []
        loop.onToolStart = { call, _ in startEvents.append(call.toolName) }
        loop.onStep = { call, result in stepEvents.append((call.toolName, result.status)) }

        let outcome = try await loop.run(task: "check calendar then remind me")

        guard case let .responded(_, steps) = outcome else {
            Issue.record("expected responded terminal")
            return
        }
        #expect(steps.count == 2)
        #expect(startEvents == ["calendar_list_events", "reminders_create"])
        #expect(stepEvents.count == 2)
        #expect(stepEvents.allSatisfy { $0.1 == .ok })
    }

    // MARK: - User cancel mid-chain

    @Test @MainActor func userCancelMidChainStopsChainKeepsCompletedSteps() async throws {
        final class CancelSecondRouter: ToolRouter {
            var calls = 0
            func execute(_ call: AssistantToolCall) async -> ToolResult {
                calls += 1
                if calls >= 2 { return .failure(tool: call.toolName, error: "cancelled_by_user") }
                return .ok(tool: call.toolName, result: ["created": "true"])
            }
        }
        let model = ScriptedModel([reminderCall, reminderCall, "unreachable"])
        var loop = AgentLoop(model: model, router: CancelSecondRouter())
        var stepEvents: [ToolResult.Status] = []
        loop.onStep = { _, result in stepEvents.append(result.status) }

        let outcome = try await loop.run(task: "set two reminders")

        guard case let .cancelled(steps) = outcome else {
            Issue.record("expected cancelled outcome")
            return
        }
        #expect(steps.count == 2)
        #expect(steps[0].contains("ok"))
        #expect(steps[1].contains("error"))
        #expect(stepEvents == [.ok, .error])
        #expect(model.calls == 2)
    }

    // MARK: - State anchor injection

    @Test func injectsStateAnchorEachTurn() async throws {
        let model = ScriptedModel([reminderCall, "Done."])
        let loop = AgentLoop(model: model, router: OKRouter())
        _ = try await loop.run(task: "remind me to call mom")

        let stateMessage = model.lastMessages.last
        #expect(stateMessage?.role == .user)
        #expect(stateMessage?.text.contains("[TASK STATE]") == true)
        #expect(stateMessage?.text.contains("original_task") == true)
        #expect(stateMessage?.text.contains("reminders_create: Call mom") == true)
    }

    // MARK: - Plain text terminates immediately

    @Test func plainTextTerminatesImmediately() async throws {
        let model = ScriptedModel(["I don't understand your request."])
        let loop = AgentLoop(model: model, router: OKRouter())
        let outcome = try await loop.run(task: "something vague")
        guard case let .completed(summary, steps) = outcome else {
            Issue.record("expected completed")
            return
        }
        #expect(summary == "I don't understand your request.")
        #expect(steps.isEmpty)
        #expect(model.calls == 1)
    }
}
