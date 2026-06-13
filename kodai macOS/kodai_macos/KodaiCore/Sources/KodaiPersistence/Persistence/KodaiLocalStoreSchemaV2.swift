import Foundation
import KodaiKernel
import SwiftData

/// Transitional schema: UUID references coexist with the old relationships.
public enum KodaiLocalStoreSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            KodaiProject.self,
            KodaiTask.self,
            KodaiChatSession.self,
            KodaiChatMessage.self,
            KodaiSummary.self,
            KodaiStream.self,
            TurnRecord.self,
            ActivityEvent.self,
            ModelPerformanceMetric.self,
            ToolCall.self
        ]
    }

    @Model
    public final class KodaiProject {
        public var id: UUID
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

    @Model
    public final class KodaiTask {
        public var id: UUID
        public var title: String
        public var notes: String
        public var priority: TaskPriority
        public var isCompleted: Bool
        public var completedAt: Date?
        public var dueDate: Date?
        public var createdAt: Date
        public var updatedAt: Date
        public var project: KodaiProject?

        public init(
            id: UUID = UUID(),
            title: String,
            notes: String = "",
            priority: TaskPriority = .medium,
            isCompleted: Bool = false,
            completedAt: Date? = nil,
            dueDate: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            project: KodaiProject? = nil
        ) {
            self.id = id
            self.title = title
            self.notes = notes
            self.priority = priority
            self.isCompleted = isCompleted
            self.completedAt = completedAt
            self.dueDate = dueDate
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.project = project
        }
    }

    @Model
    public final class KodaiChatSession {
        public var id: UUID
        public var title: String
        public var createdAt: Date
        public var updatedAt: Date
        public var stream: KodaiStream?
        public var project: KodaiProject?
        public var projectID: UUID?
        public var summarizedThroughMessageID: UUID?

        @Relationship(deleteRule: .cascade, inverse: \KodaiChatMessage.session)
        public var messages: [KodaiChatMessage]

        @Relationship(deleteRule: .cascade, inverse: \KodaiSummary.session)
        public var summaries: [KodaiSummary]

        public init(
            id: UUID = UUID(),
            title: String = "New chat",
            createdAt: Date = .now,
            updatedAt: Date = .now,
            stream: KodaiStream? = nil,
            project: KodaiProject? = nil,
            projectID: UUID? = nil,
            messages: [KodaiChatMessage] = [],
            summarizedThroughMessageID: UUID? = nil,
            summaries: [KodaiSummary] = []
        ) {
            self.id = id
            self.title = title
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.stream = stream
            self.project = project
            self.projectID = projectID
            self.messages = messages
            self.summarizedThroughMessageID = summarizedThroughMessageID
            self.summaries = summaries
        }
    }

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

    @Model
    public final class KodaiSummary {
        public var id: UUID
        public var kind: SummaryKind
        public var content: String
        public var previousContent: String?
        public var tokenCount: Int
        public var rangeStart: Date?
        public var rangeEnd: Date?
        public var createdAt: Date
        public var session: KodaiChatSession?
        public var project: KodaiProject?
        public var projectID: UUID?

        public init(
            id: UUID = UUID(),
            kind: SummaryKind,
            content: String,
            previousContent: String? = nil,
            rangeStart: Date? = nil,
            rangeEnd: Date? = nil,
            createdAt: Date = .now,
            session: KodaiChatSession? = nil,
            project: KodaiProject? = nil,
            projectID: UUID? = nil
        ) {
            self.id = id
            self.kind = kind
            self.content = content
            self.previousContent = previousContent
            self.tokenCount = max(1, Int(ceil(Double(content.count) / 4.0)))
            self.rangeStart = rangeStart
            self.rangeEnd = rangeEnd
            self.createdAt = createdAt
            self.session = session
            self.project = project
            self.projectID = projectID
        }
    }

    @Model
    public final class KodaiStream {
        public var id: UUID
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
}
