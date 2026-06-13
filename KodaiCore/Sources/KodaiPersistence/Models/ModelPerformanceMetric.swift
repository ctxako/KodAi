import Foundation
import KodaiKernel
import SwiftData

@Model
public final class ModelPerformanceMetric {
    public var id: UUID
    public var inputTokenEstimate: Int
    public var outputTokenEstimate: Int
    public var latencyMs: Double
    public var contextPercent: Int
    public var createdAt: Date

    public var turn: TurnRecord?

    public init(
        id: UUID = UUID(),
        inputTokenEstimate: Int,
        outputTokenEstimate: Int,
        latencyMs: Double,
        contextPercent: Int,
        createdAt: Date = .now,
        turn: TurnRecord? = nil
    ) {
        self.id = id
        self.inputTokenEstimate = inputTokenEstimate
        self.outputTokenEstimate = outputTokenEstimate
        self.latencyMs = latencyMs
        self.contextPercent = contextPercent
        self.createdAt = createdAt
        self.turn = turn
    }
}
