import Foundation
import KodaiKernel
import SwiftData

public enum KodaiLocalStoreSchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

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

    /// Frozen copies of the workspace models as they existed when V3 shipped.
    /// Do not replace these with the current CloudKit-compatible model classes:
    /// doing so changes the V3 model hash and makes existing stores unrecognizable.
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
}

public enum KodaiLocalStoreMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [
            KodaiLocalStoreSchemaV1.self,
            KodaiLocalStoreSchemaV2.self,
            KodaiLocalStoreSchemaV3.self,
            KodaiLocalStoreSchemaV4.self
        ]
    }

    public static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: KodaiLocalStoreSchemaV1.self,
                toVersion: KodaiLocalStoreSchemaV2.self
            ),
            .custom(
                fromVersion: KodaiLocalStoreSchemaV2.self,
                toVersion: KodaiLocalStoreSchemaV3.self,
                willMigrate: { context in
                    let sessions = try context.fetch(
                        FetchDescriptor<KodaiLocalStoreSchemaV2.KodaiChatSession>()
                    )
                    for session in sessions {
                        session.projectID = session.project?.id
                    }

                    let summaries = try context.fetch(
                        FetchDescriptor<KodaiLocalStoreSchemaV2.KodaiSummary>()
                    )
                    for summary in summaries {
                        summary.projectID = summary.project?.id
                    }

                    try context.save()
                },
                didMigrate: nil
            ),
            // V4 removes KodaiProject and KodaiTask from the local store.
            // Those types are now isolated in the workspace store (KodaiWorkspace.store).
            .lightweight(
                fromVersion: KodaiLocalStoreSchemaV3.self,
                toVersion: KodaiLocalStoreSchemaV4.self
            )
        ]
    }
}
