//
//  AppIntent.swift
//  kodai-consumer-widget
//
//  Widget-side halves of the two app contracts:
//  - ToolflowSnapshot mirrors the JSON the app writes to the App Group
//    (see ToolflowStore.mirrorToWidget — same fields, same key).
//  - OpenKodaiIntent backs the Control Center / Lock Screen "Ask kodAI"
//    button; it only opens the app, the agent runs in the app process.
//

import WidgetKit
import AppIntents
import Foundation

struct ToolflowSnapshot: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let icon: String
    let prompt: String
    let sortOrder: Int
}

enum ToolflowSnapshotStore {
    static let appGroup = "group.ctxa.kodai-consumer"
    static let snapshotKey = "toolflows.snapshot.v1"

    static func load() -> [ToolflowSnapshot] {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: snapshotKey),
              let flows = try? JSONDecoder().decode([ToolflowSnapshot].self, from: data)
        else { return [] }
        return flows.sorted { $0.sortOrder < $1.sortOrder }
    }
}

struct OpenKodaiIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask kodAI"
    static var description = IntentDescription("Opens kodAI ready for a new task.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "kodai://new")!))
    }
}
