import Foundation

public nonisolated struct LocalModelConfiguration: Sendable {
    public let modelResourceName: String
    public let modelResourceExtension: String
    public let shortDisplayName: String
    public let contextSize: Int32
    public let maxGeneratedTokens: Int32
    public let temperature: Float
    public let topP: Float
    public let topK: Int32
    public let batchSize: Int32
    public let repeatPenalty: Float

    public var expectedModelFileName: String {
        "\(modelResourceName).\(modelResourceExtension)"
    }

    public var defaultSamplerKnobs: SamplerKnobs {
        SamplerKnobs(
            temperature: temperature,
            topP: topP,
            topK: Int(topK),
            repeatPenalty: repeatPenalty,
            maxOutputTokens: Int(maxGeneratedTokens)
        )
    }

    public init(
        modelResourceName: String,
        modelResourceExtension: String,
        shortDisplayName: String,
        contextSize: Int32,
        maxGeneratedTokens: Int32,
        temperature: Float,
        topP: Float,
        topK: Int32,
        batchSize: Int32,
        repeatPenalty: Float
    ) {
        self.modelResourceName = modelResourceName
        self.modelResourceExtension = modelResourceExtension
        self.shortDisplayName = shortDisplayName
        self.contextSize = contextSize
        self.maxGeneratedTokens = maxGeneratedTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.batchSize = batchSize
        self.repeatPenalty = repeatPenalty
    }

    public nonisolated static let lfm2_5_1_2B_Instruct_Q4_K_M = LocalModelConfiguration(
        modelResourceName: "LFM2.5-1.2B-Instruct-Q4_K_M",
        modelResourceExtension: "gguf",
        shortDisplayName: "LFM2.5 1.2B",
        contextSize: 2_048,
        maxGeneratedTokens: 384,
        temperature: 0.45,
        topP: 0.92,
        topK: 40,
        batchSize: 64,
        repeatPenalty: 1.05
    )
}

public nonisolated enum LocalModelRuntimeError: Error, LocalizedError, Sendable {
    case modelFileMissing(expectedFileName: String)
    case invalidGGUFHeader(URL)
    case llamaBackendUnavailable(modelFileName: String)
    case modelLoadFailed(modelFileName: String)
    case contextCreateFailed(modelFileName: String)
    case samplerCreateFailed
    case tokenizationFailed
    case promptTooLong(tokenCount: Int, contextSize: Int32)
    case decodeFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .modelFileMissing(let expectedFileName):
            return "Missing model file: \(expectedFileName)"
        case .invalidGGUFHeader(let url):
            return "Model file is not a valid GGUF: \(url.lastPathComponent)"
        case .llamaBackendUnavailable(let modelFileName):
            return "llama.cpp backend is not wired yet for \(modelFileName)"
        case .modelLoadFailed(let modelFileName):
            return "Failed to load model: \(modelFileName)"
        case .contextCreateFailed(let modelFileName):
            return "Failed to create llama context for \(modelFileName)"
        case .samplerCreateFailed:
            return "Failed to create llama sampler"
        case .tokenizationFailed:
            return "Failed to tokenize prompt"
        case .promptTooLong(let tokenCount, let contextSize):
            return "Prompt has \(tokenCount) tokens, which exceeds context size \(contextSize)"
        case .decodeFailed(let code):
            return "llama_decode returned \(code)"
        }
    }
}
