import Testing
import Foundation
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
        .ok(tool: Self.name(call), result: ["created": "true"])
    }

    static func name(_ call: AssistantToolCall) -> String {
        switch call {
        case .createCalendarEvent: return "create_calendar_event"
        case .createReminder: return "create_reminder"
        case .addToList: return "add_to_list"
        case .saveFile: return "save_file"
        case .readFile: return "read_file"
        }
    }
}

private let reminderCall = #"<|tool_call_start|>[{"name":"create_reminder","arguments":{"title":"Call mom"}}]<|tool_call_end|>"#
private let addMilkCall = #"[{"name":"add_to_list","arguments":{"list":"Groceries","item":"Milk"}}]"#

struct AgentLoopTests {
    @Test func singleStepThenTerminal() async throws {
        let model = ScriptedModel([reminderCall, "Done — reminder set."])
        let loop = AgentLoop(model: model, router: OKRouter())
        let outcome = try await loop.run(task: "remind me to call mom")
        #expect(outcome == .completed(summary: "Done — reminder set.", steps: ["create_reminder: Call mom → ok"]))
        #expect(model.calls == 2)
    }

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

    @Test func enforcesStepBudget() async throws {
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

    @Test func retriesOnceThenRecovers() async throws {
        let invalid = #"[{"name":"create_reminder","arguments":{"notes":"no title here"}}]"#
        let model = ScriptedModel([invalid, reminderCall, "Done."])
        let loop = AgentLoop(model: model, router: OKRouter())
        let outcome = try await loop.run(task: "remind me to call mom")
        guard case let .completed(_, steps) = outcome else {
            #expect(Bool(false), "expected completed")
            return
        }
        #expect(steps == ["create_reminder: Call mom → ok"])
        #expect(model.calls == 3)
    }

    @Test func recordsErrorStepWhenRetryAlsoInvalid() async throws {
        let invalid = #"[{"name":"create_reminder","arguments":{"notes":"still no title"}}]"#
        let model = ScriptedModel([invalid, invalid, "Giving up."])
        let loop = AgentLoop(model: model, router: OKRouter())
        let outcome = try await loop.run(task: "remind me")
        guard case let .completed(_, steps) = outcome else {
            #expect(Bool(false), "expected completed")
            return
        }
        #expect(steps == ["create_reminder → error"])
    }

    @Test func injectsStateAnchorEachTurn() async throws {
        let model = ScriptedModel([reminderCall, "Done."])
        let loop = AgentLoop(model: model, router: OKRouter())
        _ = try await loop.run(task: "remind me to call mom")

        let stateMessage = model.lastMessages.last
        #expect(stateMessage?.role == .user)
        #expect(stateMessage?.text.contains("[TASK STATE]") == true)
        #expect(stateMessage?.text.contains("original_task") == true)
        #expect(stateMessage?.text.contains("create_reminder: Call mom") == true)
    }
}
