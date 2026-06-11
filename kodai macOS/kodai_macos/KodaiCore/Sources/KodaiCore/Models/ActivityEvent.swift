import Foundation
import SwiftData

@Model
public final class ActivityEvent {
    @Attribute(.unique) public var id: UUID
    public var kind: ActivityKind
    public var detail: String
    public var createdAt: Date

    public var turn: TurnRecord?

    public init(
        id: UUID = UUID(),
        kind: ActivityKind,
        detail: String = "",
        createdAt: Date = .now,
        turn: TurnRecord? = nil
    ) {
        self.id = id
        self.kind = kind
        self.detail = detail
        self.createdAt = createdAt
        self.turn = turn
    }
}
