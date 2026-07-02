import Foundation
import KodaiKernel
import llama

public nonisolated final class LlamaContextWrapper: @unchecked Sendable {
    public let modelURL: URL
    public let modelByteCount: Int
    public let contextSize: Int32

    private let model: OpaquePointer
    private let context: OpaquePointer
    private var sampler: UnsafeMutablePointer<llama_sampler>
    private let batchSize: Int
    private let chatTemplate: String?
    /// `<|tool_call_end|>` as a single vocab token, when the model has one.
    /// LFM2 emits this control token to close a tool call but doesn't mark it
    /// EOG, so we stop on it explicitly — otherwise the model runs on into
    /// trailing prose we'd only throw away. `nil` for models without the token.
    private let toolCallEndTokenID: llama_token?
    private let log = KodaiLog(category: "LlamaContext")
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

    public nonisolated init(
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
        guard let samplerChain = Self.makeSamplerChain(configuration.defaultSamplerKnobs, model: loadedModel) else {
            llama_free(loadedContext)
            llama_model_free(loadedModel)
            throw LocalModelRuntimeError.samplerCreateFailed
        }

        self.model = loadedModel
        self.context = loadedContext
        self.sampler = samplerChain
        self.chatTemplate = Self.chatTemplate(from: loadedModel)
        self.toolCallEndTokenID = Self.singleSpecialTokenID("<|tool_call_end|>", model: loadedModel)
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

    public nonisolated func requestCancellation() {
        cancellationLock.lock()
        cancellationRequested = true
        cancellationLock.unlock()
    }

    public nonisolated func applySamplerKnobs(_ knobs: SamplerKnobs) {
        guard let chain = Self.makeSamplerChain(knobs, model: model) else {
            log.event("sampler rebuild failed, keeping previous chain")
            return
        }
        llama_sampler_free(sampler)
        sampler = chain
    }

    private static func makeSamplerChain(
        _ knobs: SamplerKnobs,
        model: OpaquePointer
    ) -> UnsafeMutablePointer<llama_sampler>? {
        guard let chain = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            return nil
        }

        if knobs.repeatPenalty != 1.0 || knobs.frequencyPenalty != 0.0 || knobs.presencePenalty != 0.0 {
            llama_sampler_chain_add(
                chain,
                llama_sampler_init_penalties(128, knobs.repeatPenalty, knobs.frequencyPenalty, knobs.presencePenalty)
            )
        }

        // Grammar masks invalid continuations before any selection sampler
        // runs, so top-k/temp/dist (or greedy) choose among valid tokens only.
        // llama_sampler_init_grammar returns NULL on unparseable GBNF — drop
        // the constraint rather than poison the chain with a null sampler.
        if let grammar = knobs.grammar, !grammar.isEmpty {
            if let grammarSampler = llama_sampler_init_grammar(llama_model_get_vocab(model), grammar, "root") {
                llama_sampler_chain_add(chain, grammarSampler)
            } else {
                KodaiLog(category: "LlamaContext").event("grammar rejected by llama.cpp, sampling unconstrained")
            }
        }

        if knobs.deterministic {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
            return chain
        }

        llama_sampler_chain_add(chain, llama_sampler_init_top_k(Int32(max(1, knobs.topK))))
        if knobs.minP > 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_min_p(knobs.minP, 1))
        }
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(knobs.topP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(knobs.temperature))

        let seed = knobs.seed ?? UInt32.random(in: 0...UInt32.max)
        llama_sampler_chain_add(chain, llama_sampler_init_dist(seed))
        return chain
    }

    public nonisolated func tokenize(_ prompt: String) throws -> [llama_token] {
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
            true,   // add_special: prepend BOS
            true    // parse_special: the prompt we build contains real control
                    // tokens (<|im_start|>, <|im_end|>, …). They MUST be parsed
                    // as those tokens, not as literal "<", "|", "im_start" text —
                    // otherwise the model never sees turn boundaries and its
                    // trained tool-call behavior collapses into plain prose.
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

    public nonisolated var lastStopStringForLog: String? {
        lastStopString
    }

    public nonisolated func formatChatPrompt(
        messages: [KodaiRuntimeMessage],
        systemPrompt: String,
        assistantPrimer: String? = nil
    ) -> LlamaPromptBuildResult {
        let promptMessages = Self.recentPromptMessages(from: messages)
        let prompt = Self.formatChatMLPrompt(
            messages: promptMessages,
            systemMessage: systemPrompt,
            assistantPrimer: assistantPrimer
        )

        return LlamaPromptBuildResult(
            prompt: prompt,
            includedMessageCount: promptMessages.count,
            historyIncluded: promptMessages.count > 1
        )
    }

    public nonisolated func prefill(_ tokens: [llama_token]) throws {
        guard !tokens.isEmpty else {
            throw LocalModelRuntimeError.tokenizationFailed
        }

        llama_memory_clear(llama_get_memory(context), true)

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

    public nonisolated func decode(
        maxTokens: Int32,
        onDecision: (TokenDecision) -> Void,
        onText: (String, Int) -> Void
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
                _ = flushBufferedText(generatedTokenCount: Int(generatedTokenCount), onText: onText, lossy: true)
                log.event("generation cancelled")
                logRawOutputSummary(finishReason: .cancelled)
                return .cancelled
            }

            // Thermal pacing: when the device is hot, sleep briefly between tokens
            // to lower the sustained duty cycle. This actually slows generation on
            // .serious/.critical (on the background decode thread, never the main
            // thread) rather than only hinting at it in the prompt. The first token
            // is never paced so time-to-first-token stays responsive.
            if generatedTokenCount > 0 {
                switch ProcessInfo.processInfo.thermalState {
                case .serious: Thread.sleep(forTimeInterval: 0.012)
                case .critical: Thread.sleep(forTimeInterval: 0.030)
                default: break
                }
            }

            // llama_sampler_sample already accepts the sampled token into the
            // chain (see llama.h) — a second llama_sampler_accept here would
            // double-count it in the penalties window and advance a grammar
            // sampler twice, desyncing it from the actual output.
            let token = llama_sampler_sample(sampler, context, -1)
            let distribution = readTopAlternatives(sampledToken: token)

            #if DEBUG
            debugGeneratedTokenIDs.append(token)
            #endif

            let vocabulary = llama_model_get_vocab(model)
            // Stop on a real EOG token, or on `<|tool_call_end|>` — LFM2 closes a
            // tool call with the latter but doesn't mark it EOG, and everything
            // after it is throwaway prose for our one-call-per-turn flow.
            let isNativeEOG = llama_vocab_is_eog(vocabulary, token)
                || (toolCallEndTokenID.map { token == $0 } ?? false)
            let tokenIndex = Int(generatedTokenCount) + 1

            if isNativeEOG {
                _ = flushBufferedText(generatedTokenCount: tokenIndex, onText: onText, lossy: true)
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

            onDecision(
                TokenDecision(
                    step: tokenIndex - 1,
                    tokenID: token,
                    text: tokenText(token),
                    distribution: distribution
                )
            )

            let visibleCountBeforeAppend = debugVisibleYieldedCharacterCount
            let didTextualStop = appendToken(token, generatedTokenCount: tokenIndex, onText: onText)
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
                _ = flushBufferedText(generatedTokenCount: tokenIndex, onText: onText, lossy: true)
                throw LocalModelRuntimeError.decodeFailed(decodeResult)
            }
        }

        _ = flushBufferedText(generatedTokenCount: Int(generatedTokenCount), onText: onText, lossy: true)
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
        onText: (String, Int) -> Void
    ) -> Bool {
        utf8Buffer.append(contentsOf: tokenBytes(token))
        return flushBufferedText(generatedTokenCount: generatedTokenCount, onText: onText, lossy: false)
    }

    private func flushBufferedText(
        generatedTokenCount: Int,
        onText: (String, Int) -> Void,
        lossy: Bool
    ) -> Bool {
        let emitToken: (String) -> Void = { text in
            onText(text, generatedTokenCount)
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

    private func readTopAlternatives(sampledToken: llama_token, n: Int = 5) -> TokenDistribution {
        let vocab = llama_model_get_vocab(model)
        let nVocab = Int(llama_vocab_n_tokens(vocab))
        guard nVocab > 0, let logitsPtr = llama_get_logits_ith(context, -1) else { return .empty }
        let logits = UnsafeBufferPointer(start: logitsPtr, count: nVocab)

        var maxLogit: Float = -Float.greatestFiniteMagnitude
        var topN: [(id: Int32, logit: Float)] = []
        topN.reserveCapacity(n)
        for i in 0..<nVocab {
            let logit = logits[i]
            if logit > maxLogit { maxLogit = logit }

            if topN.count < n {
                topN.append((Int32(i), logit))
                if topN.count == n { topN.sort { $0.logit > $1.logit } }
            } else if logit > topN[n - 1].logit {
                topN[n - 1] = (Int32(i), logit)
                var j = n - 1
                while j > 0 && topN[j].logit > topN[j - 1].logit {
                    topN.swapAt(j, j - 1)
                    j -= 1
                }
            }
        }
        if topN.count < n { topN.sort { $0.logit > $1.logit } }

        var sumExp: Double = 0
        var shiftedLogitMoment: Double = 0
        for logit in logits {
            let shifted = Double(logit - maxLogit)
            let weight = Foundation.exp(shifted)
            sumExp += weight
            shiftedLogitMoment += weight * shifted
        }
        guard sumExp > 0 else { return .empty }
        let entropy = Float(Foundation.log(sumExp) - shiftedLogitMoment / sumExp)

        let selectedProbability: Float = {
            let index = Int(sampledToken)
            guard index >= 0, index < nVocab else { return 0 }
            return Float(Foundation.exp(Double(logits[index] - maxLogit)) / sumExp)
        }()

        let probabilities = topN.map {
            Float(Foundation.exp(Double($0.logit - maxLogit)) / sumExp)
        }
        let margin = probabilities.count >= 2 ? probabilities[0] - probabilities[1] : (probabilities.first ?? 0)

        var alternatives = zip(topN, probabilities).map { entry, probability in
            TokenAlternative(
                tokenID: entry.id,
                text: tokenText(entry.id),
                probability: probability,
                isSelected: entry.id == sampledToken
            )
        }

        if !alternatives.contains(where: { $0.isSelected }) {
            alternatives.append(
                TokenAlternative(
                    tokenID: sampledToken,
                    text: tokenText(sampledToken),
                    probability: selectedProbability,
                    isSelected: true
                )
            )
        }

        return TokenDistribution(
            alternatives: alternatives,
            selectedProbability: selectedProbability,
            entropy: entropy,
            margin: margin
        )
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

    /// Resolves `text` to its single vocab token id, or nil if the model
    /// tokenizes it into anything other than exactly one token (i.e. it isn't a
    /// known special token). `parse_special` so the marker maps to its control
    /// token; `add_special: false` so no BOS is prepended.
    private static func singleSpecialTokenID(_ text: String, model: OpaquePointer) -> llama_token? {
        let vocabulary = llama_model_get_vocab(model)
        var tokens = [llama_token](repeating: 0, count: 8)
        let count = llama_tokenize(
            vocabulary, text, Int32(text.utf8.count),
            &tokens, Int32(tokens.count),
            false,  // add_special
            true    // parse_special
        )
        guard count == 1 else { return nil }
        return tokens[0]
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

    private static func recentPromptMessages(from messages: [KodaiRuntimeMessage]) -> [KodaiRuntimeMessage] {
        Array(messages
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(6))
    }

    // Mirrors LFM2's own chat template exactly (`<|im_start|>{role}\n{content}<|im_end|>\n`,
    // then `<|im_start|>assistant\n` to open the turn). BOS is added by the
    // tokenizer (add_special). The trailing newline after `assistant` and the
    // absence of a newline before `<|im_end|>` are part of the trained format —
    // a 1.2B's tool-call reliability depends on getting this whitespace right.
    //
    // `assistantPrimer`, when set, is appended after the assistant marker so the
    // model continues *from* it instead of choosing how to open. The consumer
    // app primes `<|tool_call_start|>` to force a tool call — at 1.2B the model
    // otherwise refuses/narrates most of the time. Default nil = normal chat.
    private static func formatChatMLPrompt(
        messages: [KodaiRuntimeMessage],
        systemMessage: String,
        assistantPrimer: String? = nil
    ) -> String {
        var prompt = "<|im_start|>system\n\(systemMessage)<|im_end|>\n"

        for message in messages {
            prompt += "<|im_start|>\(message.role.rawValue)\n\(message.text)<|im_end|>\n"
        }

        prompt += "<|im_start|>assistant\n"
        if let assistantPrimer { prompt += assistantPrimer }
        return prompt
    }
}

// MARK: - Textual stop filter

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
        "<|im_start|>assistant",
        // LFM2 renders this special token as literal text; stopping here cuts
        // generation cleanly right after a tool call (one call per turn).
        "<|tool_call_end|>"
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
