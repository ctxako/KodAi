import Foundation

public struct ContextBlock: Codable, Equatable, Sendable {
    public var kind: String
    public var content: String
    public var tokenEstimate: Int
    public var priority: Int
    public var sourceID: UUID?

    public init(
        kind: String,
        content: String,
        tokenEstimate: Int,
        priority: Int,
        sourceID: UUID? = nil
    ) {
        self.kind = kind
        self.content = content
        self.tokenEstimate = tokenEstimate
        self.priority = priority
        self.sourceID = sourceID
    }
}
