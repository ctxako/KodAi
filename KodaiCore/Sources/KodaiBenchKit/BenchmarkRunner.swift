import Foundation
import KodaiKernel
import KodaiRuntime

/// Runs a fixed prompt set through a `LocalModelRuntime`, measuring
/// tokens/sec, time-to-first-token, and memory per prompt. Shared by the
/// macOS CLI and the on-device iOS test so both exercise the identical path.
public struct BenchmarkRunner: Sendable {
    public init() {}

    /// - Parameters:
    ///   - modelName: model identifier for the `model` column (no extension).
    ///   - quant: quantization label for the `quant` column.
    ///   - log: optional progress sink (CLI prints it; the test logs it).
    public func run(
        runtime: LocalModelRuntime,
        modelName: String,
        quant: String,
        prompts: [BenchPrompt],
        experimentId: String,
        device: String,
        knobs: SamplerKnobs,
        log: (@Sendable (String) -> Void)? = nil
    ) async throws -> [BenchmarkRun] {
        func emit(_ message: String) { log?(message) }

        // Warmup — load the model and prime Metal before timing, so the first
        // measured prompt doesn't absorb cold-start model-load latency.
        emit("warmup …")
        let warmup = await runtime.generate(
            messages: [KodaiRuntimeMessage(role: .user, text: "Hi")],
            systemPrompt: "Reply with one word.",
            samplerKnobs: knobs
        )
        for try await _ in warmup {}
        emit("warmup ready")

        var runs: [BenchmarkRun] = []
        for (i, prompt) in prompts.enumerated() {
            let memBefore = MemoryMeasurement.physicalFootprintMB()
            let start = ContinuousClock.now

            var tokenCount = 0
            var ttftDuration: Duration?

            let stream = await runtime.generate(
                messages: [KodaiRuntimeMessage(role: .user, text: prompt.text)],
                systemPrompt: prompt.system ?? "You are a helpful assistant.",
                samplerKnobs: knobs
            )
            for try await event in stream {
                switch event {
                case .token(_, let count):
                    if ttftDuration == nil { ttftDuration = start.duration(to: .now) }
                    tokenCount = count
                default:
                    break
                }
            }

            let elapsed = start.duration(to: .now)
            let elapsedSec = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            let memAfter = MemoryMeasurement.physicalFootprintMB()

            let tokPerSec = tokenCount > 0 ? Double(tokenCount) / elapsedSec : 0
            let ttftMs: Double
            if let ttft = ttftDuration {
                ttftMs = Double(ttft.components.seconds) * 1000 + Double(ttft.components.attoseconds) / 1e15
            } else {
                ttftMs = -1
            }

            let run = BenchmarkRun(
                experiment_id: experimentId,
                model: modelName,
                quant: quant,
                prompt_id: prompt.id,
                tokens_per_sec: tokPerSec,
                ttft_ms: ttftMs,
                memory_mb: memAfter > 0 ? memAfter : memBefore,
                timestamp: BenchmarkRun.timestampNow(),
                device: device
            )
            runs.append(run)

            let line = "[\(i + 1)/\(prompts.count)] \(prompt.id) — "
                + String(format: "%.1f tok/s, TTFT %.0fms, %.0fMB", tokPerSec, ttftMs, run.memory_mb)
                + ", thermal=\(Self.thermalLabel())"
            emit(line)
        }
        return runs
    }

    static func thermalLabel() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
