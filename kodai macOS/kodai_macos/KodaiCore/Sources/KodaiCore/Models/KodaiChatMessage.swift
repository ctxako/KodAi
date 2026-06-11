import Foundation
import SwiftData

@Model
public final class KodaiChatMessage {
    @Attribute(.unique) public var id: UUID
    public var role: ChatRole
    public var content: String
    public var tokenEstimate: Int
    public var createdAt: Date
    // Loose reference to TurnRecord — avoids a formal relationship for the common case
    // where only the assistant message maps to a turn.
    public var turnId: UUID?

    public var session: KodaiChatSession?

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        tokenEstimate: Int? = nil,
        createdAt: Date = .now,
        turnId: UUID? = nil,
        session: KodaiChatSession? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.tokenEstimate = tokenEstimate ?? TokenEstimator.estimate(content)
        self.createdAt = createdAt
        self.turnId = turnId
        self.session = session
    }
}
