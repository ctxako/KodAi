import Foundation

public enum GenerationFinishReason: Equatable, Sendable {
    case maxTokens
    case endOfGenerationToken
    case textualStopString
    case cancelled

    public var logValue: String {
        switch self {
        case .maxTokens:
            return "maxTokens"
        case .endOfGenerationToken:
            return "endOfGenerationToken"
        case .textualStopString:
            return "textualStopString"
        case .cancelled:
            return "cancelled"
        }
    }
}
