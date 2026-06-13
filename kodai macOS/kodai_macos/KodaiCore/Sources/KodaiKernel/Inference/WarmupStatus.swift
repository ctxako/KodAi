import Foundation

public enum WarmupStatus: String, Codable, Equatable, Sendable {
    case initializingRuntime
    case allocatingContext
    case mappingWeights
    case compilingMetal
    case warmingTokenizer
    case ready
}
