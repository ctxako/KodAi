import Foundation

public struct PersonaBlockProvider: ContextBlockProvider, Sendable {
    public var persona: PersonaMode
    public var format: OutputFormat

    public init(persona: PersonaMode = .default_, format: OutputFormat = .chat) {
        self.persona = persona
        self.format = format
    }

    public func provide(for chat: KodaiChatSession, query: String) -> ContextBlock? {
        let personaText = Prompts.persona(for: persona)
        let formatText = Prompts.format(for: format)
        let content = "\(personaText)\n\n\(formatText)"
        return ContextBlock(
            kind: "persona",
            content: content,
            tokenEstimate: TokenEstimator.estimate(content),
            priority: 0
        )
    }
}
