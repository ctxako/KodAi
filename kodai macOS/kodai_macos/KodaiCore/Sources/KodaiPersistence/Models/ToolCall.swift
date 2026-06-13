import Foundation
import KodaiKernel
import SwiftData

@Model
public final class ToolCall {
    public var id: UUID
    public var toolName: String
    public var input: String
    public var output: String?
    public var outcome: ToolOutcome
    public var invoker: ToolInvoker
    public var latencyMs: Double
    public var createdAt: Date

    public var turn: TurnRecord?

    public init(
        id: UUID = UUID(),
        toolName: String,
        input: String,
        output: String? = nil,
        outcome: ToolOutcome = .success,
        invoker: ToolInvoker = .model,
        latencyMs: Double = 0,
        createdAt: Date = .now,
        turn: TurnRecord? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.input = input
        self.output = output
        self.outcome = outcome
        self.invoker = invoker
        self.latencyMs = latencyMs
        self.createdAt = createdAt
        self.turn = turn
    }
}
