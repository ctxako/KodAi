import Foundation
import SwiftData
import XCTest
@testable import KodaiPersistence

final class StoreMigrationTests: XCTestCase {
    func testRelationshipMigrationPreservesProjectIDs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KodaiMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("test.store")
        let projectID = UUID()
        let sessionID = UUID()
        let summaryID = UUID()
        let looseSessionID = UUID()

        do {
            let schema = Schema(versionedSchema: KodaiLocalStoreSchemaV1.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(
                    schema: schema,
                    url: storeURL,
                    cloudKitDatabase: .none
                )
            )
            let context = ModelContext(container)
            let project = KodaiLocalStoreSchemaV1.KodaiProject(
                id: projectID,
                title: "Migrated project"
            )
            let session = KodaiLocalStoreSchemaV1.KodaiChatSession(
                id: sessionID,
                title: "Linked chat",
                project: project
            )
            let summary = KodaiLocalStoreSchemaV1.KodaiSummary(
                id: summaryID,
                kind: .project,
                content: "Linked summary",
                session: session,
                project: project
            )
            context.insert(project)
            context.insert(session)
            context.insert(summary)
            context.insert(
                KodaiLocalStoreSchemaV1.KodaiChatSession(
                    id: looseSessionID,
                    title: "Loose chat"
                )
            )
            try context.save()
        }

        let schema = Schema(versionedSchema: KodaiLocalStoreSchemaV4.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: KodaiLocalStoreMigrationPlan.self,
            configurations: ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)
        let sessions = try context.fetch(FetchDescriptor<KodaiChatSession>())
        let summaries = try context.fetch(FetchDescriptor<KodaiSummary>())

        XCTAssertEqual(sessions.first { $0.id == sessionID }?.projectID, projectID)
        XCTAssertNil(sessions.first { $0.id == looseSessionID }?.projectID)
        XCTAssertEqual(summaries.first { $0.id == summaryID }?.projectID, projectID)

        XCTAssertNil(schema.entitiesByName["KodaiProject"])
        XCTAssertNil(schema.entitiesByName["KodaiTask"])
    }

    func testV3LocalStoreMigratesInsideSplitStoreContainer() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KodaiSplitStoreMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let localStoreURL = directory.appendingPathComponent("default.store")
        let workspaceStoreURL = directory.appendingPathComponent("KodaiWorkspace.store")

        do {
            let v3Schema = Schema(versionedSchema: KodaiLocalStoreSchemaV3.self)
            _ = try ModelContainer(
                for: v3Schema,
                configurations: ModelConfiguration(
                    schema: v3Schema,
                    url: localStoreURL,
                    cloudKitDatabase: .none
                )
            )
        }

        let localSchema = Schema(versionedSchema: KodaiLocalStoreSchemaV4.self)
        let workspaceSchema = Schema([KodaiProject.self, KodaiTask.self])
        let fullSchema = Schema([
            KodaiProject.self,
            KodaiTask.self,
            KodaiChatSession.self,
            KodaiChatMessage.self,
            KodaiSummary.self,
            KodaiStream.self,
            TurnRecord.self,
            ActivityEvent.self,
            ModelPerformanceMetric.self,
            ToolCall.self
        ])

        do {
            _ = try ModelContainer(
                for: localSchema,
                migrationPlan: KodaiLocalStoreMigrationPlan.self,
                configurations: ModelConfiguration(
                    schema: localSchema,
                    url: localStoreURL,
                    cloudKitDatabase: .none
                )
            )
        }

        _ = try ModelContainer(
            for: fullSchema,
            configurations: [
                ModelConfiguration(
                    schema: localSchema,
                    url: localStoreURL,
                    cloudKitDatabase: .none
                ),
                ModelConfiguration(
                    "KodaiWorkspace",
                    schema: workspaceSchema,
                    url: workspaceStoreURL,
                    cloudKitDatabase: .none
                )
            ]
        )
    }

    func testWorkspaceSchemaSupportsCloudKitConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KodaiCloudKitValidation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let schema = Schema([KodaiProject.self, KodaiTask.self])
        _ = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                "KodaiWorkspaceCloudKitValidation",
                schema: schema,
                url: directory.appendingPathComponent("KodaiWorkspace.store"),
                cloudKitDatabase: .private("iCloud.com.ctxa.kodai")
            )
        )
    }
}
