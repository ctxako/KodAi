//
//  ToolflowIntents.swift
//  kodai-consumer
//
//  Siri / Shortcuts / Spotlight surface for saved toolflows. The entity is
//  backed by the App Group snapshot (not SwiftData) so the query stays a
//  plain read with no store dependency; the intent opens the app and hands
//  the flow's prompt to the normal agent pipeline via IntentActionInbox —
//  same path a widget tap takes, so confirmation gates are identical.
//

import Foundation
import AppIntents

struct ToolflowEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Toolflow"
    static var defaultQuery = ToolflowEntityQuery()

    let id: UUID
    let name: String
    let icon: String
    let prompt: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: icon)
        )
    }

    init(snapshot: ToolflowSnapshot) {
        id = snapshot.id
        name = snapshot.name
        icon = snapshot.icon
        prompt = snapshot.prompt
    }
}

struct ToolflowEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ToolflowEntity] {
        ToolflowStore.loadSnapshots()
            .filter { identifiers.contains($0.id) }
            .map(ToolflowEntity.init)
    }

    func suggestedEntities() async throws -> [ToolflowEntity] {
        ToolflowStore.loadSnapshots().map(ToolflowEntity.init)
    }
}

struct RunToolflowIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Toolflow"
    static var description = IntentDescription(
        "Runs one of your saved kodAI toolflows through the on-device agent.",
        categoryName: "Toolflows"
    )
    // The agent needs the app process (model, confirm cards), so this intent
    // always foregrounds the app and deposits the prompt for pickup.
    static var openAppWhenRun = true

    @Parameter(title: "Toolflow")
    var flow: ToolflowEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentActionInbox.shared.depositPrompt(flow.prompt)
        return .result()
    }
}
