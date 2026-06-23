import Foundation
import KodaiKernel

public actor LocalModelRuntime {
    private let configuration: LocalModelConfiguration
    private let llamaRuntime: LlamaRuntime
    private let modelDownloader: ModelDownloader
    private let log = KodaiLog(category: "LocalModelRuntime")

    private var context: LlamaContextWrapper?
    private var generationTask: Task<Void, Never>?

    public init(
        configuration: LocalModelConfiguration = .lfm2_5_1_2B_Instruct_Q4_K_M,
        modelFileResolver: any ModelFileResolver,
        modelDownloader: ModelDownloader = ModelDownloader()
    ) {
        self.configuration = configuration
        self.llamaRuntime = LlamaRuntime(modelFileResolver: modelFileResolver)
        self.modelDownloader = modelDownloader
    }

    public func generate(
        messages: [KodaiRuntimeMessage],
        systemPrompt: String,
        samplerKnobs: SamplerKnobs
    ) -> AsyncThrowingStream<InferenceEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                do {
                    try await self.run(messages: messages, systemPrompt: systemPrompt, samplerKnobs: samplerKnobs, continuation: continuation)
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
        messages: [KodaiRuntimeMessage],
        systemPrompt: String,
        samplerKnobs: SamplerKnobs,
        continuation: AsyncThrowingStream<InferenceEvent, Error>.Continuation
    ) async throws {
        let context = try await loadContext(continuation: continuation)
        try Task.checkCancellation()

        log.event("model ready name=\(context.modelURL.lastPathComponent)")

        let finishReason = try await llamaRuntime.generate(
            messages: messages,
            systemPrompt: systemPrompt,
            context: context,
            configuration: configuration,
            samplerKnobs: samplerKnobs,
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

    public func prewarm(onStatus: @Sendable (WarmupStatus) -> Void) async {
        do {
            _ = try await loadContextWithStatus(onStatus: onStatus)
        } catch {
            log.event("prewarm failed error=\(error.localizedDescription)")
        }
    }

    public func cancel() {
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
