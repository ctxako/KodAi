//
//  ToolResult.swift
//  kodai-consumer
//
//  Deterministic, structured tool result fed back into context so the model
//  reads ground truth instead of hallucinating an outcome (hard-problem #2).
//

import Foundation

struct ToolResult: Equatable, Sendable {
    enum Status: String, Sendable {
        case ok
        case error
    }

    let tool: String
    let status: Status
    let fields: [String: String]

    static func ok(tool: String, result: [String: String]) -> ToolResult {
        ToolResult(tool: tool, status: .ok, fields: result)
    }

    static func failure(tool: String, error: String) -> ToolResult {
        ToolResult(tool: tool, status: .error, fields: ["error": error])
    }

    /// {"tool":"create_reminder","status":"ok","result":{…}}  (or "error":"…")
    func asContextJSON() -> String {
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
