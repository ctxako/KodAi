import Foundation
import KodaiKernel
import SwiftData

@Model
public final class Summary {
    public var id: UUID
    public var kind: SummaryKind
    public var content: String
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
        tokenCount: Int? = nil,
        rangeStart: Date? = nil,
        rangeEnd: Date? = nil,
        createdAt: Date = .now,
        session: KodaiChatSession? = nil,
        project: KodaiProject? = nil
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.tokenCount = tokenCount ?? TokenEstimator.estimate(content)
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.createdAt = createdAt
        self.session = session
        self.project = project
    }
}
