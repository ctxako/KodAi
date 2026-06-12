import Foundation
import KodaiKernel
import SwiftData

@Model
public final class KodaiStream {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \KodaiChatSession.stream)
    public var sessions: [KodaiChatSession]

    public init(
        id: UUID = UUID(),
        title: String = "New stream",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sessions: [KodaiChatSession] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessions = sessions
    }
}
