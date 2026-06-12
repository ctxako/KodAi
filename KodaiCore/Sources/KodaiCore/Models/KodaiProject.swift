import Foundation
import SwiftData

@Model
public final class KodaiProject {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var details: String
    public var status: ProjectStatus
    public var summary: String?
    public var summaryUpdatedAt: Date?
    public var deadline: Date?
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \KodaiChatSession.project)
    public var sessions: [KodaiChatSession]

    @Relationship(deleteRule: .cascade, inverse: \KodaiTask.project)
    public var tasks: [KodaiTask]

    public init(
        id: UUID = UUID(),
        title: String = "New project",
        details: String = "",
        status: ProjectStatus = .active,
        summary: String? = nil,
        summaryUpdatedAt: Date? = nil,
        deadline: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sessions: [KodaiChatSession] = [],
        tasks: [KodaiTask] = []
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.status = status
        self.summary = summary
        self.summaryUpdatedAt = summaryUpdatedAt
        self.deadline = deadline
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessions = sessions
        self.tasks = tasks
    }
}
