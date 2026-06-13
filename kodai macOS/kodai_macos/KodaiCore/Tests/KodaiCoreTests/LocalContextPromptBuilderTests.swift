import XCTest
@testable import KodaiKernel

final class LocalContextPromptBuilderTests: XCTestCase {

    private func makeDueTask(_ title: String, project: String = "P", isOverdue: Bool) -> DueTaskValue {
        DueTaskValue(
            task: KodaiTaskValue(title: title, dueDate: Date()),
            projectID: UUID(),
            projectTitle: project,
            isOverdue: isOverdue
        )
    }

    func testEmptySnapshotReturnsNoPrompt() {
        let result = KodaiLocalContextPromptBuilder.build(snapshot: KodaiLocalContextSnapshotValue())
        XCTAssertNil(result.promptBlock)
        let localBlock = result.contextBlocks.last
        XCTAssertEqual(localBlock?.kind, "Local context")
        XCTAssertTrue(localBlock?.content.contains("Nothing injected") ?? false)
    }

    func testSelectedProjectWithActiveTasksBuildsCompactPrompt() {
        let project = KodaiProjectValue(
            title: "Launch",
            deadline: Date(timeIntervalSince1970: 1_900_000_000),
            tasks: [
                KodaiTaskValue(title: "Write copy"),
                KodaiTaskValue(title: "Ship build", isCompleted: true),
                KodaiTaskValue(title: "Fix bug")
            ]
        )
        let result = KodaiLocalContextPromptBuilder.build(
            snapshot: KodaiLocalContextSnapshotValue(selectedProject: project)
        )
        let prompt = try! XCTUnwrap(result.promptBlock)
        XCTAssertTrue(prompt.hasPrefix("[LOCAL KODAI CONTEXT]"))
        XCTAssertTrue(prompt.hasSuffix("[/LOCAL KODAI CONTEXT]"))
        XCTAssertTrue(prompt.contains("Selected project: Launch"))
        XCTAssertTrue(prompt.contains("Project deadline:"))
        XCTAssertTrue(prompt.contains("- Write copy"))
        XCTAssertTrue(prompt.contains("- Fix bug"))
        XCTAssertFalse(prompt.contains("Ship build"), "completed tasks must be excluded")
    }

    func testProjectTaskCapIsEnforcedAtEight() {
        let tasks = (1...12).map { KodaiTaskValue(title: "Task \($0)") }
        let project = KodaiProjectValue(title: "Big", tasks: tasks)
        let result = KodaiLocalContextPromptBuilder.build(
            snapshot: KodaiLocalContextSnapshotValue(selectedProject: project)
        )
        let prompt = try! XCTUnwrap(result.promptBlock)
        XCTAssertTrue(prompt.contains("- Task 8"))
        XCTAssertFalse(prompt.contains("- Task 9"))
    }

    func testDueTaskCapIsEnforcedAtEight() {
        let due = (1...12).map { makeDueTask("Due \($0)", isOverdue: false) }
        let result = KodaiLocalContextPromptBuilder.build(
            snapshot: KodaiLocalContextSnapshotValue(todayAndOverdueTasks: due)
        )
        let prompt = try! XCTUnwrap(result.promptBlock)
        XCTAssertTrue(prompt.contains("Due 8"))
        XCTAssertFalse(prompt.contains("Due 9"))
    }

    func testOverdueTasksAppearBeforeTodayTasks() {
        let due = [
            makeDueTask("Today A", isOverdue: false),
            makeDueTask("Late B", isOverdue: true)
        ]
        let result = KodaiLocalContextPromptBuilder.build(
            snapshot: KodaiLocalContextSnapshotValue(todayAndOverdueTasks: due)
        )
        let prompt = try! XCTUnwrap(result.promptBlock)
        let overdueIndex = try! XCTUnwrap(prompt.range(of: "Overdue: Late B")).lowerBound
        let todayIndex = try! XCTUnwrap(prompt.range(of: "Today: Today A")).lowerBound
        XCTAssertLessThan(overdueIndex, todayIndex)
    }

    func testActionRulesIncludedByDefault() {
        let result = KodaiLocalContextPromptBuilder.build(
            snapshot: KodaiLocalContextSnapshotValue(todayAndOverdueTasks: [makeDueTask("X", isOverdue: true)])
        )
        let prompt = try! XCTUnwrap(result.promptBlock)
        XCTAssertTrue(prompt.contains("Rules:"))
        XCTAssertTrue(prompt.contains("Do not claim to create, edit, delete, or complete tasks directly."))
        XCTAssertTrue(prompt.contains("/propose task"))
    }

    func testActionRulesOmittedWhenDisabled() {
        let result = KodaiLocalContextPromptBuilder.build(
            snapshot: KodaiLocalContextSnapshotValue(todayAndOverdueTasks: [makeDueTask("X", isOverdue: true)]),
            options: KodaiLocalContextPromptOptions(includeActionRules: false)
        )
        let prompt = try! XCTUnwrap(result.promptBlock)
        XCTAssertFalse(prompt.contains("Rules:"))
        XCTAssertTrue(prompt.hasSuffix("[/LOCAL KODAI CONTEXT]"))
    }

    func testContextBlocksIncludeDisplayContent() {
        let project = KodaiProjectValue(title: "Launch", tasks: [KodaiTaskValue(title: "T1")])
        let snapshot = KodaiLocalContextSnapshotValue(
            selectedProject: project,
            todayAndOverdueTasks: [
                makeDueTask("A", isOverdue: true),
                makeDueTask("B", isOverdue: false)
            ],
            assistantModeDescription: "Default",
            currentMessageCount: 5,
            currentChatTokenEstimate: 123
        )
        let result = KodaiLocalContextPromptBuilder.build(snapshot: snapshot)
        let kinds = result.contextBlocks.map(\.kind)
        XCTAssertEqual(kinds, ["Assistant mode", "Selected project", "Today / overdue", "Current chat", "Local context"])

        let byKind = Dictionary(uniqueKeysWithValues: result.contextBlocks.map { ($0.kind, $0) })
        XCTAssertEqual(byKind["Assistant mode"]?.content, "Default")
        XCTAssertEqual(byKind["Selected project"]?.content, "Launch · 1 active task")
        XCTAssertEqual(byKind["Today / overdue"]?.content, "1 due today, 1 overdue")
        XCTAssertEqual(byKind["Current chat"]?.content, "5 messages")
        XCTAssertEqual(byKind["Current chat"]?.tokenEstimate, 123)
        XCTAssertTrue(byKind["Local context"]?.content.contains("Injected into latest prompt") ?? false)
        XCTAssertEqual(result.contextBlocks.map(\.priority), [0, 1, 2, 3, 4])
    }

    func testTokenEstimateIsStableAndNonzeroForInjectedPrompt() {
        let snapshot = KodaiLocalContextSnapshotValue(
            todayAndOverdueTasks: [makeDueTask("Pay rent", isOverdue: true)]
        )
        let first = KodaiLocalContextPromptBuilder.build(snapshot: snapshot)
        let second = KodaiLocalContextPromptBuilder.build(snapshot: snapshot)
        let firstEstimate = first.contextBlocks.last?.tokenEstimate ?? 0
        XCTAssertGreaterThan(firstEstimate, 0)
        XCTAssertEqual(firstEstimate, second.contextBlocks.last?.tokenEstimate)
        XCTAssertEqual(
            firstEstimate,
            TokenEstimator.estimate(characterCount: first.promptBlock?.count ?? 0)
        )
    }
}
