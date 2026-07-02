import Testing
import Foundation
import SwiftData
@testable import kodai_consumer

private func makeStore(suite: String = "toolflow-tests-\(UUID().uuidString)") throws -> (ToolflowStore, UserDefaults) {
    let schema = Schema([Toolflow.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: config)
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (ToolflowStore(context: ModelContext(container), sharedDefaults: defaults), defaults)
}

struct ToolflowStoreTests {

    @Test func addAndFetchFlows() throws {
        let (store, _) = try makeStore()
        store.add(name: "Morning Brief", icon: "sun.max.fill", prompt: "List today's events.")
        store.add(name: "Clip to File", icon: "doc.on.clipboard.fill", prompt: "Save my clipboard.")

        let flows = store.flows()
        #expect(flows.count == 2)
        #expect(flows[0].name == "Morning Brief")
        #expect(flows[1].name == "Clip to File")
        #expect(flows[1].sortOrder > flows[0].sortOrder)
    }

    @Test func lookupByID() throws {
        let (store, _) = try makeStore()
        store.add(name: "Flow", icon: "bolt.fill", prompt: "Do the thing.")
        let id = store.flows()[0].id

        #expect(store.flow(id: id)?.prompt == "Do the thing.")
        #expect(store.flow(id: UUID()) == nil)
    }

    @Test func updateAndDelete() throws {
        let (store, _) = try makeStore()
        store.add(name: "Old", icon: "bolt.fill", prompt: "old prompt")
        let flow = store.flows()[0]

        store.update(flow, name: "New", icon: "sparkles", prompt: "new prompt")
        #expect(store.flows()[0].name == "New")
        #expect(store.flows()[0].prompt == "new prompt")

        store.delete(flow)
        #expect(store.flows().isEmpty)
    }

    @Test func moveReordersAndRenumbers() throws {
        let (store, _) = try makeStore()
        store.add(name: "A", icon: "bolt.fill", prompt: "a")
        store.add(name: "B", icon: "bolt.fill", prompt: "b")
        store.add(name: "C", icon: "bolt.fill", prompt: "c")

        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        let names = store.flows().map(\.name)
        #expect(names == ["C", "A", "B"])
        #expect(store.flows().map(\.sortOrder) == [0, 1, 2])
    }

    @Test func seedOnlyWhenEmpty() throws {
        let (store, _) = try makeStore()
        store.seedIfEmpty()
        let seeded = store.flows().count
        #expect(seeded > 0)

        store.seedIfEmpty()
        #expect(store.flows().count == seeded)
    }

    // The widget reads this snapshot with its own copy of the struct — the
    // round-trip below is the contract test for that JSON.
    @Test func mirrorWritesSnapshotWidgetCanDecode() throws {
        let (store, defaults) = try makeStore()
        store.add(name: "Morning Brief", icon: "sun.max.fill", prompt: "List today's events.")

        let data = try #require(defaults.data(forKey: ToolflowSharing.snapshotKey))
        let decoded = try JSONDecoder().decode([ToolflowSnapshot].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded[0].name == "Morning Brief")
        #expect(decoded[0].icon == "sun.max.fill")
        #expect(decoded[0].prompt == "List today's events.")
        #expect(decoded[0].id == store.flows()[0].id)

        #expect(ToolflowStore.loadSnapshots(from: defaults) == decoded)
    }

    @Test func deleteClearsSnapshot() throws {
        let (store, defaults) = try makeStore()
        store.add(name: "Flow", icon: "bolt.fill", prompt: "x")
        store.delete(store.flows()[0])

        #expect(ToolflowStore.loadSnapshots(from: defaults).isEmpty)
    }
}
