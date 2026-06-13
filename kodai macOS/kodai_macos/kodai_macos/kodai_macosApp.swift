//
//  kodai_macosApp.swift
//  kodai_macos
//
//  Created by Charles Thomas Xavier Austin III on 6/9/26.
//


import FoundationModels
import SwiftUI
import SwiftData
import KodaiCore

@main
struct kodai_macosApp: App {
    private let container: ModelContainer = {
        // Workspace store: KodaiProject and KodaiTask.
        // Isolated for eventual CloudKit sync (deferred — cloudKitDatabase: .none for now).
        let workspaceConfig = WorkspaceModelContainer.makeConfiguration()

        // Local store: chat sessions, messages, summaries, streams, and telemetry.
        // Uses the default store path (default.store) so existing chat data is preserved.
        // Migrated from V3 → V4 (V4 removes KodaiProject/KodaiTask from local schema).
        let localSchema = Schema(versionedSchema: KodaiLocalStoreSchemaV4.self)
        let localConfig = ModelConfiguration(
            schema: localSchema,
            cloudKitDatabase: .none
        )

        // The full schema is the union of workspace and local models.
        // SwiftData routes each type to the appropriate store via the configurations above.
        let fullSchema = Schema([
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
        ])

        do {
            return try ModelContainer(
                for: fullSchema,
                migrationPlan: KodaiLocalStoreMigrationPlan.self,
                configurations: [localConfig, workspaceConfig]
            )
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(.clear)
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(container)
    }
}
