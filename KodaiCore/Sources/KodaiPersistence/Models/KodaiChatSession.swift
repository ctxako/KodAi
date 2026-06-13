import Foundation
import KodaiKernel
import SwiftData

@Model
public final class KodaiChatSession {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var stream: KodaiStream?
    public var project: KodaiProject?
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
        project: KodaiProject? = nil,
        messages: [KodaiChatMessage] = [],
        summarizedThroughMessageID: UUID? = nil,
        summaries: [KodaiSummary] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.stream = stream
        self.project = project
        self.messages = messages
        self.summarizedThroughMessageID = summarizedThroughMessageID
        self.summaries = summaries
    }
}
