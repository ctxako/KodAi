import Foundation
import KodaiKernel
import SwiftData

// K2E: schema after the workspace/chat split. KodaiProject no longer has a
// sessions relationship; KodaiChatSession and KodaiSummary reference projects
// by scalar projectID.
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
}

/// Migration for the macOS full local store (chat + workspace + ledger in one
/// container). Custom stage: lightweight migration would silently drop the
/// session→project relationship data, so the link map is captured before the
/// schema changes and re-applied to the scalar projectID fields afterwards.
public enum KodaiLocalStoreMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [KodaiLocalStoreSchemaV0.self, KodaiLocalStoreSchemaV1.self, KodaiLocalStoreSchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        [migrateV0toV1, migrateV1toV2]
    }

    // V0 → V1 only drops the .unique constraints K2B removed from
    // KodaiProject.id and KodaiTask.id.
    static let migrateV0toV1 = MigrationStage.lightweight(
        fromVersion: KodaiLocalStoreSchemaV0.self,
        toVersion: KodaiLocalStoreSchemaV1.self
    )

    // Carried between willMigrate (V1 context) and didMigrate (V2 context).
    // Migration runs once, single-threaded, before the container is handed out.
    nonisolated(unsafe) private static var sessionProjectLinks: [UUID: UUID] = [:]
    nonisolated(unsafe) private static var summaryProjectLinks: [UUID: UUID] = [:]

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: KodaiLocalStoreSchemaV1.self,
        toVersion: KodaiLocalStoreSchemaV2.self,
        willMigrate: { context in
            sessionProjectLinks = [:]
            summaryProjectLinks = [:]
            let sessions = try context.fetch(
                FetchDescriptor<KodaiLocalStoreSchemaV1.KodaiChatSession>()
            )
            for session in sessions {
                if let projectID = session.project?.id {
                    sessionProjectLinks[session.id] = projectID
                }
            }
            let summaries = try context.fetch(
                FetchDescriptor<KodaiLocalStoreSchemaV1.KodaiSummary>()
            )
            for summary in summaries {
                if let projectID = summary.project?.id {
                    summaryProjectLinks[summary.id] = projectID
                }
            }
        },
        didMigrate: { context in
            if !sessionProjectLinks.isEmpty {
                let sessions = try context.fetch(FetchDescriptor<KodaiChatSession>())
                for session in sessions {
                    if let projectID = sessionProjectLinks[session.id] {
                        session.projectID = projectID
                    }
                }
            }
            if !summaryProjectLinks.isEmpty {
                let summaries = try context.fetch(FetchDescriptor<KodaiSummary>())
                for summary in summaries {
                    if let projectID = summaryProjectLinks[summary.id] {
                        summary.projectID = projectID
                    }
                }
            }
            try context.save()
            sessionProjectLinks = [:]
            summaryProjectLinks = [:]
        }
    )
}
