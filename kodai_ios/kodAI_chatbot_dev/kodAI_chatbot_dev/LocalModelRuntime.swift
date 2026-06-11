//
//  LocalModelRuntime.swift
//  kodAI_chatbot_dev
//
//  Created by OpenAI Codex on 6/6/26.
//

import Foundation

actor LocalModelRuntime {
    private let configuration: LocalModelConfiguration
    private let llamaRuntime: LlamaRuntime
    private let modelDownloader: ModelDownloader
    private let log = AppLog(category: "LocalModelRuntime")

    private var context: LlamaContextWrapper?
    private var generationTask: Task<Void, Never>?

    init(
        configuration: LocalModelConfiguration = .lfm2_5_1_2B_Instruct_Q4_K_M,
        llamaRuntime: LlamaRuntime = LlamaRuntime(),
        modelDownloader: ModelDownloader = ModelDownloader()
    ) {
        self.configuration = configuration
        self.llamaRuntime = llamaRuntime
        self.modelDownloader = modelDownloader
    }

    func generate(
        messages: [ChatMessage],
        promptStack: ModelPromptStack
    ) -> AsyncThrowingStream<InferenceEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                do {
                    try await self.run(messages: messages, promptStack: promptStack, continuation: continuation)
                } catch is CancellationError {
                    await self.logCancellation()
                    continuation.yield(.cancelled)
                    continuation.finish()
                } catch {
                    await self.logFailure(error)
                    continuation.yield(.phase(.failed))
                    continuation.finish(throwing: error)
                }
            }

            generationTask = task
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task {
                    await self.cancel()
                }
            }
        }
    }

    private func run(
        messages: [ChatMessage],
        promptStack: ModelPromptStack,
        continuation: AsyncThrowingStream<InferenceEvent, Error>.Continuation
    ) async throws {
        let context = try await loadContext(continuation: continuation)
        try Task.checkCancellation()

        log.event("model ready name=\(context.modelURL.lastPathComponent)")

        let finishReason = try await llamaRuntime.generate(
            messages: messages,
            promptStack: promptStack,
            context: context,
            configuration: configuration,
            continuation: continuation
        )

        continuation.yield(.phase(.flushingOutput))
        continuation.yield(.done(finishReason))
        continuation.finish()
        generationTask = nil
    }

    private func loadContext(
        continuation: AsyncThrowingStream<InferenceEvent, Error>.Continuation
    ) async throws -> LlamaContextWrapper {
        try await loadContextWithStatus { status in
            continuation.yield(.warmup(status))
        }
    }

    private func loadContextWithStatus(
        onStatus: @Sendable (WarmupStatus) -> Void
    ) async throws -> LlamaContextWrapper {
        if let context {
            return context
        }

        _ = try await modelDownloader.ensureDownloaded(configuration: configuration)
        try Task.checkCancellation()

        let loadedContext = try await llamaRuntime.initialize(configuration: configuration, onWarmupStatus: onStatus)
        context = loadedContext
        return loadedContext
    }

    func prewarm(onStatus: @Sendable (WarmupStatus) -> Void) async {
        do {
            _ = try await loadContextWithStatus(onStatus: onStatus)
        } catch {
            log.event("prewarm failed error=\(error.localizedDescription)")
        }
    }

    func cancel() {
        context?.requestCancellation()
        generationTask?.cancel()
        generationTask = nil
    }

    private func logCancellation() {
        log.event("generation cancelled")
        generationTask = nil
    }

    private func logFailure(_ error: Error) {
        log.event("generation failed error=\(error.localizedDescription)")
        generationTask = nil
    }
}

nonisolated struct LocalModelConfiguration: Sendable {
    let modelResourceName: String
    let modelResourceExtension: String
    let shortDisplayName: String
    let contextSize: Int32
    let maxGeneratedTokens: Int32
    let temperature: Float
    let topP: Float
    let batchSize: Int32
    let repeatPenalty: Float

    var expectedModelFileName: String {
        "\(modelResourceName).\(modelResourceExtension)"
    }

    nonisolated static let lfm2_5_1_2B_Instruct_Q4_K_M = LocalModelConfiguration(
        modelResourceName: "LFM2.5-1.2B-Instruct-Q4_K_M",
        modelResourceExtension: "gguf",
        shortDisplayName: "LFM2.5 1.2B",
        contextSize: 2_048,
        maxGeneratedTokens: 384,
        temperature: 0.45,
        topP: 0.92,
        batchSize: 64,
        repeatPenalty: 1.05
    )
}

nonisolated enum LocalModelRuntimeError: Error, LocalizedError, Sendable {
    case modelFileMissing(expectedFileName: String)
    case invalidGGUFHeader(URL)
    case llamaBackendUnavailable(modelFileName: String)
    case modelLoadFailed(modelFileName: String)
    case contextCreateFailed(modelFileName: String)
    case samplerCreateFailed
    case tokenizationFailed
    case promptTooLong(tokenCount: Int, contextSize: Int32)
    case decodeFailed(Int32)

    var errorDescription: String? {
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
