import Foundation
import KodaiPersistence
import SwiftData

/// SwiftData container for workspace data (projects/tasks).
///
/// iOS syncs KodaiProject and KodaiTask via CloudKit container
/// "iCloud.com.ctxa.kodai". Chats, sessions, summaries, turns,
/// activity events, metrics, and tools are not part of this schema and remain
/// local-only in their own stores.
enum WorkspaceModelContainer {
    static let cloudKitContainerIdentifier = "iCloud.com.ctxa.kodai"

    static let schema = Schema([
        KodaiProject.self,
        KodaiTask.self
    ])

    static let storeFileName = "KodaiWorkspace.store"

    /// On-disk store under Application Support, synced via CloudKit on iOS.
    static func makeLocal() throws -> ModelContainer {
#if DEBUG
        let entityNames = Set(schema.entitiesByName.keys)
        precondition(entityNames == ["KodaiProject", "KodaiTask"])
        print(
            "[PersistenceCheck] iOS workspace store=KodaiWorkspace " +
            "entities=\(entityNames.sorted()) cloudKit=\(cloudKitContainerIdentifier)"
        )
#endif
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
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
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
