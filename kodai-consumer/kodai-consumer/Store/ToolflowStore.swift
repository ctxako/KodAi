import Foundation
import SwiftData
import Observation
import SwiftUI // Array.move(fromOffsets:toOffset:) for List reordering
import WidgetKit

@Observable
final class ToolflowStore {
    private let context: ModelContext
    private let sharedDefaults: UserDefaults?

    init(
        context: ModelContext,
        sharedDefaults: UserDefaults? = UserDefaults(suiteName: ToolflowSharing.appGroup)
    ) {
        self.context = context
        self.sharedDefaults = sharedDefaults
    }

    // MARK: - Queries

    func flows() -> [Toolflow] {
        let descriptor = FetchDescriptor<Toolflow>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func flow(id: UUID) -> Toolflow? {
        var descriptor = FetchDescriptor<Toolflow>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Mutations

    func add(name: String, icon: String, prompt: String) {
        let flow = Toolflow(
            name: name,
            icon: icon,
            prompt: prompt,
            sortOrder: (flows().last?.sortOrder ?? -1) + 1
        )
        context.insert(flow)
        persist()
    }

    func update(_ flow: Toolflow, name: String, icon: String, prompt: String) {
        flow.name = name
        flow.icon = icon
        flow.prompt = prompt
        persist()
    }

    func delete(_ flow: Toolflow) {
        context.delete(flow)
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ordered = flows()
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, flow) in ordered.enumerated() {
            flow.sortOrder = index
        }
        persist()
    }

    /// First-run starter flows so the widget isn't an empty grid before the
    /// user has saved anything. Only runs when the table is empty.
    func seedIfEmpty() {
        guard flows().isEmpty else {
            mirrorToWidget()
            return
        }
        context.insert(Toolflow(
            name: "Morning Brief",
            icon: "sun.max.fill",
            prompt: "List today's calendar events, then list my reminders.",
            sortOrder: 0
        ))
        context.insert(Toolflow(
            name: "Clip to File",
            icon: "doc.on.clipboard.fill",
            prompt: "Read my clipboard and save its contents to a new text file in local/Documents named with today's date.",
            sortOrder: 1
        ))
        persist()
    }

    // MARK: - Widget mirror

    private func persist() {
        try? context.save()
        mirrorToWidget()
    }

    /// Writes the snapshot the widget renders from (it can't read SwiftData)
    /// and asks WidgetKit to redraw. Called after every mutation.
    func mirrorToWidget() {
        let snapshots = flows().map {
            ToolflowSnapshot(id: $0.id, name: $0.name, icon: $0.icon, prompt: $0.prompt, sortOrder: $0.sortOrder)
        }
        if let data = try? JSONEncoder().encode(snapshots) {
            sharedDefaults?.set(data, forKey: ToolflowSharing.snapshotKey)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: ToolflowSharing.widgetKind)
    }

    /// The snapshot as the widget and the Run Toolflow intent read it.
    static func loadSnapshots(
        from defaults: UserDefaults? = UserDefaults(suiteName: ToolflowSharing.appGroup)
    ) -> [ToolflowSnapshot] {
        guard let data = defaults?.data(forKey: ToolflowSharing.snapshotKey),
              let snapshots = try? JSONDecoder().decode([ToolflowSnapshot].self, from: data)
        else { return [] }
        return snapshots.sorted { $0.sortOrder < $1.sortOrder }
    }
}
