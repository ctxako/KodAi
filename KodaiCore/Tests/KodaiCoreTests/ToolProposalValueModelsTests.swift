import XCTest
@testable import KodaiKernel

final class ToolProposalValueModelsTests: XCTestCase {

    func testToolProposalKindRawValuesStable() throws {
        XCTAssertEqual(KodaiToolProposalKind.createTask.rawValue, "createTask")
        let data = try JSONEncoder().encode(KodaiToolProposalKind.createTask)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"createTask\"")
        let decoded = try JSONDecoder().decode(KodaiToolProposalKind.self, from: data)
        XCTAssertEqual(decoded, .createTask)
    }

    func testCreateTaskProposalValueCodableRoundTrip() throws {
        let proposal = KodaiCreateTaskProposalValue(
            title: "Review me",
            details: "Look closely",
            projectID: UUID(),
            projectTitle: "Inbox",
            dueDate: Date(timeIntervalSince1970: 1_900_000_000),
            priority: .high
        )
        let data = try JSONEncoder().encode(proposal)
        let decoded = try JSONDecoder().decode(KodaiCreateTaskProposalValue.self, from: data)
        XCTAssertEqual(decoded, proposal)
    }

    func testPendingToolProposalValueCodableRoundTrip() throws {
        let pending = KodaiPendingToolProposalValue(
            kind: .createTask,
            title: "Create task",
            message: "Confirm to create this task.",
            createdAt: Date(timeIntervalSince1970: 1_900_000_500),
            createTask: KodaiCreateTaskProposalValue(title: "Ship it")
        )
        let data = try JSONEncoder().encode(pending)
        let decoded = try JSONDecoder().decode(KodaiPendingToolProposalValue.self, from: data)
        XCTAssertEqual(decoded, pending)
    }

    func testCreateTaskProposalPreservesFields() {
        let projectID = UUID()
        let due = Date(timeIntervalSince1970: 1_910_000_000)
        let pending = KodaiPendingToolProposalValue(
            kind: .createTask,
            title: "Create task",
            createTask: KodaiCreateTaskProposalValue(
                title: "Due today",
                projectID: projectID,
                projectTitle: "Launch",
                dueDate: due,
                priority: .low
            )
        )
        XCTAssertEqual(pending.createTask?.projectID, projectID)
        XCTAssertEqual(pending.createTask?.projectTitle, "Launch")
        XCTAssertEqual(pending.createTask?.dueDate, due)
        XCTAssertEqual(pending.createTask?.priority, .low)
    }

    func testDefaultsAreNormalPriorityAndEmptyMessage() {
        let proposal = KodaiCreateTaskProposalValue(title: "Plain")
        XCTAssertEqual(proposal.priority, .normal)
        XCTAssertNil(proposal.details)
        XCTAssertNil(proposal.projectID)
        XCTAssertNil(proposal.dueDate)

        let pending = KodaiPendingToolProposalValue(kind: .createTask, title: "Create task")
        XCTAssertEqual(pending.message, "")
        XCTAssertNil(pending.createTask)
    }
}
