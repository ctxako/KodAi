import Foundation
import SwiftData

@Model
public final class KodaiSummary {
    @Attribute(.unique) public var id: UUID
    public var kind: SummaryKind
    public var content: String
    public var previousContent: String?
    public var tokenCount: Int
    public var createdAt: Date
    public var session: KodaiChatSession?
    public var project: KodaiProject?

    public init(
        id: UUID = UUID(),
        kind: SummaryKind,
        content: String,
        previousContent: String? = nil,
        createdAt: Date = .now,
        session: KodaiChatSession? = nil,
        project: KodaiProject? = nil
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.previousContent = previousContent
        self.tokenCount = max(1, Int(ceil(Double(content.count) / 4.0)))
        self.createdAt = createdAt
        self.session = session
        self.project = project
    }
}
