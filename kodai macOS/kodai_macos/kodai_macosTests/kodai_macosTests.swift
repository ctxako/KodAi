//
//  kodai_macosTests.swift
//  kodai_macosTests
//
//  Created by Charles Thomas Xavier Austin III on 6/9/26.
//

import Testing
import SwiftData
import KodaiCore
@testable import kodai_macos

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
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: KodaiChatSession.self,
            KodaiChatMessage.self,
            configurations: configuration
        )
    }
}
