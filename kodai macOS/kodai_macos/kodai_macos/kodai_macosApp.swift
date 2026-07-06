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
        let localSchema = Schema(versionedSchema: KodaiLocalStoreSchemaV5.self)

        // The full schema is the union of workspace and local models.
        // SwiftData routes each type to the appropriate store via the configurations below.
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
            ToolCall.self,
            KodaiCommitment.self,
            BriefingRecord.self
        ])

        // Unit tests run inside this app as their test host. Opening the real
        // stores here would run staged migration against the user's data on
        // every test run (and quarantine it when migration fails), and the
        // CloudKit workspace configuration taints the process-wide entity
        // metadata so the tests' own in-memory containers crash on save.
        // Give the test host a throwaway in-memory container instead.
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestSessionIdentifier"] != nil {
            do {
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                return try ModelContainer(for: fullSchema, configurations: [configuration])
            } catch {
                fatalError("Failed to create unit-test model container: \(error)")
            }
        }

        // ModelConfiguration has internal state that gets bound when added to a container.
        // Always create fresh instances — never share one config across two containers.
        func makeLocalConfig() -> ModelConfiguration {
            ModelConfiguration(schema: localSchema, cloudKitDatabase: .none)
        }

        func makeFinalContainer() throws -> ModelContainer {
            try ModelContainer(
                for: fullSchema,
                configurations: [makeLocalConfig(), WorkspaceModelContainer.makeConfiguration()]
            )
        }

#if DEBUG
        let localEntityNames = Set(localSchema.entitiesByName.keys)
        precondition(!localEntityNames.contains("KodaiProject"))
        precondition(!localEntityNames.contains("KodaiTask"))
        let debugLocalURL = makeLocalConfig().url
        let debugWorkspaceURL = WorkspaceModelContainer.makeConfiguration().url
        print("[PersistenceCheck] macOS local store URL=\(debugLocalURL) entities=\(localEntityNames.sorted())")
        print("[PersistenceCheck] macOS workspace store URL=\(debugWorkspaceURL)")
        precondition(debugLocalURL != debugWorkspaceURL, "Local and workspace configs point to the same store file")
#endif

        do {
            // Stage 1: staged migration against the local store only.
            // Using a dedicated config here so the migration container does not
            // share a ModelConfiguration instance with the final container.
            // Including CloudKit workspace models in the migration coordinator
            // makes historical V3 stores appear unrecognized.
            _ = try ModelContainer(
                for: localSchema,
                migrationPlan: KodaiLocalStoreMigrationPlan.self,
                configurations: [makeLocalConfig()]
            )
        } catch {
            // EXPECTED on healthy stores: the final container stamps
            // default.store with an unversioned union-schema checksum the
            // migration plan does not recognize (134504 "unknown model
            // version"). The final container is the arbiter of store health —
            // a Stage-1 failure alone must never quarantine anything.
            print("[PersistenceCheck] Staged migration skipped (final container decides): \(error)")
        }

        do {
            // Stage 2: final container with fresh config instances.
            return try makeFinalContainer()
        } catch {
            // Only a final-container failure counts as corruption. Quarantine
            // the broken files (never delete), then prefer restoring the
            // newest quarantined snapshot that still has chat rows over
            // booting on empty stores.
            print("[PersistenceCheck] Final container failed: \(error)")

            let localURL = makeLocalConfig().url
            let workspaceURL = WorkspaceModelContainer.makeConfiguration().url
            PersistenceRecovery.quarantine(storeURLs: [localURL, workspaceURL])

            if let snapshot = PersistenceRecovery.newestSnapshotWithChats(near: localURL),
               PersistenceRecovery.restoreSnapshot(snapshot, to: localURL) {
                if let restored = try? makeFinalContainer() {
                    return restored
                }
                // The restored snapshot fails too — re-quarantine it and fall
                // through to fresh stores.
                PersistenceRecovery.quarantine(storeURLs: [localURL])
            }

            do {
                return try makeFinalContainer()
            } catch let recoveryError {
                fatalError("Model container creation failed even after quarantine recovery: \(recoveryError)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .background(.clear)
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(container)

        // Always inserted, on purpose. Binding isInserted (to the rhythm
        // toggle) sends SwiftUI on macOS 26.4 into an infinite main-menu
        // invalidation loop — 100% CPU, unbounded memory, beachball — even
        // while the extra is NOT inserted. Do not add isInserted back
        // without sampling the main thread on a clean launch.
        MenuBarExtra("Kodai", systemImage: "circle.hexagongrid.fill") {
            MenuBarGlanceView()
                .modelContainer(container)
        }
        .menuBarExtraStyle(.window)
    }
}
