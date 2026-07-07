//
//  chatmessage.swift
//  kodai_macos
//

import Foundation

enum ChatRole: String {
    case user
    case assistant
}

struct ResponseTelemetry: Equatable {
    var phase: String
    var promptTokens: Int
    var outputTokens: Int
    var contextUsedPercent: Int
    var timeToFirstToken: Double?
    var decodeTime: Double?
    var tokensPerSecond: Double
    var totalLatency: Double
    var toolCallCount: Int = 0
    var toolTime: Double = 0
    var errorType: String?
    /// Which engine produced this turn ("Apple FM", "qwen3:8b", …) — one
    /// conversation can mix engines, so honesty lives per message.
    var engineLabel: String?

    var totalTokens: Int { promptTokens + outputTokens }

    var displayText: String {
        var parts: [String] = []
        parts.append("Context \(contextUsedPercent)%")
        if tokensPerSecond > 0 {
            parts.append("\(Int(tokensPerSecond)) tok/s")
        }
        if let ttft = timeToFirstToken {
            parts.append("\(String(format: "%.1f", ttft))s first token")
        }
        parts.append("\(String(format: "%.1f", totalLatency))s total")
        if outputTokens > 0 {
            parts.append("\(outputTokens) out")
        }
        return parts.joined(separator: " · ")
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    var text: String
    var metrics: ResponseTelemetry?
    /// Agent-loop step digests ("file_grep — 12 matches in 4 files"), shown
    /// as chips above the answer so multi-step work is visible, not hidden.
    var agentSteps: [String] = []

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        metrics: ResponseTelemetry? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.metrics = metrics
    }
}
