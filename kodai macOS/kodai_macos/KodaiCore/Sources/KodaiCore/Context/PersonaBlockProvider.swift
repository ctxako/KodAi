import Foundation

public struct PersonaBlockProvider: ContextBlockProvider, Sendable {
    public init() {}

    public func provide(for chat: KodaiChatSession, query: String) -> ContextBlock? {
        let personaText = Prompts.persona(for: chat.persona)
        let formatText = Prompts.format(for: chat.format)
        let content = "\(personaText)\n\n\(formatText)"
        return ContextBlock(
            kind: "persona",
            content: content,
            tokenEstimate: TokenEstimator.estimate(content),
            priority: 0
        )
    }
}
