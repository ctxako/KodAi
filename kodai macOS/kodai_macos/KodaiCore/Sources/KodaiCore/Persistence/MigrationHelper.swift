import Foundation

// Plain-struct representations of the old macOS app models,
// used as input to the migration — no dependency on the app target.

public struct LegacyChatMessage: Sendable {
    public var id: UUID
    public var role: String
    public var content: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        role: String,
        content: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public struct LegacyChatSession: Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var messages: [LegacyChatMessage]

    public init(
        id: UUID = UUID(),
        title: String = "New chat",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        messages: [LegacyChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

public enum MigrationHelper {
    /// Converts a legacy session into the canonical KodaiChatSession.
    /// The result is a loose chat (project == nil) with default persona and format.
    public static func migrate(_ legacy: LegacyChatSession) -> KodaiChatSession {
        let session = KodaiChatSession(
            id: legacy.id,
            title: legacy.title,
            persona: .default_,
            format: .chat,
            createdAt: legacy.createdAt,
            updatedAt: legacy.updatedAt
        )
        session.messages = legacy.messages.map { migrate($0) }
        return session
    }

    public static func migrate(_ legacy: LegacyChatMessage) -> KodaiChatMessage {
        KodaiChatMessage(
            id: legacy.id,
            role: ChatRole(rawValue: legacy.role) ?? .user,
            content: legacy.content,
            createdAt: legacy.createdAt
        )
    }
}
