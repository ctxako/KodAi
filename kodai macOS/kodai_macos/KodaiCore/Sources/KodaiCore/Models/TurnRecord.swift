import Foundation
import SwiftData

/// The glass-box contract: one record per assistant turn capturing the full context
/// used to produce the response, plus performance and tool-use metadata.
@Model
public final class TurnRecord {
    @Attribute(.unique) public var id: UUID
    public var userMessage: String
    public var assistantMessage: String
    public var systemPrompt: String
    public var persona: PersonaMode
    public var format: OutputFormat
    public var inputTokenEstimate: Int
    public var outputTokenEstimate: Int
    public var latencyMs: Double
    public var createdAt: Date

    public var session: KodaiChatSession?

    @Relationship(deleteRule: .cascade, inverse: \ToolCall.turn)
    public var toolCalls: [ToolCall]

    @Relationship(deleteRule: .cascade, inverse: \ActivityEvent.turn)
    public var activityEvents: [ActivityEvent]

    @Relationship(deleteRule: .cascade, inverse: \ModelPerformanceMetric.turn)
    public var performanceMetric: ModelPerformanceMetric?

    public init(
        id: UUID = UUID(),
        userMessage: String,
        assistantMessage: String,
        systemPrompt: String,
        persona: PersonaMode = .default_,
        format: OutputFormat = .chat,
        inputTokenEstimate: Int? = nil,
        outputTokenEstimate: Int? = nil,
        latencyMs: Double = 0,
        createdAt: Date = .now,
        session: KodaiChatSession? = nil,
        toolCalls: [ToolCall] = [],
        activityEvents: [ActivityEvent] = [],
        performanceMetric: ModelPerformanceMetric? = nil
    ) {
        self.id = id
        self.userMessage = userMessage
        self.assistantMessage = assistantMessage
        self.systemPrompt = systemPrompt
        self.persona = persona
        self.format = format
        self.inputTokenEstimate = inputTokenEstimate ?? TokenEstimator.estimate(userMessage + systemPrompt)
        self.outputTokenEstimate = outputTokenEstimate ?? TokenEstimator.estimate(assistantMessage)
        self.latencyMs = latencyMs
        self.createdAt = createdAt
        self.session = session
        self.toolCalls = toolCalls
        self.activityEvents = activityEvents
        self.performanceMetric = performanceMetric
    }
}
