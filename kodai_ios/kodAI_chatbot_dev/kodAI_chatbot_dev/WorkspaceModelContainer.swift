import Foundation
import KodaiPersistence
import SwiftData

/// Local-only SwiftData container for workspace data (projects/tasks).
///
/// Since K2D this is the source of truth for projects/tasks, accessed through
/// WorkspaceProjectStore (which imports any legacy Projects.json on first
/// access). ChatStore still owns the chat/stream/prompt-settings JSON;
/// chats stay JSON-only.
///
/// Chat data stays outside this workspace-only schema.
enum WorkspaceModelContainer {
    static let schema = Schema([
        KodaiProject.self,
        KodaiTask.self
    ])

    static let storeFileName = "KodaiWorkspace.store"

    /// On-disk store under Application Support, device-local with CloudKit
    /// explicitly disabled.
    static func makeLocal() throws -> ModelContainer {
        let supportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let configuration = ModelConfiguration(
            "KodaiWorkspaceLocal",
            schema: schema,
            url: supportURL.appendingPathComponent(storeFileName),
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// In-memory variant for tests and startup verification.
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
