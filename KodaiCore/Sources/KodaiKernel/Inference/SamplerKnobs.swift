import Foundation

public struct SamplerKnobs: Equatable, Sendable {
    // Core
    public var temperature: Float
    public var topP: Float
    public var topK: Int
    public var repeatPenalty: Float

    // Advanced
    public var minP: Float
    public var frequencyPenalty: Float
    public var presencePenalty: Float
    public var deterministic: Bool
    public var seed: UInt32?

    // Generation
    public var maxOutputTokens: Int

    /// GBNF grammar constraining generation (llama.cpp grammar sampler, root
    /// rule "root"). nil = unconstrained. Invalid GBNF is dropped at chain
    /// build time with a log, never a crash.
    public var grammar: String?

    public static let minTemperature: Float = 0.05

    public init(
        temperature: Float = 1.0,
        topP: Float = 1.0,
        topK: Int = 40,
        repeatPenalty: Float = 1.0,
        minP: Float = 0.0,
        frequencyPenalty: Float = 0.0,
        presencePenalty: Float = 0.0,
        deterministic: Bool = false,
        seed: UInt32? = nil,
        maxOutputTokens: Int = 384,
        grammar: String? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repeatPenalty = repeatPenalty
        self.minP = minP
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.deterministic = deterministic
        self.seed = seed
        self.maxOutputTokens = maxOutputTokens
        self.grammar = grammar
    }
}
