import Foundation
import SwiftData

@Model
public final class KodaiProject {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var notes: String
    public var status: ProjectStatus
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \KodaiChatSession.project)
    public var sessions: [KodaiChatSession]

    @Relationship(deleteRule: .cascade, inverse: \KodaiTask.project)
    public var tasks: [KodaiTask]

    @Relationship(deleteRule: .cascade, inverse: \MemoryEntry.project)
    public var memories: [MemoryEntry]

    @Relationship(deleteRule: .cascade, inverse: \Summary.project)
    public var summaries: [Summary]

    @Relationship(deleteRule: .nullify, inverse: \FileReference.project)
    public var fileReferences: [FileReference]

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        status: ProjectStatus = .active,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sessions: [KodaiChatSession] = [],
        tasks: [KodaiTask] = [],
        memories: [MemoryEntry] = [],
        summaries: [Summary] = [],
        fileReferences: [FileReference] = []
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessions = sessions
        self.tasks = tasks
        self.memories = memories
        self.summaries = summaries
        self.fileReferences = fileReferences
    }
}
