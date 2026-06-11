import Foundation
import Testing
import SwiftData
@testable import KodaiCore

// MARK: - Container helper

private func makeContainer() throws -> ModelContainer {
    let schema = Schema([
        KodaiProject.self,
        KodaiChatSession.self,
        KodaiChatMessage.self,
        TurnRecord.self,
        MemoryEntry.self,
        Summary.self,
        KodaiTask.self,
        ActivityEvent.self,
        ToolCall.self,
        ModelPerformanceMetric.self,
        FileReference.self,
        KodaiReminder.self
    ])
    return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
}

// MARK: - TokenEstimator

@Suite("TokenEstimator")
struct TokenEstimatorTests {
    @Test func emptyStringReturnsOne() {
        #expect(TokenEstimator.estimate("") == 1)
    }

    @Test func singleCharReturnsOne() {
        #expect(TokenEstimator.estimate("a") == 1)
    }

    @Test func fourBytesIsOneToken() {
        #expect(TokenEstimator.estimate("four") == 1)
    }

    @Test func hundredCharsIsRoughlyTwentyFiveTokens() {
        let text = String(repeating: "x", count: 100)
        #expect(TokenEstimator.estimate(text) == 25)
    }

    @Test func multibyteUTF8CountedByBytes() {
        // "€" is 3 bytes in UTF-8, so 6 "€" chars = 18 bytes → 18/4 = 4
        let text = String(repeating: "€", count: 6)
        #expect(TokenEstimator.estimate(text) == 4)
    }
}

// MARK: - Enum defaults

@Suite("Enum raw values")
struct EnumTests {
    @Test func chatRoleRawValues() {
        #expect(ChatRole.user.rawValue == "user")
        #expect(ChatRole.assistant.rawValue == "assistant")
        #expect(ChatRole.system.rawValue == "system")
    }

    @Test func personaModeDefaultHasNoUnderscore() {
        #expect(PersonaMode.default_.rawValue == "default")
    }

    @Test func outputFormatMatchesOutputModeNames() {
        #expect(OutputFormat.chat.rawValue == "chat")
        #expect(OutputFormat.debug.rawValue == "debug")
    }
}

// MARK: - Model creation

@Suite("Model creation")
struct ModelCreationTests {
    @Test func projectDefaults() throws {
        let project = KodaiProject(title: "My Project")
        #expect(project.title == "My Project")
        #expect(project.status == .active)
        #expect(project.notes == "")
        #expect(project.sessions.isEmpty)
        #expect(project.tasks.isEmpty)
    }

    @Test func sessionDefaults() throws {
        let session = KodaiChatSession()
        #expect(session.title == "New chat")
        #expect(session.persona == .default_)
        #expect(session.format == .chat)
        #expect(session.project == nil)
        #expect(session.messages.isEmpty)
    }

    @Test func messageTokenEstimateAutoFilled() {
        let msg = KodaiChatMessage(role: .user, content: "Hello world!")
        // "Hello world!" = 12 bytes → 12/4 = 3
        #expect(msg.tokenEstimate == 3)
    }

    @Test func messageTokenEstimateOverride() {
        let msg = KodaiChatMessage(role: .assistant, content: "Hi", tokenEstimate: 42)
        #expect(msg.tokenEstimate == 42)
    }

    @Test func turnRecordAutoEstimates() {
        let turn = TurnRecord(
            userMessage: "Hello",
            assistantMessage: "World",
            systemPrompt: ""
        )
        #expect(turn.inputTokenEstimate >= 1)
        #expect(turn.outputTokenEstimate >= 1)
    }

    @Test func reminderDefaultsFired() {
        let reminder = KodaiReminder(title: "Follow up", scheduledAt: .now)
        #expect(reminder.fired == false)
    }

    @Test func taskDefaults() {
        let task = KodaiTask(title: "Write tests")
        #expect(task.status == .pending)
        #expect(task.priority == .medium)
        #expect(task.notes == "")
        #expect(task.dueDate == nil)
    }

