//
//  LlamaRuntime.swift
//  kodAI_chatbot_dev
//
//  Created by OpenAI Codex on 6/6/26.
//

import Foundation
import KodaiKernel

actor LlamaRuntime {
    private let modelFileResolver: BundledModelFileResolver
    private let log = AppLog(category: "LlamaRuntime")
    init(modelFileResolver: BundledModelFileResolver = BundledModelFileResolver()) {
        self.modelFileResolver = modelFileResolver
    }

    func initialize(
        configuration: LocalModelConfiguration,
        onWarmupStatus: @Sendable (WarmupStatus) -> Void = { _ in }
    ) async throws -> LlamaContextWrapper {
        let modelURL = try modelFileResolver.resolve(configuration: configuration)
        try validateGGUFHeader(at: modelURL)

        let resourceValues = try modelURL.resourceValues(forKeys: [.fileSizeKey])
        let modelByteCount = resourceValues.fileSize ?? 0

        log.event("model load started path=\(modelURL.path)")
        let context = try LlamaContextWrapper(
            modelURL: modelURL,
            modelByteCount: modelByteCount,
            configuration: configuration,
            onWarmupStatus: onWarmupStatus
        )
        log.event("model load finished bytes=\(modelByteCount)")
        return context
    }

    func generate(
        messages: [ChatMessage],
        promptStack: ModelPromptStack,
        context: LlamaContextWrapper,
        configuration: LocalModelConfiguration,
        samplerKnobs: SamplerKnobs,
        continuation: AsyncThrowingStream<InferenceEvent, Error>.Continuation
    ) async throws -> GenerationFinishReason {
        try Task.checkCancellation()

        context.applySamplerKnobs(samplerKnobs)
        log.event("sampler knobs temp=\(samplerKnobs.temperature) topP=\(samplerKnobs.topP) topK=\(samplerKnobs.topK) repeat=\(samplerKnobs.repeatPenalty)")

        continuation.yield(.phase(.formattingPrompt))
        log.event("prompt formatting started")
        let promptBuildResult = context.formatChatPrompt(messages: messages, promptStack: promptStack)
        let formattedPrompt = promptBuildResult.prompt
        #if DEBUG
        log.event("raw formatted prompt sent to llama.cpp=\(formattedPrompt.debugDescription)")
        #endif

        let maxOutputTokens = Int32(max(1, samplerKnobs.maxOutputTokens))

        continuation.yield(.phase(.tokenizing))
        log.event("tokenization started")
        let promptTokens = try context.tokenize(formattedPrompt)
        log.event(
            "prompt messages=\(promptBuildResult.includedMessageCount) promptTokens=\(promptTokens.count) maxOutputTokens=\(maxOutputTokens) historyIncluded=\(promptBuildResult.historyIncluded)"
        )
        #if DEBUG
        log.event("first 20 prompt token ids=\(Array(promptTokens.prefix(20)))")
        #endif
        try Task.checkCancellation()

        continuation.yield(.phase(.prefilling))
        log.event("prefill started")
        try context.prefill(promptTokens)
        log.event("prefill finished")
        try Task.checkCancellation()

        continuation.yield(.phase(.decoding))
        log.event("decode started")
        try Task.checkCancellation()

        var yieldedCharacterCount = 0
        let finishReason = try context.decode(
            maxTokens: maxOutputTokens,
            onDecision: { decision in
                continuation.yield(.tokenDecision(decision))
            },
            onText: { chunk, generatedTokenCount in
                yieldedCharacterCount += chunk.count
                #if DEBUG
                log.event("yielding token chunk to stream chars=\(chunk.count) totalChars=\(yieldedCharacterCount) text=\(chunk.debugDescription)")
                #endif
                continuation.yield(.token(chunk, generatedTokenCount: generatedTokenCount))
            }
        )

        log.event("generation finish reason=\(finishReason.logValue)")
        log.event("finishReason=\(finishReason.logValue) stopString=\(context.lastStopStringForLog ?? "nil")")
        log.event("decode finished")

        if case .cancelled = finishReason {
            log.event("generation cancelled")
            throw CancellationError()
        }

        return finishReason
    }

    private func validateGGUFHeader(at url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        let header = try handle.read(upToCount: 4)
        guard header == Data([0x47, 0x47, 0x55, 0x46]) else {
            throw LocalModelRuntimeError.invalidGGUFHeader(url)
        }
    }
}
