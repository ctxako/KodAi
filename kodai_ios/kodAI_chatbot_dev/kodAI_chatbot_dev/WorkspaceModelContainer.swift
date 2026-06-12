import Foundation
import KodaiPersistence
import SwiftData

/// Local-only SwiftData container scaffold for workspace data (projects/tasks).
///
/// Not yet the source of truth: ProjectTaskStore still owns Projects.json and
/// ChatStore still owns the chat/stream/prompt-settings JSON. K2D will import
/// Projects.json into this container; chats stay JSON-only.
///
/// The schema must include the full relationship closure of KodaiProject:
/// KodaiProject.sessions pulls in KodaiChatSession, which pulls in
/// KodaiChatMessage, KodaiSummary, and KodaiStream. They are registered so the
/// schema is valid, but nothing writes chat data through this container.
enum WorkspaceModelContainer {
    static let schema = Schema([
        KodaiProject.self,
        KodaiTask.self,
        KodaiChatSession.self,
        KodaiChatMessage.self,
        KodaiSummary.self,
        KodaiStream.self
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
