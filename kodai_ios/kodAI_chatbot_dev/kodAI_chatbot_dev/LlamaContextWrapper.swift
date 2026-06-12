//
//  LlamaContextWrapper.swift
//  kodAI_chatbot_dev
//
//  Created by OpenAI Codex on 6/6/26.
//

import Foundation
import KodaiKernel
import llama

nonisolated final class LlamaContextWrapper: @unchecked Sendable {
    let modelURL: URL
    let modelByteCount: Int
    let contextSize: Int32

    private let model: OpaquePointer
    private let context: OpaquePointer
    private let sampler: UnsafeMutablePointer<llama_sampler>
    private let batchSize: Int
    private let chatTemplate: String?
    private let log = AppLog(category: "LlamaContext")
    private let cancellationLock = NSLock()
    private var cancellationRequested = false
    private var utf8Buffer = Data()
    private var stopFilter = TextualStopFilter()
    private var lastStopString: String?
    private var debugYieldedCharacterCount = 0
    private var debugVisibleYieldedCharacterCount = 0
    #if DEBUG
    private var debugGeneratedTokenIDs: [llama_token] = []
    private var debugRawDecodedText = ""
    private var debugFilteredText = ""
    private var debugLastStopString: String?
    #endif

    nonisolated init(
        modelURL: URL,
        modelByteCount: Int,
        configuration: LocalModelConfiguration,
        onWarmupStatus: @Sendable (WarmupStatus) -> Void = { _ in }
    ) throws {
        self.modelURL = modelURL
        self.modelByteCount = modelByteCount
        self.contextSize = configuration.contextSize
        self.batchSize = max(1, Int(configuration.batchSize))

        onWarmupStatus(.initializingRuntime)
        llama_backend_init()

        onWarmupStatus(.allocatingContext)
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 99

        onWarmupStatus(.mappingWeights)
        guard let loadedModel = llama_model_load_from_file(modelURL.path, modelParams) else {
            throw LocalModelRuntimeError.modelLoadFailed(modelFileName: modelURL.lastPathComponent)
        }

        onWarmupStatus(.compilingMetal)
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(configuration.contextSize)
        contextParams.n_batch = UInt32(max(configuration.batchSize, 1))
        contextParams.n_ubatch = UInt32(max(configuration.batchSize, 1))
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let threadCount = Int32(max(2, min(4, processorCount - 1)))
        contextParams.n_threads = threadCount
        contextParams.n_threads_batch = threadCount

        guard let loadedContext = llama_init_from_model(loadedModel, contextParams) else {
            llama_model_free(loadedModel)
            throw LocalModelRuntimeError.contextCreateFailed(modelFileName: modelURL.lastPathComponent)
        }

        onWarmupStatus(.warmingTokenizer)
        guard let samplerChain = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            llama_free(loadedContext)
            llama_model_free(loadedModel)
            throw LocalModelRuntimeError.samplerCreateFailed
        }

        llama_sampler_chain_add(samplerChain, llama_sampler_init_top_p(configuration.topP, 1))
        llama_sampler_chain_add(samplerChain, llama_sampler_init_temp(configuration.temperature))
        if configuration.repeatPenalty != 1.0 {
            llama_sampler_chain_add(
                samplerChain,
                llama_sampler_init_penalties(128, configuration.repeatPenalty, 0.0, 0.0)
            )
        }
        llama_sampler_chain_add(samplerChain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

        self.model = loadedModel
        self.context = loadedContext
        self.sampler = samplerChain
        self.chatTemplate = Self.chatTemplate(from: loadedModel)
        _ = llama_model_get_vocab(loadedModel)
        onWarmupStatus(.ready)

        if chatTemplate != nil {
            log.event("chat template found")
        } else {
            log.event("chat template missing using fallback")
        }
    }

    deinit {
        llama_sampler_free(sampler)
        llama_free(context)
        llama_model_free(model)
        llama_backend_free()
    }

    nonisolated func requestCancellation() {
        cancellationLock.lock()
        cancellationRequested = true
        cancellationLock.unlock()
    }

    nonisolated func tokenize(_ prompt: String) throws -> [llama_token] {
        resetForGeneration()

        let vocabulary = llama_model_get_vocab(model)
        let capacity = max(prompt.utf8.count + 64, 256)
        var tokens = [llama_token](repeating: 0, count: capacity)
        let tokenCount = llama_tokenize(
            vocabulary,
            prompt,
            Int32(prompt.utf8.count),
            &tokens,
            Int32(tokens.count),
            true,
            false
        )

        guard tokenCount > 0 else {
            throw LocalModelRuntimeError.tokenizationFailed
        }

        let result = Array(tokens.prefix(Int(tokenCount)))
        guard result.count < Int(contextSize) else {
            throw LocalModelRuntimeError.promptTooLong(
                tokenCount: result.count,
                contextSize: contextSize
            )
        }
        return result
    }

    nonisolated var lastStopStringForLog: String? {
        lastStopString
    }

    nonisolated func formatChatPrompt(
        messages: [ChatMessage],
        promptStack: ModelPromptStack
    ) -> LlamaPromptBuildResult {
        let promptMessages = Self.recentPromptMessages(from: messages)
        // Normal chat inference uses only the compact core prompt plus the selected assistant mode.
        let prompt = Self.formatChatMLPrompt(messages: promptMessages, systemMessage: promptStack.runtimeSystemPrompt)

        return LlamaPromptBuildResult(
            prompt: prompt,
            includedMessageCount: promptMessages.count,
            historyIncluded: promptMessages.count > 1
        )
    }

    nonisolated func prefill(_ tokens: [llama_token]) throws {
        guard !tokens.isEmpty else {
            throw LocalModelRuntimeError.tokenizationFailed
        }

        llama_kv_cache_clear(context)

        var cursor = 0
        while cursor < tokens.count {
            if isCancellationRequested {
                log.event("generation cancelled")
                throw CancellationError()
            }

            let end = min(cursor + batchSize, tokens.count)
            var chunk = Array(tokens[cursor..<end])
            let decodeResult = chunk.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress!, Int32(buffer.count)))
            }

            guard decodeResult == 0 else {
                throw LocalModelRuntimeError.decodeFailed(decodeResult)
            }

            cursor = end
        }
    }

    nonisolated func decode(
        maxTokens: Int32,
        onToken: (String, Int) -> Void
    ) throws -> GenerationFinishReason {
        var generatedTokenCount: Int32 = 0
        utf8Buffer.removeAll(keepingCapacity: true)
        debugYieldedCharacterCount = 0
        debugVisibleYieldedCharacterCount = 0
        #if DEBUG
        debugGeneratedTokenIDs.removeAll(keepingCapacity: true)
        debugRawDecodedText.removeAll(keepingCapacity: true)
        debugFilteredText.removeAll(keepingCapacity: true)
        debugLastStopString = nil
        #endif

        while generatedTokenCount < maxTokens {
            if isCancellationRequested {
                _ = flushBufferedText(generatedTokenCount: Int(generatedTokenCount), onToken: onToken, lossy: true)
                log.event("generation cancelled")
                logRawOutputSummary(finishReason: .cancelled)
                return .cancelled
            }

            let token = llama_sampler_sample(sampler, context, -1)
            llama_sampler_accept(sampler, token)

            #if DEBUG
            debugGeneratedTokenIDs.append(token)
            #endif

            let vocabulary = llama_model_get_vocab(model)
            let isNativeEOG = llama_vocab_is_eog(vocabulary, token)
            let tokenIndex = Int(generatedTokenCount) + 1

            if isNativeEOG {
                _ = flushBufferedText(generatedTokenCount: tokenIndex, onToken: onToken, lossy: true)
                logDecodeDiagnostic(
                    tokenIndex: tokenIndex,
                    token: token,
                    isNativeEOG: true,
                    didTextualStop: false
                )
                if debugVisibleYieldedCharacterCount == 0 {
                    log.event("EOG fired before any visible user-facing text was yielded")
                }
                logRawOutputSummary(finishReason: .endOfGenerationToken)
                return .endOfGenerationToken
            }

            let visibleCountBeforeAppend = debugVisibleYieldedCharacterCount
            let didTextualStop = appendToken(token, generatedTokenCount: tokenIndex, onToken: onToken)
            if tokenIndex == 1 || (tokenIndex <= 3 && visibleCountBeforeAppend == 0) {
                logDecodeDiagnostic(
                    tokenIndex: tokenIndex,
                    token: token,
                    isNativeEOG: false,
                    didTextualStop: didTextualStop
                )
            }

            if didTextualStop {
                logRawOutputSummary(finishReason: .textualStopString)
                return .textualStopString
            }

            generatedTokenCount += 1

            var nextToken = token
            let decodeResult = llama_decode(context, llama_batch_get_one(&nextToken, 1))
            guard decodeResult == 0 else {
                _ = flushBufferedText(generatedTokenCount: tokenIndex, onToken: onToken, lossy: true)
                throw LocalModelRuntimeError.decodeFailed(decodeResult)
            }
        }

        _ = flushBufferedText(generatedTokenCount: Int(generatedTokenCount), onToken: onToken, lossy: true)
        logRawOutputSummary(finishReason: .maxTokens)
        return .maxTokens
    }

    private var isCancellationRequested: Bool {
        cancellationLock.lock()
        let value = cancellationRequested
        cancellationLock.unlock()
        return value
    }

    private func resetForGeneration() {
        cancellationLock.lock()
        cancellationRequested = false
        cancellationLock.unlock()
        utf8Buffer.removeAll(keepingCapacity: true)
        stopFilter.reset()
        lastStopString = nil
        debugYieldedCharacterCount = 0
        debugVisibleYieldedCharacterCount = 0
        #if DEBUG
        debugGeneratedTokenIDs.removeAll(keepingCapacity: true)
        debugRawDecodedText.removeAll(keepingCapacity: true)
        debugFilteredText.removeAll(keepingCapacity: true)
        debugLastStopString = nil
        #endif
        llama_sampler_reset(sampler)
    }

    private func appendToken(
        _ token: llama_token,
        generatedTokenCount: Int,
        onToken: (String, Int) -> Void
    ) -> Bool {
        utf8Buffer.append(contentsOf: tokenBytes(token))
        return flushBufferedText(generatedTokenCount: generatedTokenCount, onToken: onToken, lossy: false)
    }

    private func flushBufferedText(
        generatedTokenCount: Int,
        onToken: (String, Int) -> Void,
        lossy: Bool
    ) -> Bool {
        let emitToken: (String) -> Void = { text in
            onToken(text, generatedTokenCount)
        }

        let result: TextualStopFilterResult
        if utf8Buffer.isEmpty {
            result = stopFilter.flushRemaining(onToken: emitToken)
        } else if let text = String(data: utf8Buffer, encoding: .utf8) {
            #if DEBUG
            debugRawDecodedText += text
            log.event("raw decoded before stop filtering text=\(debugEscaped(text))")
            #endif
            utf8Buffer.removeAll(keepingCapacity: true)
            result = stopFilter.append(text, onToken: emitToken)
        } else if lossy {
            let text = String(decoding: utf8Buffer, as: UTF8.self)
            #if DEBUG
            debugRawDecodedText += text
            log.event("raw decoded before stop filtering lossy=true text=\(debugEscaped(text))")
            #endif
            utf8Buffer.removeAll(keepingCapacity: true)
            result = stopFilter.append(text, onToken: emitToken)
        } else {
            return false
        }

        recordYieldedText(result.emittedText)
        #if DEBUG
        if !result.emittedText.isEmpty {
            debugFilteredText += result.emittedText
            log.event("decoded after stop filtering emitted=\(debugEscaped(result.emittedText))")
        }
        if result.didStop {
            debugLastStopString = result.stopString
        }
        #endif
        if let stopString = result.stopString {
            lastStopString = stopString
            #if DEBUG
            log.event(
                "textual stop fired stopString=\(debugEscaped(stopString)) pending=\(debugEscaped(result.pendingAtStop)) yieldedChars=\(debugYieldedCharacterCount)"
            )
            if debugVisibleYieldedCharacterCount == 0 {
                log.event("textual stop fired before any visible user-facing text was yielded")
            }
            #endif
        }

        return result.didStop
    }

    private func tokenBytes(_ token: llama_token) -> [UInt8] {
        let vocabulary = llama_model_get_vocab(model)
        var buffer = [CChar](repeating: 0, count: 64)
        let byteCount = llama_token_to_piece(
            vocabulary,
            token,
            &buffer,
            Int32(buffer.count),
            0,
            false
        )

        if byteCount >= 0 {
            return buffer.prefix(Int(byteCount)).map { UInt8(bitPattern: $0) }
        }

        let requiredCount = Int(-byteCount)
        buffer = [CChar](repeating: 0, count: requiredCount)
        let retryCount = llama_token_to_piece(
            vocabulary,
            token,
            &buffer,
            Int32(buffer.count),
            0,
            false
        )

        guard retryCount > 0 else { return [] }
        return buffer.prefix(Int(retryCount)).map { UInt8(bitPattern: $0) }
    }

    private func tokenText(_ token: llama_token) -> String {
        String(decoding: tokenBytes(token), as: UTF8.self)
    }

    private func recordYieldedText(_ text: String) {
        guard !text.isEmpty else { return }
        debugYieldedCharacterCount += text.count
        debugVisibleYieldedCharacterCount += text
            .filter { !$0.isWhitespace && !$0.isNewline }
            .count
        #if DEBUG
        log.event("yielded to UI chars=\(text.count) totalChars=\(debugYieldedCharacterCount) text=\(debugEscaped(text))")
        #endif
    }

    private func debugEscaped(_ text: String) -> String {
        text.debugDescription
    }

    private func logDecodeDiagnostic(
        tokenIndex: Int,
        token: llama_token,
        isNativeEOG: Bool,
        didTextualStop: Bool
    ) {
        #if DEBUG
        log.event(
            "decode token[\(tokenIndex)] id=\(token) piece=\(debugEscaped(tokenText(token))) nativeEOG=\(isNativeEOG) textualStop=\(didTextualStop) visibleChars=\(debugVisibleYieldedCharacterCount)"
        )
        #endif
    }

    private func logRawOutputSummary(finishReason: GenerationFinishReason) {
        #if DEBUG
        log.event("generated token ids=\(debugGeneratedTokenIDs)")
        log.event("decoded text before stop filtering=\(debugEscaped(debugRawDecodedText))")
        log.event("decoded text after stop filtering=\(debugEscaped(debugFilteredText))")
        let stopString = debugLastStopString.map(debugEscaped) ?? "nil"
        log.event("finish reason=\(finishReason.logValue) stopString=\(stopString) finalChars=\(debugFilteredText.count)")
        #else
        log.event("final assistant text length=\(debugYieldedCharacterCount)")
        #endif
    }

    private static func chatTemplate(from model: OpaquePointer) -> String? {
        if let templatePointer = llama_model_chat_template(model, nil) {
            let template = String(cString: templatePointer)
            if !template.isEmpty {
                return template
            }
        }

        return metadataString(from: model, key: "tokenizer.chat_template")
    }

    private static func metadataString(from model: OpaquePointer, key: String) -> String? {
        let byteCount = key.withCString { keyPointer in
            llama_model_meta_val_str(model, keyPointer, nil, 0)
        }

        guard byteCount > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: Int(byteCount) + 1)
        let writtenCount = key.withCString { keyPointer in
            llama_model_meta_val_str(model, keyPointer, &buffer, buffer.count)
        }

        guard writtenCount > 0 else { return nil }

        let value = String(cString: buffer)
        return value.isEmpty ? nil : value
    }

    private static func recentPromptMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        Array(messages
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(6))
    }

    private static func formatChatMLPrompt(messages: [ChatMessage], systemMessage: String) -> String {
        var prompt = """
        <|im_start|>system
        \(systemMessage)
        <|im_end|>

        """

        for message in messages {
            prompt += """
            <|im_start|>\(message.role.rawValue)
            \(message.text)
            <|im_end|>

            """
        }

        prompt += "<|im_start|>assistant"
        return prompt
    }
}

