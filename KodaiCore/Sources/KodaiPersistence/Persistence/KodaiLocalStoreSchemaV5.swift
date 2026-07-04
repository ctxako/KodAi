import SwiftData

/// V5 adds the accountability models (KodaiCommitment, BriefingRecord).
/// Purely additive over V4 — existing entities are unchanged.
public enum KodaiLocalStoreSchemaV5: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            KodaiChatSession.self,
            KodaiChatMessage.self,
            KodaiSummary.self,
            KodaiStream.self,
            TurnRecord.self,
            ActivityEvent.self,
            ModelPerformanceMetric.self,
            ToolCall.self,
            KodaiCommitment.self,
            BriefingRecord.self
        ]
    }
}
