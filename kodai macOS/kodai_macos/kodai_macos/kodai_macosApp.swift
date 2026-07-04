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

            // Stage 2: final container with fresh config instances.
            return try makeFinalContainer()
        } catch {
#if DEBUG
            // Recovery: quarantine corrupt store files into a timestamped folder
            // so a fresh container can be created without data loss going unnoticed.
            // Production fatalErrors to avoid silently discarding user data.
            print("[PersistenceCheck] Container creation failed: \(error)")

            let fm = FileManager.default
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let storeURLs = [makeLocalConfig().url, WorkspaceModelContainer.makeConfiguration().url]
            let suffixes = ["", "-wal", "-shm"]

            if let baseDir = storeURLs.first.map({ $0.deletingLastPathComponent() }) {
                let corruptDir = baseDir.appendingPathComponent(
                    "CorruptStores/\(timestamp)", isDirectory: true
                )
                try? fm.createDirectory(at: corruptDir, withIntermediateDirectories: true)
                for storeURL in storeURLs {
                    for suffix in suffixes {
                        let src = URL(fileURLWithPath: storeURL.path + suffix)
                        guard fm.fileExists(atPath: src.path) else { continue }
                        let dst = corruptDir.appendingPathComponent(src.lastPathComponent)
                        try? fm.moveItem(at: src, to: dst)
                        print("[PersistenceCheck] Quarantined \(src.lastPathComponent) → CorruptStores/\(timestamp)/")
                    }
                }
            }

            do {
                return try makeFinalContainer()
            } catch let recoveryError {
                fatalError("Model container creation failed even after quarantine recovery: \(recoveryError)")
            }
#else
            fatalError("Failed to create model container: \(error)")
#endif
        }
    }()

    @AppStorage(AccountabilitySettings.rhythmEnabledKey)
    private var rhythmEnabled = false

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .background(.clear)
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(container)

        MenuBarExtra("Kodai", systemImage: "circle.hexagongrid.fill", isInserted: $rhythmEnabled) {
            MenuBarGlanceView()
                .modelContainer(container)
        }
        .menuBarExtraStyle(.window)
    }
}
