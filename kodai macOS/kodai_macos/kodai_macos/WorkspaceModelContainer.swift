import Foundation
import KodaiCore
import SwiftData

/// SwiftData configuration for workspace data (KodaiProject, KodaiTask).
///
/// K2G-B: The workspace store uses a dedicated SQLite file
/// (KodaiWorkspace.store) and syncs through CloudKit. The local chat store
/// remains separate and device-only.
enum WorkspaceModelContainer {
    static let schema = Schema([
        KodaiProject.self,
        KodaiTask.self
    ])

    static func makeConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            "KodaiWorkspace",
            schema: schema,
            cloudKitDatabase: .automatic
        )
    }
}
