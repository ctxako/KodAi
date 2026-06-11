import Foundation
import SwiftData

@Model
public final class KodaiChatSession {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var persona: PersonaMode
    public var format: OutputFormat
    public var createdAt: Date
    public var updatedAt: Date

    public var project: KodaiProject?

    @Relationship(deleteRule: .cascade, inverse: \KodaiChatMessage.session)
    public var messages: [KodaiChatMessage]

    @Relationship(deleteRule: .nullify, inverse: \Summary.session)
    public var summaries: [Summary]

    @Relationship(deleteRule: .nullify, inverse: \MemoryEntry.session)
    public var sessionMemories: [MemoryEntry]

    @Relationship(deleteRule: .nullify, inverse: \FileReference.session)
    public var fileReferences: [FileReference]

    public init(
        id: UUID = UUID(),
        title: String = "New chat",
        persona: PersonaMode = .default_,
        format: OutputFormat = .chat,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        project: KodaiProject? = nil,
        messages: [KodaiChatMessage] = [],
        summaries: [Summary] = [],
        sessionMemories: [MemoryEntry] = [],
        fileReferences: [FileReference] = []
    ) {
        self.id = id
        self.title = title
        self.persona = persona
        self.format = format
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.project = project
        self.messages = messages
        self.summaries = summaries
        self.sessionMemories = sessionMemories
        self.fileReferences = fileReferences
    }
}
