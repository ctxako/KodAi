import Foundation
import SwiftData
import XCTest
@testable import KodaiPersistence

// K2E: the workspace/chat schema split changes on-disk stores, so both
// migration paths are exercised against real (temp-file) stores:
//  - the macOS full local store migrates via KodaiLocalStoreMigrationPlan,
//    preserving session→project links as scalar projectIDs;
//  - the iOS workspace store reopens with a workspace-only schema after the
//    chat entities are dropped from registration.
//
// XCTest on purpose: the V1 legacy classes share entity names with the live
// models, and SwiftData's process-global entity bookkeeping conflates the two
// when containers for both are created *concurrently*. The XCTest phase of
// `swift test` runs serially before the parallel swift-testing phase, which
// keeps these stores from overlapping with the other SwiftData suites.
// (Sequential coexistence — which is what staged migration itself does — is
// fine; only concurrent creation conflicts.)
final class StoreMigrationTests: XCTestCase {

    private func makeTempStoreURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("K2EStoreMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("test.store")
    }

    func testLocalStoreMigrationPreservesChatProjectLinks() throws {
        let storeURL = try makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }

        let projectID = UUID()
        let linkedSessionID = UUID()
        let looseSessionID = UUID()

        // Build a pre-split store with a relationship-linked session.
        do {
            let v1Schema = Schema(versionedSchema: KodaiLocalStoreSchemaV1.self)
            let container = try ModelContainer(
                for: v1Schema,
                configurations: ModelConfiguration(schema: v1Schema, url: storeURL, cloudKitDatabase: .none)
            )
            let context = ModelContext(container)
            let project = KodaiLocalStoreSchemaV1.KodaiProject(id: projectID, title: "Kodai")
            context.insert(project)
            let task = KodaiLocalStoreSchemaV1.KodaiTask(title: "Ship K2E", project: project)
            context.insert(task)
            let linked = KodaiLocalStoreSchemaV1.KodaiChatSession(id: linkedSessionID, title: "Project chat")
            linked.project = project
            context.insert(linked)
            let message = KodaiLocalStoreSchemaV1.KodaiChatMessage(role: "user", content: "Hello")
            message.session = linked
            context.insert(message)
            let loose = KodaiLocalStoreSchemaV1.KodaiChatSession(id: looseSessionID, title: "Loose chat")
            context.insert(loose)
            try context.save()
        }

        // Reopen through the migration plan.
        let v2Schema = Schema(versionedSchema: KodaiLocalStoreSchemaV2.self)
        let container = try ModelContainer(
            for: v2Schema,
            migrationPlan: KodaiLocalStoreMigrationPlan.self,
            configurations: ModelConfiguration(schema: v2Schema, url: storeURL, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)

        let sessions = try context.fetch(FetchDescriptor<KodaiChatSession>())
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first { $0.id == linkedSessionID }?.projectID, projectID)
        XCTAssertNil(sessions.first { $0.id == looseSessionID }?.projectID)
        XCTAssertEqual(sessions.first { $0.id == linkedSessionID }?.messages.count, 1)

        let projects = try context.fetch(FetchDescriptor<KodaiProject>())
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects.first?.id, projectID)
        XCTAssertEqual(projects.first?.tasks.map(\.title), ["Ship K2E"])
    }

    // Real macOS stores were created before K2B removed the .unique
    // constraints, i.e. with the V0 shape; the plan must chain V0→V1→V2.
    func testLocalStoreMigratesFromV0PreservingChatProjectLinks() throws {
        let storeURL = try makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }

        let projectID = UUID()
        let linkedSessionID = UUID()

        do {
            let v0Schema = Schema(versionedSchema: KodaiLocalStoreSchemaV0.self)
            let container = try ModelContainer(
                for: v0Schema,
                configurations: ModelConfiguration(schema: v0Schema, url: storeURL, cloudKitDatabase: .none)
            )
            let context = ModelContext(container)
            let project = KodaiLocalStoreSchemaV0.KodaiProject(id: projectID, title: "Pre-K2B project")
            context.insert(project)
            let linked = KodaiLocalStoreSchemaV0.KodaiChatSession(id: linkedSessionID, title: "Project chat")
            linked.project = project
            context.insert(linked)
            try context.save()
        }

        let v2Schema = Schema(versionedSchema: KodaiLocalStoreSchemaV2.self)
        let container = try ModelContainer(
            for: v2Schema,
            migrationPlan: KodaiLocalStoreMigrationPlan.self,
            configurations: ModelConfiguration(schema: v2Schema, url: storeURL, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)

        let sessions = try context.fetch(FetchDescriptor<KodaiChatSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.projectID, projectID)
        let projects = try context.fetch(FetchDescriptor<KodaiProject>())
        XCTAssertEqual(projects.map(\.id), [projectID])
    }

    func testWorkspaceStoreReopensWithWorkspaceOnlySchema() throws {
        let storeURL = try makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }

        let projectID = UUID()

        // Build a store with the K2D workspace schema: project/task plus the
        // chat entities the old relationship closure forced in. Chat rows were
        // never written on iOS, so only workspace rows exist.
        do {
            let oldSchema = Schema([
                KodaiLocalStoreSchemaV1.KodaiProject.self,
                KodaiLocalStoreSchemaV1.KodaiTask.self,
                KodaiLocalStoreSchemaV1.KodaiChatSession.self,
                KodaiLocalStoreSchemaV1.KodaiChatMessage.self,
                KodaiLocalStoreSchemaV1.KodaiSummary.self,
                KodaiLocalStoreSchemaV1.KodaiStream.self
            ])
            let container = try ModelContainer(
                for: oldSchema,
                configurations: ModelConfiguration(schema: oldSchema, url: storeURL, cloudKitDatabase: .none)
            )
            let context = ModelContext(container)
            let project = KodaiLocalStoreSchemaV1.KodaiProject(id: projectID, title: "iOS project")
            context.insert(project)
            context.insert(KodaiLocalStoreSchemaV1.KodaiTask(title: "Survive the split", project: project))
            try context.save()
        }

        // Reopen registering only workspace models, exactly like the iOS
        // WorkspaceModelContainer does after K2E.
        let newSchema = Schema([KodaiProject.self, KodaiTask.self])
        let container = try ModelContainer(
            for: newSchema,
            configurations: ModelConfiguration(schema: newSchema, url: storeURL, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)

        let projects = try context.fetch(FetchDescriptor<KodaiProject>())
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects.first?.id, projectID)
        XCTAssertEqual(projects.first?.title, "iOS project")
        XCTAssertEqual(projects.first?.tasks.map(\.title), ["Survive the split"])
    }
}
