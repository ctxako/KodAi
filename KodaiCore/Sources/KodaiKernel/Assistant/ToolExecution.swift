//
//  ToolExecution.swift
//  KodaiKernel
//
//  Shared tool-execution vocabulary: the structured result fed back into
//  model context, the user-confirmation decision for mutating calls, the
//  router protocol that executes validated calls, and the activity events
//  a backend or executor can surface while a tool chain runs. Promoted from
//  kodai-consumer so the macOS Foundation Models agent and the iOS llama.cpp
//  agent share one execution layer.
//

import Foundation

/// Deterministic, structured tool result fed back into context so the model
/// reads ground truth instead of hallucinating an outcome.
public struct ToolResult: Equatable, Sendable {
    public enum Status: String, Sendable {
        case ok
        case error
    }

    public let tool: String
    public let status: Status
    public let fields: [String: String]

    public init(tool: String, status: Status, fields: [String: String]) {
        self.tool = tool
        self.status = status
        self.fields = fields
    }

    public static func ok(tool: String, result: [String: String]) -> ToolResult {
        ToolResult(tool: tool, status: .ok, fields: result)
    }

    public static func failure(tool: String, error: String) -> ToolResult {
        ToolResult(tool: tool, status: .error, fields: ["error": error])
    }

    /// {"tool":"create_reminder","status":"ok","result":{…}}  (or "error":"…")
    public func asContextJSON() -> String {
        let payload: [String: Any]
        switch status {
        case .ok:
            payload = ["tool": tool, "status": status.rawValue, "result": fields]
        case .error:
            payload = ["tool": tool, "status": status.rawValue, "error": fields["error"] ?? "unknown"]
        }
        let data = (try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

/// The user's decision on a mutating tool call. `accept` carries the call
/// back so a confirm UI could hand back an edited version.
public enum ConfirmDecision: Sendable {
    case accept(AssistantToolCall)
    case cancel
}

/// Executes a validated call (confirming writes in real implementations)
/// and returns a structured result.
public protocol ToolRouter {
    func execute(_ call: AssistantToolCall) async -> ToolResult
}

/// One observable moment in a tool call's lifecycle, for streaming quiet
/// progress into a transcript ("Checking calendar…", "Created reminder ✓").
public struct ToolActivity: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        case started
        case awaitingConfirmation
        case executing
        case succeeded
        case failed
        case cancelled
    }

    public let tool: String
    public let phase: Phase
    public let detail: String?

    public init(tool: String, phase: Phase, detail: String? = nil) {
        self.tool = tool
        self.phase = phase
        self.detail = detail
    }
}
