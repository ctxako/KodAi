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
        maxOutputTokens: Int = 384
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
    }
}
