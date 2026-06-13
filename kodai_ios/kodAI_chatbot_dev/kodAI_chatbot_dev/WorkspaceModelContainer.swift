import Foundation
import KodaiPersistence
import SwiftData

/// SwiftData container for workspace data (projects/tasks).
///
/// K2F: iOS syncs KodaiProject and KodaiTask via CloudKit (iCloud container
/// "iCloud.ctxa.kodAI-chatbot-dev"). Chats, sessions, summaries, turns,
/// activity events, metrics, and tools are not part of this schema and remain
/// local-only in their own stores. macOS CloudKit container split is deferred
/// to K2G.
enum WorkspaceModelContainer {
    static let schema = Schema([
        KodaiProject.self,
        KodaiTask.self
    ])

    static let storeFileName = "KodaiWorkspace.store"

    /// On-disk store under Application Support, synced via CloudKit on iOS.
    static func makeLocal() throws -> ModelContainer {
        let supportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let configuration = ModelConfiguration(
            "KodaiWorkspace",
            schema: schema,
            url: supportURL.appendingPathComponent(storeFileName),
            cloudKitDatabase: .automatic
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// In-memory variant for tests and startup verification — no CloudKit.
    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "KodaiWorkspaceInMemory",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
