import Foundation
import KodaiKernel
import SwiftData

@Model
public final class KodaiChatMessage {
    public var id: UUID
    public var role: String
    public var content: String
    public var createdAt: Date
    public var session: KodaiChatSession?

    public init(
        id: UUID = UUID(),
        role: String,
        content: String,
        createdAt: Date = .now,
        session: KodaiChatSession? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.session = session
    }
}
