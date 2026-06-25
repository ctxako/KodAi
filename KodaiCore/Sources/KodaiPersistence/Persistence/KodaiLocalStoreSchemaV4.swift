import SwiftData

/// Local-only schema: chat sessions, messages, summaries, streams, and telemetry.
/// KodaiProject and KodaiTask were removed from this schema in V4 and are now
/// isolated in a separate workspace store (KodaiWorkspace.store).
public enum KodaiLocalStoreSchemaV4: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
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
