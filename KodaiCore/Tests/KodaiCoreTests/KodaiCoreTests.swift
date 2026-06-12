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
        KodaiStream.self,
        KodaiSummary.self,
        KodaiTask.self,
        TurnRecord.self,
        ActivityEvent.self,
        ToolCall.self,
        ModelPerformanceMetric.self
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

    @Test func characterCountVariantHasNoFloorOfOne() {
        #expect(TokenEstimator.estimate(characterCount: 0) == 0)
        #expect(TokenEstimator.estimate(characterCount: 3) == 0)
        #expect(TokenEstimator.estimate(characterCount: 100) == 25)
    }
}

// MARK: - Shared inference vocabulary

@Suite("Inference vocabulary")
struct InferenceVocabularyTests {
    @Test func phaseSupersetCoversIOSAndMacOSCases() {
        // iOS-originated phases
        let iosPhases: [InferencePhase] = [
            .idle, .checkingRuntimeState, .checkingLocalTime, .checkingWeather,
            .usingCachedWeather, .downloadingModel, .loadingModel, .formattingPrompt,
            .tokenizing, .prefilling, .decoding, .flushingOutput,
            .completed, .cancelled, .failed
        ]
        // macOS-originated phases
        let macPhases: [InferencePhase] = [.resolving, .initializing]
        for phase in iosPhases + macPhases {
            #expect(InferencePhase.allCases.contains(phase))
        }
    }

    @Test func phaseRawValuesAreStableForPersistedChats() throws {
        // iOS persists InferencePhase inside ChatMessage; raw values must not drift.
        #expect(InferencePhase.checkingRuntimeState.rawValue == "checkingRuntimeState")
        #expect(InferencePhase.flushingOutput.rawValue == "flushingOutput")
        let decoded = try JSONDecoder().decode(
            InferencePhase.self,
            from: Data("\"downloadingModel\"".utf8)
        )
        #expect(decoded == .downloadingModel)
    }

    @Test func eventCarriesIOSPayloads() {
        let events: [InferenceEvent] = [
            .warmup(.compilingMetal),
            .diagnostic("weather unavailable"),
            .token("hi", generatedTokenCount: 2),
            .done(.endOfGenerationToken),
            .cancelled
        ]
        if case .token(let text, let count) = events[2] {
            #expect(text == "hi")
            #expect(count == 2)
        } else {
            Issue.record("expected token event")
        }
    }

    @Test func finishReasonLogValues() {
        #expect(GenerationFinishReason.maxTokens.logValue == "maxTokens")
        #expect(GenerationFinishReason.endOfGenerationToken.logValue == "endOfGenerationToken")
        #expect(GenerationFinishReason.textualStopString.logValue == "textualStopString")
        #expect(GenerationFinishReason.cancelled.logValue == "cancelled")
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
        #expect(project.details == "")
        #expect(project.summary == nil)
        #expect(project.deadline == nil)
        #expect(project.sessions.isEmpty)
        #expect(project.tasks.isEmpty)
    }

    @Test func sessionDefaults() throws {
        let session = KodaiChatSession()
        #expect(session.title == "New chat")
        #expect(session.project == nil)
        #expect(session.stream == nil)
        #expect(session.summarizedThroughMessageID == nil)
        #expect(session.messages.isEmpty)
        #expect(session.summaries.isEmpty)
    }

    @Test func messageDefaults() {
        let msg = KodaiChatMessage(role: "user", content: "Hello world!")
        #expect(msg.role == "user")
        #expect(msg.content == "Hello world!")
        #expect(msg.session == nil)
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

    @Test func taskDefaults() {
        let task = KodaiTask(title: "Write tests")
        #expect(task.isCompleted == false)
        #expect(task.completedAt == nil)
        #expect(task.priority == .medium)
        #expect(task.notes == "")
        #expect(task.dueDate == nil)
    }

    @Test func summaryTokenCountAutoFilled() {
        let summary = KodaiSummary(kind: .session, content: String(repeating: "x", count: 100))
        #expect(summary.tokenCount == 25)
        #expect(summary.previousContent == nil)
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
        let msg = KodaiChatMessage(role: "user", content: "Hello")
        session.messages.append(msg)
        msg.session = session
        context.insert(session)
        context.insert(msg)
        try context.save()

        #expect(session.messages.count == 1)
        #expect(session.messages.first?.content == "Hello")
    }

    @Test func sessionBelongsToStream() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stream = KodaiStream(title: "Work")
        let session = KodaiChatSession(title: "Chat")
        stream.sessions.append(session)
        session.stream = stream
        context.insert(stream)
        context.insert(session)
        try context.save()

        #expect(session.stream?.title == "Work")
        #expect(stream.sessions.count == 1)
    }

    @Test func summaryLinksToSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let session = KodaiChatSession(title: "Chat")
        let summary = KodaiSummary(kind: .session, content: "Recap")
        session.summaries.append(summary)
        summary.session = session
        context.insert(session)
        context.insert(summary)
        try context.save()

        #expect(session.summaries.count == 1)
        #expect(session.summaries.first?.content == "Recap")
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
        #expect(session.project == nil)
    }

    @Test func migratesKnownRoles() {
        let userMsg = LegacyChatMessage(role: "user", content: "Hi")
        let assistantMsg = LegacyChatMessage(role: "assistant", content: "Hello")

        #expect(MigrationHelper.migrate(userMsg).role == "user")
        #expect(MigrationHelper.migrate(assistantMsg).role == "assistant")
    }

    @Test func unknownRoleFallsBackToUser() {
        let msg = LegacyChatMessage(role: "bot", content: "??")
        #expect(MigrationHelper.migrate(msg).role == "user")
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
        #expect(session.messages[1].role == "assistant")
    }

    @Test func preservesMessageTimestamps() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let msg = LegacyChatMessage(role: "user", content: "Hi", createdAt: date)
        let migrated = MigrationHelper.migrate(msg)
        #expect(migrated.createdAt == date)
    }
}