nonisolated struct LlamaPromptBuildResult: Sendable {
    let prompt: String
    let includedMessageCount: Int
    let historyIncluded: Bool
}

// GenerationFinishReason now lives in KodaiKernel.

nonisolated private struct TextualStopFilterResult {
    let didStop: Bool
    let stopString: String?
    let pendingAtStop: String
    let emittedText: String
}

nonisolated private struct TextualStopMatch {
    let stopString: String
    let range: Range<String.Index>
}

nonisolated private struct TextualStopFilter {
    private static let stopStrings = [
        "<|im_end|>",
        "<|im_end|",
        "<|endoftext|>",
        "</s>",
        "User:",
        "Assistant:",
        "<|im_start|>user",
        "<|im_start|>assistant"
    ]

    private let pendingCharacterCount = TextualStopFilter.stopStrings.map(\.count).max() ?? 0
    private var pending = ""
    private var didStop = false

    mutating func reset() {
        pending.removeAll(keepingCapacity: true)
        didStop = false
    }

    mutating func append(_ text: String, onToken: (String) -> Void) -> TextualStopFilterResult {
        guard !didStop else {
            return TextualStopFilterResult(
                didStop: true,
                stopString: nil,
                pendingAtStop: pending,
                emittedText: ""
            )
        }

        pending += text

        if let stopMatch = firstStopMatch(in: pending) {
            let pendingAtStop = pending
            let output = String(pending[..<stopMatch.range.lowerBound])
            emit(output, onToken: onToken)
            pending.removeAll(keepingCapacity: true)
            didStop = true
            return TextualStopFilterResult(
                didStop: true,
                stopString: stopMatch.stopString,
                pendingAtStop: pendingAtStop,
                emittedText: output
            )
        }

        var emittedText = ""
        let safeCharacterCount = pending.count - max(pendingCharacterCount - 1, 0)
        if safeCharacterCount > 0 {
            let safeEndIndex = pending.index(pending.startIndex, offsetBy: safeCharacterCount)
            let output = String(pending[..<safeEndIndex])
            pending = String(pending[safeEndIndex...])
            emit(output, onToken: onToken)
            emittedText = output
        }

        return TextualStopFilterResult(
            didStop: false,
            stopString: nil,
            pendingAtStop: "",
            emittedText: emittedText
        )
    }

    mutating func flushRemaining(onToken: (String) -> Void) -> TextualStopFilterResult {
        guard !didStop else {
            return TextualStopFilterResult(
                didStop: true,
                stopString: nil,
                pendingAtStop: pending,
                emittedText: ""
            )
        }

        if let stopMatch = firstStopMatch(in: pending) {
            let pendingAtStop = pending
            let output = String(pending[..<stopMatch.range.lowerBound])
            emit(output, onToken: onToken)
            pending.removeAll(keepingCapacity: true)
            didStop = true
            return TextualStopFilterResult(
                didStop: true,
                stopString: stopMatch.stopString,
                pendingAtStop: pendingAtStop,
                emittedText: output
            )
        }

        let output = pending
        emit(pending, onToken: onToken)
        pending.removeAll(keepingCapacity: true)
        return TextualStopFilterResult(
            didStop: false,
            stopString: nil,
            pendingAtStop: "",
            emittedText: output
        )
    }

    private func firstStopMatch(in text: String) -> TextualStopMatch? {
        Self.stopStrings
            .compactMap { stopString in
                text.range(of: stopString).map {
                    TextualStopMatch(stopString: stopString, range: $0)
                }
            }
            .min { $0.range.lowerBound < $1.range.lowerBound }
    }

    private func emit(_ text: String, onToken: (String) -> Void) {
        if !text.isEmpty {
            onToken(text)
        }
    }
}
