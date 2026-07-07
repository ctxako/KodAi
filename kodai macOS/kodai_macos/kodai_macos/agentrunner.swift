//
//  agentrunner.swift
//  kodai_macos
//
//  Multi-step agent loop for the Ollama engine: model calls a tool, reads
//  the real result, decides the next step — until it answers or the step
//  budget runs out. Tool calls come back natively from /api/chat (Ollama
//  applies the model's own tool template, no grammar prompting needed).
//  Older tool results are compacted to one-line digests between steps so a
//  long chain doesn't drown the context window — the ledger keeps every
//  verbatim result; compaction only trims what the model re-reads. Confirm-
//  gated tools suspend the loop on ConfirmBroker exactly like single-step
//  turns. Budget exhaustion ends with an honest hand-back, never a fake
//  completion. The FM engine keeps its native LanguageModelSession loop.
//

import Foundation
import KodaiCore

/// One tool the agent may call: Ollama-format schema + an executor closure.
/// The closure receives stringified arguments (the kernel's RawToolCall
/// convention) and returns the structured ground-truth result.
struct AgentToolSpec {
    let spec: OllamaToolSpec
    let run: @MainActor (_ arguments: [String: String]) async -> ToolResult
}

@MainActor
enum AgentRunner {

    struct Configuration {
        let model: String
        let stepBudget: Int
        let tools: [AgentToolSpec]
    }

    /// Runs the loop as an InferenceEvent stream so ChatViewModel consumes it
    /// exactly like a single-shot backend. `.toolActivity` events carry step
    /// digests for the transcript chips; `onCompletion` hands back the
    /// compacted message history to persist plus the last turn's real stats.
    static func stream(
        config: Configuration,
        systemInstructions: String,
        history: [OllamaChatMessage],
        userPrompt: String,
        onCompletion: @escaping @MainActor ([OllamaChatMessage], OllamaTurnStats?) -> Void
    ) -> AsyncStream<InferenceEvent> {
        let (asyncStream, continuation) = AsyncStream.makeStream(of: InferenceEvent.self)

        let task = Task { @MainActor in
            continuation.yield(.phase(.resolving))

            // Working transcript for this run; persisted (compacted) at the end.
            var working = history
            working.append(OllamaChatMessage(role: "user", content: userPrompt))

            let startedAt = Date()
            var finalText = ""
            var totalToolCalls = 0
            var lastStats: OllamaTurnStats?

            do {
            steps:
                for step in 1...max(config.stepBudget, 1) {
                    try Task.checkCancellation()
                    continuation.yield(.phase(step == 1 ? .prefilling : .decoding))

                    var messages = [OllamaChatMessage(role: "system", content: systemInstructions)]
                    messages += working

                    var accumulated = ""
                    var toolCalls: [OllamaToolCall] = []
                    var finalChunk: OllamaChunk?

                    for try await chunk in OllamaBackend.streamChat(
                        model: config.model,
                        messages: messages,
                        tools: config.tools.map(\.spec)
                    ) {
                        try Task.checkCancellation()
                        if !chunk.content.isEmpty {
                            accumulated += chunk.content
                            continuation.yield(.token(accumulated, generatedTokenCount: 0))
                        }
                        toolCalls += chunk.toolCalls
                        if chunk.done { finalChunk = chunk }
                    }

                    if let chunk = finalChunk {
                        lastStats = Self.stats(from: chunk, model: config.model, fallbackText: accumulated)
                    }

                    // No tool calls → this is the answer.
                    if toolCalls.isEmpty {
                        finalText = accumulated
                        working.append(OllamaChatMessage(role: "assistant", content: accumulated))
                        break steps
                    }

                    // Tool step: record the assistant's call, execute, feed truth back.
                    working.append(OllamaChatMessage(
                        role: "assistant",
                        content: accumulated,
                        toolCalls: toolCalls
                    ))

                    for call in toolCalls {
                        try Task.checkCancellation()
                        totalToolCalls += 1
                        continuation.yield(.toolActivity(ToolActivity(
                            tool: call.name, phase: .started, detail: Self.callDigest(call)
                        )))

                        let result: ToolResult
                        if let tool = config.tools.first(where: { $0.spec.name == call.name }) {
                            result = await tool.run(call.arguments)
                        } else {
                            result = .failure(tool: call.name, error: "unknown tool")
                        }

                        let digest = Self.resultDigest(call: call, result: result)
                        continuation.yield(.toolActivity(ToolActivity(
                            tool: call.name,
                            phase: result.status == .ok ? .succeeded : .failed,
                            detail: digest
                        )))

                        working.append(OllamaChatMessage(
                            role: "tool",
                            content: result.asContextJSON(),
                            toolName: call.name
                        ))
                    }

                    if step == config.stepBudget {
                        // Honest hand-back: the loop ran out before an answer.
                        finalText = Self.budgetExhaustedMessage(
                            budget: config.stepBudget,
                            lastAssistantText: accumulated
                        )
                        working.append(OllamaChatMessage(role: "assistant", content: finalText))
                        break steps
                    }

                    // Compact older tool results so the next step re-reads
                    // digests, not full payloads. The newest stays verbatim.
                    Self.compactToolResults(&working, keepVerbatim: 1)
                }

                let duration = max(Date().timeIntervalSince(startedAt), 0.001)
                let outputTokens = lastStats?.outputTokens
                    ?? max(1, Int(ceil(Double(finalText.count) / 4.0)))
                let promptTokens = lastStats?.promptTokens
                    ?? max(1, Int(ceil(Double(userPrompt.count + systemInstructions.count) / 4.0)))

                // Persist a fully-compacted history: future turns need the
                // conversation, not every file body the agent read.
                Self.compactToolResults(&working, keepVerbatim: 0)
                onCompletion(working, lastStats)

                continuation.yield(.completed(InferenceResult(
                    fullText: finalText.trimmingCharacters(in: .whitespacesAndNewlines),
                    promptTokensEst: promptTokens,
                    outputTokensEst: outputTokens,
                    duration: duration,
                    tokensPerSecond: lastStats?.tokensPerSecond
                )))
                continuation.yield(.phase(.completed))
                _ = totalToolCalls
            } catch is CancellationError {
                continuation.yield(.cancelled)
            } catch {
                continuation.yield(.error(error))
            }

            continuation.finish()
        }

        continuation.onTermination = { _ in task.cancel() }
        return asyncStream
    }

