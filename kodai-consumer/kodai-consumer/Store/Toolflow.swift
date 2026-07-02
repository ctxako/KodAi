import Foundation
import SwiftData

/// A saved, named task the agent can run in one tap — from the Home Screen
/// widget, Siri, or the Toolflows list in Settings. The flow is a canned
/// prompt run through the normal agent pipeline, so it can use every tool
/// and every confirmation gate the typed version would.
@Model
final class Toolflow {
    @Attribute(.unique) var id: UUID
    var name: String
    /// SF Symbol name shown on the widget tile and in the list.
    var icon: String
    /// The instruction handed to the agent, verbatim.
    var prompt: String
    var sortOrder: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "bolt.fill",
        prompt: String,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.prompt = prompt
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

/// The JSON contract shared with the widget extension via the App Group.
/// The widget defines an identical struct (it cannot link app code) — if a
/// field changes here, change it in kodai-consumer-widget too and bump the key.
struct ToolflowSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let icon: String
    let prompt: String
    let sortOrder: Int
}

enum ToolflowSharing {
    static let appGroup = "group.ctxa.kodai-consumer"
    static let snapshotKey = "toolflows.snapshot.v1"
    static let widgetKind = "KodaiToolflows"
}