    @Test func memoryEntryDefaults() {
        let entry = MemoryEntry(content: "User prefers Swift", type: .preference)
        #expect(entry.status == .active)
        #expect(entry.tags.isEmpty)
        #expect(entry.project == nil)
        #expect(entry.session == nil)
    }
}

// MARK: - Relationship wiring

@Suite("Relationship wiring")
struct RelationshipTests {
    @Test func sessionBelongsToProject() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = KodaiProject(title: "Kodai macOS")
        let session = KodaiChatSession(title: "Sprint 1")
        project.sessions.append(session)
        session.project = project
        context.insert(project)
        context.insert(session)
        try context.save()

        #expect(session.project?.title == "Kodai macOS")
        #expect(project.sessions.count == 1)
    }

    @Test func messagesAppendToSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let session = KodaiChatSession(title: "Test")
        let msg = KodaiChatMessage(role: .user, content: "Hello")
        session.messages.append(msg)
        msg.session = session
        context.insert(session)
        context.insert(msg)
        try context.save()

        #expect(session.messages.count == 1)
        #expect(session.messages.first?.content == "Hello")
    }

    @Test func turnRecordLinksToSessionViaSessionID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let session = KodaiChatSession(title: "Chat")
        context.insert(session)
        try context.save()

        let turn = TurnRecord(
            userMessage: "Ping",
            assistantMessage: "Pong",
            systemPrompt: "Be helpful",
            sessionID: session.id
        )
        context.insert(turn)
        try context.save()

        #expect(turn.sessionID == session.id)
    }

    @Test func toolCallLinksToTurn() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let turn = TurnRecord(
            userMessage: "Search for X",
            assistantMessage: "Found X",
            systemPrompt: ""
        )
        let call = ToolCall(toolName: "search", input: #"{"query":"X"}"#, outcome: .success)
        turn.toolCalls.append(call)
        call.turn = turn
        context.insert(turn)
        context.insert(call)
        try context.save()

        #expect(turn.toolCalls.count == 1)
        #expect(turn.toolCalls.first?.toolName == "search")
    }

    @Test func reminderLinksToTask() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let task = KodaiTask(title: "Ship v1")
        let reminder = KodaiReminder(title: "Check CI", scheduledAt: .now)
        task.reminders.append(reminder)
        reminder.task = task
        context.insert(task)
        context.insert(reminder)
        try context.save()

        #expect(task.reminders.count == 1)
        #expect(task.reminders.first?.title == "Check CI")
    }
}

// MARK: - MigrationHelper

@Suite("MigrationHelper")
struct MigrationHelperTests {
    @Test func migratesSessionMetadata() {
        let id = UUID()
        let legacy = LegacyChatSession(id: id, title: "Old chat")
        let session = MigrationHelper.migrate(legacy)

        #expect(session.id == id)
        #expect(session.title == "Old chat")
        #expect(session.persona == .default_)
        #expect(session.format == .chat)
        #expect(session.project == nil)
    }

    @Test func migratesKnownRoles() {
        let userMsg = LegacyChatMessage(role: "user", content: "Hi")
        let assistantMsg = LegacyChatMessage(role: "assistant", content: "Hello")

        #expect(MigrationHelper.migrate(userMsg).role == .user)
        #expect(MigrationHelper.migrate(assistantMsg).role == .assistant)
    }

    @Test func unknownRoleFallsBackToUser() {
        let msg = LegacyChatMessage(role: "bot", content: "??")
        #expect(MigrationHelper.migrate(msg).role == .user)
    }

    @Test func migratesAllMessages() {
        let legacy = LegacyChatSession(
            title: "Migration test",
            messages: [
                LegacyChatMessage(role: "user", content: "Q1"),
                LegacyChatMessage(role: "assistant", content: "A1"),
                LegacyChatMessage(role: "user", content: "Q2")
            ]
        )
        let session = MigrationHelper.migrate(legacy)
        #expect(session.messages.count == 3)
        #expect(session.messages[1].role == .assistant)
    }

    @Test func preservesMessageTimestamps() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let msg = LegacyChatMessage(role: "user", content: "Hi", createdAt: date)
        let migrated = MigrationHelper.migrate(msg)
        #expect(migrated.createdAt == date)
    }
}
