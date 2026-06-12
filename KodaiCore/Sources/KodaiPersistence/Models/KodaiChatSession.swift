import Foundation
import KodaiKernel
import SwiftData

@Model
public final class KodaiChatSession {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var stream: KodaiStream?
    // Scalar reference instead of a SwiftData relationship: keeps the chat
    // schema decoupled from the workspace schema (KodaiProject/KodaiTask) so
    // each container can register only its own models.
    public var projectID: UUID?
    public var summarizedThroughMessageID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \KodaiChatMessage.session)
    public var messages: [KodaiChatMessage]

    @Relationship(deleteRule: .cascade, inverse: \KodaiSummary.session)
    public var summaries: [KodaiSummary]

    public init(
        id: UUID = UUID(),
        title: String = "New chat",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        stream: KodaiStream? = nil,
        projectID: UUID? = nil,
        messages: [KodaiChatMessage] = [],
        summarizedThroughMessageID: UUID? = nil,
        summaries: [KodaiSummary] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.stream = stream
        self.projectID = projectID
        self.messages = messages
        self.summarizedThroughMessageID = summarizedThroughMessageID
        self.summaries = summaries
    }
}
