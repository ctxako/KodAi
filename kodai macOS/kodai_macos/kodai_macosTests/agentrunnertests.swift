//
//  agentrunnertests.swift
//  kodai_macosTests
//
//  Deterministic pieces of the agent loop: tool-result compaction (older
//  results shrink to digests, the newest stays verbatim, the ledger is
//  untouched by design), digest composition, the honest budget-exhausted
//  hand-back, and the Ollama tool-spec wire shape. No network, no model.
//

import Foundation
import Testing
import KodaiCore
@testable import KodAi

@MainActor
struct AgentRunnerTests {

    private func toolMessage(_ content: String) -> OllamaChatMessage {
        OllamaChatMessage(role: "tool", content: content, toolName: "file_read")
    }

    private var longPayload: String {
        "{\"tool\":\"file_read\",\"status\":\"ok\",\"result\":{\"content\":\""
            + String(repeating: "x", count: 500) + "\"}}"
    }

    // MARK: - Compaction

    @Test func compactionKeepsNewestVerbatim() {
        var messages = [
            OllamaChatMessage(role: "user", content: "find my notes"),
            toolMessage(longPayload),
            OllamaChatMessage(role: "assistant", content: "reading more"),
            toolMessage(longPayload),
        ]
        AgentRunner.compactToolResults(&messages, keepVerbatim: 1)

        #expect(messages[1].content.count < 260)
        #expect(messages[1].content.contains("compacted"))
        #expect(messages[3].content == longPayload)
        // Non-tool messages are never touched.
        #expect(messages[0].content == "find my notes")
        #expect(messages[2].content == "reading more")
    }

    @Test func compactionWithZeroKeepCompactsAll() {
        var messages = [toolMessage(longPayload), toolMessage(longPayload)]
        AgentRunner.compactToolResults(&messages, keepVerbatim: 0)
        #expect(messages.allSatisfy { $0.content.contains("compacted") })
    }

    @Test func compactionSkipsShortResults() {
        let short = "{\"tool\":\"file_glob\",\"status\":\"ok\",\"result\":{\"count\":\"3\"}}"
        var messages = [toolMessage(short), toolMessage(longPayload)]
        AgentRunner.compactToolResults(&messages, keepVerbatim: 0)
        #expect(messages[0].content == short)
    }

    // MARK: - Digests

    @Test func resultDigestPrefersCompactFacts() {
        let call = OllamaToolCall(name: "file_read", arguments: ["path": "~/life/kb/a.md"], rawArguments: [:])
        let result = ToolResult.ok(tool: "file_read", result: [
            "path": "life/kb/a.md",
            "lines": "1–80 of 80",
            "content": String(repeating: "y", count: 900),
        ])
        let digest = AgentRunner.resultDigest(call: call, result: result)
        #expect(digest.contains("life/kb/a.md"))
        #expect(digest.contains("1–80 of 80"))
        #expect(digest.count <= 110)
        #expect(!digest.contains("yyy"))
    }

    @Test func resultDigestSurfacesErrors() {
        let call = OllamaToolCall(name: "file_edit", arguments: [:], rawArguments: [:])
        let result = ToolResult.failure(tool: "file_edit", error: "oldText not found")
        let digest = AgentRunner.resultDigest(call: call, result: result)
        #expect(digest.contains("oldText not found"))
    }

    @Test func callDigestUsesPrimaryArgument() {
        let call = OllamaToolCall(name: "file_grep", arguments: ["query": "briefing"], rawArguments: [:])
        #expect(AgentRunner.callDigest(call) == "file_grep briefing")
    }

    // MARK: - Budget exhaustion

    @Test func budgetMessageIsHonest() {
        let message = AgentRunner.budgetExhaustedMessage(budget: 4, lastAssistantText: "checking kb next")
        #expect(message.contains("4 tool steps"))
        #expect(message.contains("checking kb next"))
        #expect(message.contains("continue"))
    }

    // MARK: - Wire shape

    @Test func toolSpecEncodesOllamaFunctionFormat() throws {
        let spec = OllamaToolSpec(
            name: "file_read",
            description: "Read a file",
            properties: ["path": ["type": "string", "description": "File path"]],
            required: ["path"]
        )
        let json = spec.asJSON()
        #expect(json["type"] as? String == "function")
        let function = try #require(json["function"] as? [String: Any])
        #expect(function["name"] as? String == "file_read")
        let parameters = try #require(function["parameters"] as? [String: Any])
        #expect(parameters["type"] as? String == "object")
        #expect((parameters["required"] as? [String]) == ["path"])
    }
}
