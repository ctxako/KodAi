//
//  WorkspaceProjectStoreTests.swift
//  kodAI_chatbot_devTests
//
//  K2D: Projects.json → SwiftData workspace migration and the SwiftData
//  source-of-truth behavior of WorkspaceProjectStore.
//

import Foundation
import KodaiKernel
import KodaiPersistence
import SwiftData
import Testing

@testable import kodAI_chatbot_dev

struct WorkspaceProjectStoreTests {

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceProjectStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeProjectsJSON(_ projects: [KodaiProjectValue], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(projects).write(to: url, options: [.atomic])
    }

    /// Two projects with stable ids, due dates, deadlines, priorities, and
    /// completion state. Dates land on whole seconds so they survive the
    /// iso8601 round-trip exactly.
    private func sampleProjects() -> [KodaiProjectValue] {
        let projectID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondProjectID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let taskID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let doneTaskID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        return [
            KodaiProjectValue(
                id: projectID,
                title: "Launch",
                details: "v1 scope",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_100_000),
                deadline: Date(timeIntervalSince1970: 1_910_000_000),
                tasks: [
                    KodaiTaskValue(
                        id: taskID,
                        title: "Ship build",
                        details: "TestFlight",
                        createdAt: Date(timeIntervalSince1970: 1_700_000_100),
                        updatedAt: Date(timeIntervalSince1970: 1_700_000_200),
                        dueDate: Date(timeIntervalSince1970: 1_905_000_000),
                        priority: .normal,
                        isCompleted: false
                    ),
                    KodaiTaskValue(
                        id: doneTaskID,
                        title: "Write notes",
                        createdAt: Date(timeIntervalSince1970: 1_700_000_300),
                        updatedAt: Date(timeIntervalSince1970: 1_700_000_400),
                        priority: .high,
                        isCompleted: true,
                        completedAt: Date(timeIntervalSince1970: 1_700_000_400)
                    )
                ]
            ),
            KodaiProjectValue(
                id: secondProjectID,
                title: "Inbox",
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_710_000_000)
            )
        ]
    }

    // MARK: - Migration

    @Test func freshInstallWithNoJSONLoadsEmpty() async throws {
        let directory = try makeTempDirectory()
        let jsonURL = directory.appendingPathComponent("Projects.json")
        let store = WorkspaceProjectStore(
            container: try WorkspaceModelContainer.makeInMemory(),
            jsonFileURL: jsonURL
        )
        let projects = try await store.loadProjects()
        #expect(projects.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func migrationImportsProjectsAndTasksPreservingFields() async throws {
        let directory = try makeTempDirectory()
        let jsonURL = directory.appendingPathComponent("Projects.json")
        let sample = sampleProjects()
        try writeProjectsJSON(sample, to: jsonURL)

        let container = try WorkspaceModelContainer.makeInMemory()
        let store = WorkspaceProjectStore(container: container, jsonFileURL: jsonURL)
        let loaded = try await store.loadProjects()

        // Load order is createdAt-descending (newest first).
        #expect(loaded.map(\.id) == [sample[1].id, sample[0].id])

        let launch = try #require(loaded.first { $0.id == sample[0].id })
        #expect(launch.title == "Launch")
        #expect(launch.details == "v1 scope")
        #expect(launch.deadline == sample[0].deadline)
        #expect(launch.createdAt == sample[0].createdAt)
        #expect(launch.updatedAt == sample[0].updatedAt)
        // Task order from valueRepresentation is (priority, createdAt):
        // the high-priority completed task sorts first.
        #expect(launch.tasks.map(\.id) == [sample[0].tasks[1].id, sample[0].tasks[0].id])

        let shipTask = try #require(launch.tasks.first { $0.id == sample[0].tasks[0].id })
        #expect(shipTask == sample[0].tasks[0])
        #expect(shipTask.dueDate == sample[0].tasks[0].dueDate)
        #expect(shipTask.priority == .normal)
        #expect(shipTask.isCompleted == false)

        let doneTask = try #require(launch.tasks.first { $0.id == sample[0].tasks[1].id })
        #expect(doneTask.isCompleted)
        #expect(doneTask.completedAt == sample[0].tasks[1].completedAt)
    }

    @Test func migrationPreservesNormalMediumPriorityAdapterMapping() async throws {
        let directory = try makeTempDirectory()
        let jsonURL = directory.appendingPathComponent("Projects.json")
        try writeProjectsJSON(sampleProjects(), to: jsonURL)

        let container = try WorkspaceModelContainer.makeInMemory()
        let store = WorkspaceProjectStore(container: container, jsonFileURL: jsonURL)
        _ = try await store.loadProjects()

        // Kernel "normal" is stored as the persistence "medium" raw value.
        let context = ModelContext(container)
        let tasks = try context.fetch(FetchDescriptor<KodaiTask>())
        let ship = try #require(tasks.first { $0.title == "Ship build" })
        #expect(ship.priority == .medium)
        #expect(ship.valueRepresentation.priority == .normal)
    }

    @Test func migrationRenamesJSONToTimestampedBackup() async throws {
        let directory = try makeTempDirectory()
        let jsonURL = directory.appendingPathComponent("Projects.json")
        try writeProjectsJSON(sampleProjects(), to: jsonURL)

        let store = WorkspaceProjectStore(
            container: try WorkspaceModelContainer.makeInMemory(),
            jsonFileURL: jsonURL
        )
        _ = try await store.loadProjects()

        #expect(!FileManager.default.fileExists(atPath: jsonURL.path))
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(contents.count == 1)
        let backupName = try #require(contents.first)
        #expect(backupName.hasPrefix("Projects.json.migrated-"))
        // Original bytes preserved in the backup.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backupData = try Data(contentsOf: directory.appendingPathComponent(backupName))
        let restored = try decoder.decode([KodaiProjectValue].self, from: backupData)
        #expect(restored == sampleProjects())
    }

    @Test func rerunningMigrationDoesNotDuplicate() async throws {
        let directory = try makeTempDirectory()
        let jsonURL = directory.appendingPathComponent("Projects.json")
        let sample = sampleProjects()
        try writeProjectsJSON(sample, to: jsonURL)

        let container = try WorkspaceModelContainer.makeInMemory()
        // First import.
        let firstContext = ModelContext(container)
        let first = try ProjectsJSONMigration.run(jsonFileURL: jsonURL, context: firstContext)
        guard case .migrated(2, 2, let backupURL) = first else {
            Issue.record("unexpected outcome \(first)")
            return
        }
        // Simulate the backup rename having failed: restore the JSON and
        // run the migration again against the same store.
        try FileManager.default.moveItem(at: backupURL, to: jsonURL)
        let secondContext = ModelContext(container)
        let second = try ProjectsJSONMigration.run(jsonFileURL: jsonURL, context: secondContext)
        guard case .migrated(2, 2, _) = second else {
            Issue.record("unexpected outcome \(second)")
            return
        }

        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<KodaiProject>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<KodaiTask>()).count == 2)
        let ids = try context.fetch(FetchDescriptor<KodaiProject>()).map(\.id)
        #expect(Set(ids) == Set(sample.map(\.id)))
    }

    @Test func failedDecodeLeavesJSONUnrenamedAndFallsBackToJSONStore() async throws {
        let directory = try makeTempDirectory()
        let jsonURL = directory.appendingPathComponent("Projects.json")
        try Data("not valid json {{{".utf8).write(to: jsonURL)

        let container = try WorkspaceModelContainer.makeInMemory()
        let store = WorkspaceProjectStore(container: container, jsonFileURL: jsonURL)
        // The store survives the failed migration by falling back to the
        // JSON store, which treats an undecodable file as empty (existing
        // pre-K2D behavior).
        let projects = try await store.loadProjects()
        #expect(projects.isEmpty)

        // The broken file is still there, byte for byte.
        #expect(FileManager.default.fileExists(atPath: jsonURL.path))
        #expect(try Data(contentsOf: jsonURL) == Data("not valid json {{{".utf8))
        // Nothing was committed to SwiftData.
        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<KodaiProject>()).isEmpty)
    }

    @Test func migrationImportsNoChatData() async throws {
        let directory = try makeTempDirectory()
        let jsonURL = directory.appendingPathComponent("Projects.json")
        try writeProjectsJSON(sampleProjects(), to: jsonURL)

        let container = try WorkspaceModelContainer.makeInMemory()
        let store = WorkspaceProjectStore(container: container, jsonFileURL: jsonURL)
        let loaded = try await store.loadProjects()
        #expect(loaded.count == 2)

        // Chats stay in ChatStore JSON: the chat models are schema-only and
        // must never gain rows from workspace migration or saves.
        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<KodaiChatSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<KodaiChatMessage>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<KodaiStream>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<KodaiSummary>()).isEmpty)
    }

    @Test func projectValuesFromSwiftDataExcludeChatSessions() async throws {
        let container = try WorkspaceModelContainer.makeInMemory()
        // Even if a project somehow carried a session, the value layer the
        // app consumes has no chat fields at all.
        let context = ModelContext(container)
        let project = KodaiProject(title: "With session")
        context.insert(project)
        project.sessions.append(KodaiChatSession(title: "Stray chat"))
        try context.save()

        let directory = try makeTempDirectory()
        let store = WorkspaceProjectStore(
            container: container,
            jsonFileURL: directory.appendingPathComponent("Projects.json")
        )
        let loaded = try await store.loadProjects()
        let value = try #require(loaded.first)
        #expect(value.title == "With session")
        #expect(value.tasks.isEmpty)
        // KodaiProjectValue is Codable with no session key; encoding proves
        // no chat content leaks through the workspace value path.
        let encoded = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        #expect(!encoded.contains("Stray chat"))
    }

    // MARK: - SwiftData as source of truth

    @Test func savePersistsCreateUpdateToggleAndDelete() async throws {
        let directory = try makeTempDirectory()
        let jsonURL = directory.appendingPathComponent("Projects.json")
        let container = try WorkspaceModelContainer.makeInMemory()
        let store = WorkspaceProjectStore(container: container, jsonFileURL: jsonURL)

        // Create.
        var project = KodaiProjectValue(title: "New project")
        let task = KodaiTaskValue(title: "First task", dueDate: Date(timeIntervalSince1970: 1_905_000_000))
        project.tasks = [task]
        try await store.saveProjects([project])
        var loaded = try await store.loadProjects()
        #expect(loaded.map(\.id) == [project.id])
        #expect(loaded[0].tasks.map(\.id) == [task.id])
        #expect(loaded[0].tasks[0].dueDate == task.dueDate)

        // Update title, toggle completion, clear due date.
        project.title = "Renamed"
        project.tasks[0].isCompleted = true
        project.tasks[0].completedAt = Date(timeIntervalSince1970: 1_905_000_100)
        project.tasks[0].dueDate = nil
        try await store.saveProjects([project])
        loaded = try await store.loadProjects()
        #expect(loaded[0].title == "Renamed")
        #expect(loaded[0].tasks[0].isCompleted)
        #expect(loaded[0].tasks[0].dueDate == nil)
        // Same identity, not a new row.
        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<KodaiProject>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<KodaiTask>()).count == 1)

        // Delete.
        try await store.saveProjects([])
        loaded = try await store.loadProjects()
        #expect(loaded.isEmpty)
        let afterDelete = ModelContext(container)
        #expect(try afterDelete.fetch(FetchDescriptor<KodaiProject>()).isEmpty)
        #expect(try afterDelete.fetch(FetchDescriptor<KodaiTask>()).isEmpty)
        // No JSON file reappears: SwiftData is the source of truth.
        #expect(!FileManager.default.fileExists(atPath: jsonURL.path))
    }
}
