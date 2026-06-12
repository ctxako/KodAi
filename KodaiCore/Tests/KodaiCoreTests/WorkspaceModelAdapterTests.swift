import XCTest
import SwiftData
@testable import KodaiKernel
@testable import KodaiPersistence

final class WorkspaceModelAdapterTests: XCTestCase {

    // MARK: - Priority mapping

    func testPriorityMappingKernelToPersistence() {
        XCTAssertEqual(TaskPriority(KodaiTaskPriority.low), .low)
        XCTAssertEqual(TaskPriority(KodaiTaskPriority.normal), .medium)
        XCTAssertEqual(TaskPriority(KodaiTaskPriority.high), .high)
    }

    func testPriorityMappingPersistenceToKernel() {
        XCTAssertEqual(TaskPriority.low.kernelValue, KodaiTaskPriority.low)
        XCTAssertEqual(TaskPriority.medium.kernelValue, KodaiTaskPriority.normal)
        XCTAssertEqual(TaskPriority.high.kernelValue, KodaiTaskPriority.high)
    }

    func testPriorityMappingIsTotalAndRoundTrips() {
        for kernel in KodaiTaskPriority.allCases {
            XCTAssertEqual(TaskPriority(kernel).kernelValue, kernel)
        }
        for model in TaskPriority.allCases {
            XCTAssertEqual(TaskPriority(model.kernelValue), model)
        }
    }

    func testPriorityRawValueDriftIsExplicit() {
        // Stored vocabularies intentionally differ; the adapter is the only
        // bridge. Guard the raw values so a rename can't silently mis-map.
        XCTAssertEqual(TaskPriority.medium.rawValue, "medium")
        XCTAssertEqual(KodaiTaskPriority.normal.rawValue, "normal")
        XCTAssertNil(TaskPriority(rawValue: "normal"))
        XCTAssertNil(KodaiTaskPriority(rawValue: "medium"))
    }

    func testPrioritySortOrderParity() {
        for kernel in KodaiTaskPriority.allCases {
            XCTAssertEqual(kernel.sortOrder, TaskPriority(kernel).sortOrder)
        }
    }

    // MARK: - Task round-trip

    func testTaskValueToModelToValueRoundTrip() {
        let value = KodaiTaskValue(
            id: UUID(),
            title: "Write report",
            details: "Quarterly numbers",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_500),
            dueDate: Date(timeIntervalSince1970: 1_900_000_000),
            priority: .high,
            isCompleted: true,
            completedAt: Date(timeIntervalSince1970: 1_900_000_100)
        )
        let model = KodaiTask(value: value)
        XCTAssertEqual(model.id, value.id)
        XCTAssertEqual(model.priority, .high)
        XCTAssertEqual(model.valueRepresentation, value)
    }

    func testTaskModelToValueMapsMediumToNormal() {
        let model = KodaiTask(title: "Default priority", priority: .medium)
        XCTAssertEqual(model.valueRepresentation.priority, .normal)
    }

    func testTaskEmptyNotesMapsToNilDetailsAndBack() {
        let model = KodaiTask(title: "No notes")
        let value = model.valueRepresentation
        XCTAssertNil(value.details)
        XCTAssertEqual(KodaiTask(value: value).notes, "")
    }

    func testTaskApplyValueUpdatesMutableFieldsOnly() {
        let model = KodaiTask(
            id: UUID(),
            title: "Old",
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let originalID = model.id
        var value = model.valueRepresentation
        value.title = "New"
        value.priority = .low
        value.dueDate = Date(timeIntervalSince1970: 2_000_000)
        value.isCompleted = true
        value.completedAt = Date(timeIntervalSince1970: 2_000_001)
        value.updatedAt = Date(timeIntervalSince1970: 2_000_002)
        model.apply(value)
        XCTAssertEqual(model.id, originalID)
        XCTAssertEqual(model.createdAt, Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(model.title, "New")
        XCTAssertEqual(model.priority, .low)
        XCTAssertEqual(model.dueDate, Date(timeIntervalSince1970: 2_000_000))
        XCTAssertTrue(model.isCompleted)
        XCTAssertEqual(model.updatedAt, Date(timeIntervalSince1970: 2_000_002))
    }

    // MARK: - Project round-trip

    func testProjectValueToModelToValueRoundTrip() throws {
        let value = KodaiProjectValue(
            id: UUID(),
            title: "Launch",
            details: "v1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            deadline: Date(timeIntervalSince1970: 1_910_000_000),
            tasks: [
                KodaiTaskValue(
                    title: "High",
                    createdAt: Date(timeIntervalSince1970: 1_700_000_100),
                    priority: .high
                ),
                KodaiTaskValue(
                    title: "Normal",
                    createdAt: Date(timeIntervalSince1970: 1_700_000_200),
                    priority: .normal
                ),
                KodaiTaskValue(
                    title: "Low",
                    createdAt: Date(timeIntervalSince1970: 1_700_000_300),
                    priority: .low
                )
            ]
        )
        // Relationship assignment requires the models to live in a context.
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let model = KodaiProject(value: value)
        context.insert(model)
        let restored = model.valueRepresentation
        XCTAssertEqual(restored.id, value.id)
        XCTAssertEqual(restored.title, value.title)
        XCTAssertEqual(restored.details, value.details)
        XCTAssertEqual(restored.deadline, value.deadline)
        XCTAssertEqual(restored.createdAt, value.createdAt)
        XCTAssertEqual(restored.updatedAt, value.updatedAt)
        XCTAssertEqual(restored.tasks, value.tasks)
    }

    func testProjectEmptyDetailsMapsToNil() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let model = KodaiProject(title: "Bare")
        context.insert(model)
        XCTAssertNil(model.valueRepresentation.details)
    }

    func testProjectValueRepresentationExcludesChatSessions() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let model = KodaiProject(title: "With chat")
        context.insert(model)
        model.sessions.append(KodaiChatSession(title: "Chat"))
        let value = model.valueRepresentation
        // KodaiProjectValue has no chat fields at all; this guards that the
        // workspace value stays chat-free even as the model carries sessions.
        XCTAssertEqual(value.tasks, [])
        XCTAssertEqual(value.title, "With chat")
    }

    // MARK: - Persistence round-trip through a store

    func testTaskPersistsAndFetchesWithStableIdentity() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let value = KodaiTaskValue(
            title: "Persist me",
            dueDate: Date(timeIntervalSince1970: 1_905_000_000),
            priority: .normal
        )
        context.insert(KodaiTask(value: value))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<KodaiTask>())
        XCTAssertEqual(fetched.count, 1)
        let restored = try XCTUnwrap(fetched.first).valueRepresentation
        XCTAssertEqual(restored, value)
    }

    func testDuplicateIDsInsertWithoutUpsertAfterUniqueRemoval() throws {
        // CloudKit prep removed @Attribute(.unique); inserts with the same id
        // must now coexist rather than silently upserting.
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let sharedID = UUID()
        context.insert(KodaiTask(value: KodaiTaskValue(id: sharedID, title: "First")))
        context.insert(KodaiTask(value: KodaiTaskValue(id: sharedID, title: "Second")))
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<KodaiTask>())
        XCTAssertEqual(fetched.count, 2)
    }

    // MARK: - Helpers

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([KodaiProject.self, KodaiTask.self, KodaiChatSession.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