    // MARK: - Compaction

    /// Replaces tool-result payloads with their digest, keeping the newest
    /// `keepVerbatim` tool messages untouched. Deterministic truncation —
    /// no model calls spent on summarizing.
    static func compactToolResults(_ messages: inout [OllamaChatMessage], keepVerbatim: Int) {
        let toolIndices = messages.indices.filter { messages[$0].role == "tool" }
        guard toolIndices.count > keepVerbatim else { return }
        for index in toolIndices.dropLast(keepVerbatim)
        where messages[index].content.count > 220 {
            messages[index].content = String(messages[index].content.prefix(200))
                + "…\" — [compacted: full result already acted on]"
        }
    }

    // MARK: - Digests

    static func callDigest(_ call: OllamaToolCall) -> String {
        let primary = call.arguments["path"]
            ?? call.arguments["query"]
            ?? call.arguments["pattern"]
            ?? call.arguments["title"]
            ?? call.arguments.values.first
            ?? ""
        return String("\(call.name) \(primary)".prefix(90))
    }

    static func resultDigest(call: OllamaToolCall, result: ToolResult) -> String {
        if result.status == .error {
            return String("\(call.name) — \(result.fields["error"] ?? "failed")".prefix(110))
        }
        // Prefer the compact facts, never the payload body.
        let facts = ["path", "lines", "count", "action", "bytes"]
            .compactMap { key in result.fields[key].map { $0 } }
            .joined(separator: " · ")
        let summary = facts.isEmpty
            ? result.fields.first(where: { $0.key != "content" && $0.key != "matches" })?.value ?? "ok"
            : facts
        return String("\(call.name) — \(summary)".prefix(110))
    }

    static func budgetExhaustedMessage(budget: Int, lastAssistantText: String) -> String {
        var text = "I stopped after \(budget) tool steps without finishing."
        if !lastAssistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text += " Where I got to: \(lastAssistantText)"
        }
        text += "\n\nThe step log above shows everything I did. Tell me to continue and I'll pick up from there."
        return text
    }

    // MARK: - Stats

    private static func stats(from chunk: OllamaChunk, model: String, fallbackText: String) -> OllamaTurnStats {
        let outputTokens = chunk.evalCount ?? max(1, Int(ceil(Double(fallbackText.count) / 4.0)))
        let tps: Double
        if let evalNs = chunk.evalDurationNs, evalNs > 0, let count = chunk.evalCount {
            tps = Double(count) / (Double(evalNs) / 1_000_000_000)
        } else {
            tps = 0
        }
        return OllamaTurnStats(
            model: model,
            promptTokens: chunk.promptEvalCount ?? 0,
            outputTokens: outputTokens,
            tokensPerSecond: tps,
            loadSeconds: Double(chunk.loadDurationNs ?? 0) / 1_000_000_000,
            totalSeconds: Double(chunk.totalDurationNs ?? 0) / 1_000_000_000
        )
    }
}
