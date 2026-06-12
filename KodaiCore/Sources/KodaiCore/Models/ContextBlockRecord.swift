import Foundation

public enum ContextBlockStatus: String, Codable, CaseIterable, Sendable {
    case included
    case truncated
    case excluded
}

public struct ContextBlockRecord: Codable, Sendable {
    public var kind: String
    public var sourceID: UUID?
    public var tokenEstimate: Int
    public var status: ContextBlockStatus
    public var reason: String?

    public init(
        kind: String,
        sourceID: UUID? = nil,
        tokenEstimate: Int,
        status: ContextBlockStatus,
        reason: String? = nil
    ) {
        self.kind = kind
        self.sourceID = sourceID
        self.tokenEstimate = tokenEstimate
        self.status = status
        self.reason = reason
    }
}
