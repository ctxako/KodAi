import Foundation
import KodaiCore
import SwiftData

/// SwiftData configuration for workspace data (KodaiProject, KodaiTask).
///
/// K2G-A: CloudKit is disabled. The workspace store uses a dedicated SQLite
/// file (KodaiWorkspace.store) separate from the local chat store (default.store).
/// CloudKit sync for macOS is deferred to a later milestone.
enum WorkspaceModelContainer {
    static let schema = Schema([
        KodaiProject.self,
        KodaiTask.self
    ])

    static func makeConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            "KodaiWorkspace",
            schema: schema,
            cloudKitDatabase: .none
        )
    }
}
