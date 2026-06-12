import XCTest
@testable import KodaiKernel

final class WorkspaceValueModelsTests: XCTestCase {

    func testTaskValueCodableRoundTrip() throws {
        let task = KodaiTaskValue(
            title: "Write report",
            details: "Quarterly numbers",
            dueDate: Date(timeIntervalSince1970: 1_900_000_000),
            priority: .high,
            isCompleted: true,
            completedAt: Date(timeIntervalSince1970: 1_900_000_100)
        )
        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(KodaiTaskValue.self, from: data)
        XCTAssertEqual(decoded, task)
    }

    func testProjectValueCodableRoundTripWithTasks() throws {
        let project = KodaiProjectValue(
            title: "Launch",
            details: "v1",
            deadline: Date(timeIntervalSince1970: 1_910_000_000),
            tasks: [
                KodaiTaskValue(title: "A"),
                KodaiTaskValue(title: "B", priority: .low, isCompleted: true)
            ]
        )
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(KodaiProjectValue.self, from: data)
        XCTAssertEqual(decoded, project)
        XCTAssertEqual(decoded.incompleteTasks.map(\.title), ["A"])
        XCTAssertEqual(decoded.completedTasks.map(\.title), ["B"])
    }

    func testTaskPriorityRawValuesStable() {
        XCTAssertEqual(KodaiTaskPriority.low.rawValue, "low")
        XCTAssertEqual(KodaiTaskPriority.normal.rawValue, "normal")
        XCTAssertEqual(KodaiTaskPriority.high.rawValue, "high")
        XCTAssertEqual(KodaiTaskPriority.allCases, [.low, .normal, .high])
    }

    func testTaskValueDecodingDefaultsMissingFields() throws {
        // Older saved JSON may omit priority/isCompleted; decoding must default them.
        let json = """
        {"id":"\(UUID().uuidString)","title":"Legacy","createdAt":700000000,"updatedAt":700000000}
        """
        let decoded = try JSONDecoder().decode(KodaiTaskValue.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.priority, .normal)
        XCTAssertFalse(decoded.isCompleted)
        XCTAssertNil(decoded.dueDate)
    }

    func testDueTaskValueStoresProjectAssociation() {
        let task = KodaiTaskValue(title: "Due thing")
        let projectID = UUID()
        let due = DueTaskValue(task: task, projectID: projectID, projectTitle: "Proj", isOverdue: true)
        XCTAssertEqual(due.id, task.id)
        XCTAssertEqual(due.projectID, projectID)
        XCTAssertEqual(due.projectTitle, "Proj")
        XCTAssertTrue(due.isOverdue)
    }
}
