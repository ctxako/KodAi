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
