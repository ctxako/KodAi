import Foundation
import Testing
import SwiftData
@testable import KodaiCore

// MARK: - Helpers

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

private struct FixedProvider: ContextBlockProvider {
    let block: ContextBlock
    func provide(for chat: KodaiChatSession, query: String) -> ContextBlock? { block }
}

// MARK: - Tests

@Suite("ContextAssembler")
struct ContextAssemblerTests {

    // Budget overflow excludes lowest-priority blocks (history first, then tasks).
    // Persona and time are in the never-drop set and must survive.
    @Test func budgetOverflowDropsLowestPriorityBlocks() {
        let providers: [any ContextBlockProvider] = [
            FixedProvider(block: ContextBlock(kind: "persona",  content: String(repeating: "a", count: 60),  tokenEstimate: 15, priority: 0)),
            FixedProvider(block: ContextBlock(kind: "time",     content: String(repeating: "b", count: 40),  tokenEstimate: 10, priority: 1)),
            FixedProvider(block: ContextBlock(kind: "history",  content: String(repeating: "c", count: 800), tokenEstimate: 200, priority: 10)),
        ]
        let assembler = ContextAssembler(budget: TokenBudget(total: 50))
        let (_, manifest) = assembler.assemble(for: KodaiChatSession(), userMessage: "test", providers: providers)

        #expect(manifest.blocks.first { $0.kind == "persona" }?.status == .included)
        #expect(manifest.blocks.first { $0.kind == "time" }?.status == .included)
        #expect(manifest.blocks.first { $0.kind == "history" }?.status == .excluded)
    }

    // A session without a project must not produce a project_summary block.
    @Test func emptyProjectYieldsNoProjectBlock() {
        let session = KodaiChatSession()
        let block = ProjectSummaryBlockProvider().provide(for: session, query: "test")
        #expect(block == nil)
    }

    // HistoryBlockProvider with maxMessages: 3 must keep the three most recent messages
    // and omit older ones.
    @Test func historyTruncationKeepsMostRecentMessages() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let now = Date()

        let session = KodaiChatSession()
        context.insert(session)

        let fixtures: [(String, String, TimeInterval)] = [
            ("user",      "Message 1 old",    -4),
            ("assistant", "Message 2 old",    -3),
            ("user",      "Message 3 mid",    -2),
            ("assistant", "Message 4 recent", -1),
            ("user",      "Message 5 newest",  0),
        ]
        for (role, content, offset) in fixtures {
            let msg = KodaiChatMessage(role: role, content: content, createdAt: now.addingTimeInterval(offset))
            context.insert(msg)
            msg.session = session
            session.messages.append(msg)
        }
        try context.save()

        let block = try #require(HistoryBlockProvider(maxMessages: 3).provide(for: session, query: "test"))

        #expect(!block.content.contains("Message 1 old"))
        #expect(!block.content.contains("Message 2 old"))
        #expect(block.content.contains("Message 3 mid"))
        #expect(block.content.contains("Message 4 recent"))
        #expect(block.content.contains("Message 5 newest"))
    }

    // When all blocks fit within budget, the manifest must mark every block as .included
    // and report accurate token totals.
    @Test func manifestAccuratelyReflectsAssembly() {
        let providers: [any ContextBlockProvider] = [
            FixedProvider(block: ContextBlock(kind: "persona",         content: "persona",  tokenEstimate: 10, priority: 0)),
            FixedProvider(block: ContextBlock(kind: "time",            content: "time",     tokenEstimate: 10, priority: 1)),
            FixedProvider(block: ContextBlock(kind: "project_summary", content: "project",  tokenEstimate: 10, priority: 3)),
            FixedProvider(block: ContextBlock(kind: "active_tasks",    content: "tasks",    tokenEstimate: 10, priority: 4)),
            FixedProvider(block: ContextBlock(kind: "history",         content: "history",  tokenEstimate: 10, priority: 10)),
        ]
        let assembler = ContextAssembler(budget: TokenBudget(total: 100))
        let (prompt, manifest) = assembler.assemble(for: KodaiChatSession(), userMessage: "test", providers: providers)

        #expect(manifest.blocks.count == 5)
        #expect(manifest.blocks.allSatisfy { $0.status == .included })
        #expect(manifest.totalTokens == 50)
        #expect(manifest.budgetLimit == 100)
        #expect(prompt.contains("persona"))
        #expect(prompt.contains("history"))
    }
}

@Suite("Context value types")
struct ContextValueTypeTests {

    // iOS uses ContextBlock as a plain value type for glass-box display;
    // it must round-trip through Codable and compare by value.
    @Test func contextBlockCodableRoundTrip() throws {
        let block = ContextBlock(kind: "Local context", content: "Injected into latest prompt", tokenEstimate: 42, priority: 4, sourceID: UUID())
        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(ContextBlock.self, from: data)
        #expect(decoded == block)
    }

    @Test func contextManifestRepresentsSmallBlockSet() throws {
        let manifest = ContextManifest(
            blocks: [
                ContextBlockRecord(kind: "persona", tokenEstimate: 10, status: .included),
                ContextBlockRecord(kind: "history", tokenEstimate: 200, status: .truncated, reason: "over budget"),
            ],
            totalTokens: 210,
            budgetLimit: 220
        )
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(ContextManifest.self, from: data)
        #expect(decoded.blocks.count == 2)
        #expect(decoded.blocks[1].status == .truncated)
        #expect(decoded.totalTokens == 210)
    }

    // The estimates feeding the iOS glass box must stay stable.
    @Test func tokenEstimatesAreStable() {
        #expect(TokenEstimator.estimate("abcdefgh") == 2)
        #expect(TokenEstimator.estimate("") == 1)
        #expect(TokenEstimator.estimate(characterCount: 0) == 0)
        #expect(TokenEstimator.estimate(characterCount: 100) == 25)
    }
}
