import Foundation
import FoundationModels
import KodaiBenchKit

@available(macOS 26.0, *)
struct AppleModelRunner {
    func run(
        prompts: [BenchPrompt],
        experimentId: String,
        device: String,
        log: (@Sendable (String) -> Void)? = nil
    ) async throws -> [BenchmarkRun] {
        func emit(_ message: String) { log?(message) }

        emit("warmup (Apple Foundation Model) …")
        let warmupSession = LanguageModelSession(instructions: "Reply with one word.")
        _ = try await warmupSession.respond(to: "Hi")
        emit("warmup ready")

        var runs: [BenchmarkRun] = []
        for (i, prompt) in prompts.enumerated() {
            let memBefore = MemoryMeasurement.physicalFootprintMB()
            let start = ContinuousClock.now

            let session = LanguageModelSession(
                instructions: prompt.system ?? "You are a helpful assistant."
            )

            var snapshotCount = 0
            var ttftDuration: Duration?
            var finalText = ""

            let stream = session.streamResponse(to: prompt.text)
            for try await snapshot in stream {
                if ttftDuration == nil && !snapshot.content.isEmpty {
                    ttftDuration = start.duration(to: .now)
                }
                snapshotCount += 1
                finalText = snapshot.content
            }

            let elapsed = start.duration(to: .now)
            let elapsedSec = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            let memAfter = MemoryMeasurement.physicalFootprintMB()

            // Approximate token count from final text length (≈ 4 chars/token
            // for English). Snapshot count is also a reasonable proxy since each
            // update typically delivers one or a small batch of tokens.
            let approxTokens = max(snapshotCount, finalText.count / 4)
            let tokPerSec = approxTokens > 0 ? Double(approxTokens) / elapsedSec : 0

            let ttftMs: Double
            if let ttft = ttftDuration {
                ttftMs = Double(ttft.components.seconds) * 1000
                    + Double(ttft.components.attoseconds) / 1e15
            } else {
                ttftMs = -1
            }

            let run = BenchmarkRun(
                experiment_id: experimentId,
                model: "apple-foundation-model",
                quant: "native",
                prompt_id: prompt.id,
                tokens_per_sec: tokPerSec,
                ttft_ms: ttftMs,
                memory_mb: memAfter > 0 ? memAfter : memBefore,
                timestamp: BenchmarkRun.timestampNow(),
                device: device
            )
            runs.append(run)

            emit(
                "[\(i + 1)/\(prompts.count)] \(prompt.id) — "
                + String(format: "%.1f tok/s, TTFT %.0fms, %.0fMB", tokPerSec, ttftMs, run.memory_mb)
                + " (\(approxTokens) approx tokens, \(snapshotCount) snapshots)"
                + ", thermal=\(thermalLabel())"
            )
        }
        return runs
    }

    private func thermalLabel() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
