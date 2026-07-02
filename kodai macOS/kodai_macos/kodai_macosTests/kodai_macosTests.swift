//
//  kodai_macosTests.swift
//  kodai_macosTests
//
//  Created by Charles Thomas Xavier Austin III on 6/9/26.
//

import Foundation
import Testing
import SwiftData
import KodaiCore
@testable import KodAi

struct kodai_macosTests {

    @Test func liveEntitySignalsMapIntoNormalizedLifeSigns() {
        let state = LiveEntitySignalState(
            status: .responding,
            contextPercent: 72,
            tasksDueCount: 4,
            selectedProjectName: "Kodai",
            memoryReady: true,
            toolActionReady: true
        )

        #expect(state.modelPulse == 1)
        #expect(state.contextPressure == 0.72)
        #expect(state.responseHeat == 0.88)
        #expect(state.focusLock == 0.86)
        #expect(state.taskPressure == 0.76)
        #expect(state.readiness == 1)
    }

    @Test func liveEntitySignalsStayCalmWithoutContext() {
        let state = LiveEntitySignalState(
            status: .idle,
            contextPercent: -10,
            tasksDueCount: 0,
            selectedProjectName: nil,
            memoryReady: false,
            toolActionReady: false
        )

        #expect(state.modelPulse == 0.14)
        #expect(state.contextPressure == 0)
        #expect(state.responseHeat == 0.08)
        #expect(state.focusLock == 0.12)
        #expect(state.taskPressure == 0.08)
        #expect(state.readiness == 0.1)
    }

    @MainActor
    @Test func newChatRemainsTransientUntilUserMessage() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let viewModel = ChatViewModel()

        let session = viewModel.createNewChat(context: context)
        let storedSessions = try context.fetch(FetchDescriptor<KodaiChatSession>())

        #expect(session.modelContext == nil)
        #expect(storedSessions.isEmpty)
        #expect(viewModel.messages.isEmpty)
    }

    @MainActor
    @Test func cleanupRemovesOnlySessionsWithoutVisibleMessages() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let emptySession = KodaiChatSession()
        let populatedSession = KodaiChatSession()
        let assistantMessage = KodaiChatMessage(
            role: "assistant",
            content: "Existing response",
            session: populatedSession
        )

        context.insert(emptySession)
        context.insert(populatedSession)
        context.insert(assistantMessage)
        populatedSession.messages.append(assistantMessage)
        try context.save()

        ChatViewModel().cleanupEmptySessions(context: context)

        let storedSessions = try context.fetch(FetchDescriptor<KodaiChatSession>())
        #expect(storedSessions.map(\.id) == [populatedSession.id])
    }

    @MainActor
    @Test func workspaceExecutorCreatesProjectAfterApproval() async throws {
        let broker = ConfirmBroker()
        let executor = WorkspaceToolExecutor(broker: broker)
        var createdTitle: String?
        executor.performCreateProject = { title in
            createdTitle = title
            return .ok(tool: WorkspaceToolExecutor.createProjectToolID, result: ["title": title])
        }

        let resultTask = Task { await executor.createProject(title: "WGU") }
        var spins = 0
        while broker.pending == nil && spins < 10_000 {
            await Task.yield()
            spins += 1
        }

        let pending = try #require(broker.pending)
        #expect(pending.request.heading == "Create project?")
        #expect(pending.request.subject == "WGU")
        #expect(pending.request.confirmLabel == "Create Project")

        broker.resolve(approved: true)
        let result = await resultTask.value
        #expect(result.status == .ok)
        #expect(createdTitle == "WGU")
    }

    @MainActor
    @Test func workspaceExecutorReportsCancellationWhenDeclined() async throws {
        let broker = ConfirmBroker()
        let executor = WorkspaceToolExecutor(broker: broker)
        var performed = false
        executor.performCreateTask = { title, priority, _ in
            performed = true
            return .ok(
                tool: WorkspaceToolExecutor.createTaskToolID,
                result: ["title": title, "priority": priority.rawValue]
            )
        }

        let resultTask = Task {
            await executor.createTask(title: "Read", priority: "high", dueDate: "")
        }
        var spins = 0
        while broker.pending == nil && spins < 10_000 {
            await Task.yield()
            spins += 1
        }

        #expect(broker.pending?.request.heading == "Create task?")
        broker.resolve(approved: false)

        let result = await resultTask.value
        #expect(result.status == .error)
        #expect(result.fields["error"] == "cancelled_by_user")
        #expect(performed == false)
        #expect(broker.pending == nil)
    }

    @MainActor
    @Test func workspaceExecutorFailsSafelyWithoutTurnBindings() async {
        let broker = ConfirmBroker()
        let executor = WorkspaceToolExecutor(broker: broker)

        let result = await executor.createTask(title: "Read", priority: "medium", dueDate: "")

        #expect(result.status == .error)
        #expect(result.fields["error"] == "workspace unavailable")
        #expect(broker.pending == nil)
    }

    @Test func juneThirteenthRemainsJuneThirteenthInCurrentCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 12)))

        let dueDate = try #require(
            TaskDueDateSemantics.parse("2026-06-13", now: now, calendar: calendar)
        )
        let components = calendar.dateComponents([.year, .month, .day], from: dueDate)

        #expect(components.year == 2026)
        #expect(components.month == 6)
        #expect(components.day == 13)
    }

    @MainActor
    @Test func dueDateCorrectionUpdatesConfirmedTaskWithoutDuplicating() throws {
        let container = try makeFullContainer()
        let context = container.mainContext
        let viewModel = ChatViewModel()
        let project = viewModel.createProject(title: "WGU", context: context)
        _ = viewModel.createNewChat(context: context, project: project)

        let session = try #require(viewModel.selectedChat)
        let createdTask = viewModel.createTask(
            in: project,
            title: "Read",
            priority: .medium,
            dueDate: TaskDueDateSemantics.parse("2026-06-14"),
            context: context
        )
        viewModel.noteRecentCreatedTask(createdTask, sessionID: session.id)

        viewModel.inputText = "no, due June 13th!"
        viewModel.send(context: context, projects: [project])

        let tasks = try context.fetch(FetchDescriptor<KodaiTask>())
        let task = try #require(tasks.first)
        let components = Calendar.current.dateComponents([.month, .day], from: try #require(task.dueDate))
        #expect(tasks.count == 1)
        #expect(components.month == 6)
        #expect(components.day == 13)
        #expect(viewModel.lastAssistantMessage == "Updated task: Read (due Jun 13)")
    }

    // The KodAi test host is CloudKit-entitled, so ModelConfiguration's default
    // cloudKitDatabase (.automatic) tries to mirror these in-memory stores to
    // CloudKit and container creation fails with loadIssueModelContainer.
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: KodaiChatSession.self,
            KodaiChatMessage.self,
            configurations: configuration
        )
    }

    @MainActor
    private func makeFullContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: KodaiProject.self,
            KodaiTask.self,
            KodaiChatSession.self,
            KodaiChatMessage.self,
            KodaiSummary.self,
            KodaiStream.self,
            TurnRecord.self,
            ActivityEvent.self,
            ModelPerformanceMetric.self,
            ToolCall.self,
            configurations: configuration
        )
    }
}
