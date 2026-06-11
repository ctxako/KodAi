import Foundation
import SwiftData
import Observation

/// Single write path for all TurnRecord and ActivityEvent creation.
/// Nothing else in the app should insert these models directly.
@MainActor
@Observable
public final class LedgerRecorder {

    public init() {}

    /// Record one complete assistant turn, building the ModelPerformanceMetric inline.
    /// Returns the inserted TurnRecord so callers can attach further relationships.
    @discardableResult
    public func recordTurn(
        userText: String,
        assistantText: String,
        systemPrompt: String,
        sessionID: UUID?,
        manifest: ContextManifest,
        backend: String,
        modelName: String,
        latencyMs: Double,
        inputTokens: Int,
        outputTokens: Int,
        contextPercent: Int,
        context: ModelContext
    ) -> TurnRecord {
        let manifestData = (try? JSONEncoder().encode(manifest)) ?? Data()

        let metric = ModelPerformanceMetric(
            inputTokenEstimate: inputTokens,
            outputTokenEstimate: outputTokens,
            latencyMs: latencyMs,
            contextPercent: contextPercent
        )
        context.insert(metric)

        let turn = TurnRecord(
            userMessage: userText,
            assistantMessage: assistantText,
            systemPrompt: systemPrompt,
            inputTokenEstimate: inputTokens,
            outputTokenEstimate: outputTokens,
            latencyMs: latencyMs,
            sessionID: sessionID,
            contextManifestJSON: manifestData,
            performanceMetric: metric
        )
        context.insert(turn)
        metric.turn = turn

        let event = ActivityEvent(kind: .turn, detail: "turn", turn: turn)
        context.insert(event)
        turn.activityEvents.append(event)

        try? context.save()
        return turn
    }

    /// Record a standalone activity event not tied to an assistant turn.
    @discardableResult
    public func recordActivity(
        kind: ActivityKind,
        summary: String,
        projectID: UUID? = nil,
        context: ModelContext
    ) -> ActivityEvent {
        let event = ActivityEvent(kind: kind, detail: summary)
        context.insert(event)
        try? context.save()
        return event
    }
}
