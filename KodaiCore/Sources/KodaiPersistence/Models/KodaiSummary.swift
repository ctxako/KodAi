import Foundation
import KodaiKernel
import SwiftData

@Model
public final class KodaiSummary {
    public var id: UUID
    public var kind: SummaryKind
    public var content: String
    public var previousContent: String?
    public var tokenCount: Int
    public var rangeStart: Date?
    public var rangeEnd: Date?
    public var createdAt: Date
    public var session: KodaiChatSession?
    public var project: KodaiProject?

    public init(
        id: UUID = UUID(),
        kind: SummaryKind,
        content: String,
        previousContent: String? = nil,
        rangeStart: Date? = nil,
        rangeEnd: Date? = nil,
        createdAt: Date = .now,
        session: KodaiChatSession? = nil,
        project: KodaiProject? = nil
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.previousContent = previousContent
        self.tokenCount = max(1, Int(ceil(Double(content.count) / 4.0)))
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.createdAt = createdAt
        self.session = session
        self.project = project
    }
}
