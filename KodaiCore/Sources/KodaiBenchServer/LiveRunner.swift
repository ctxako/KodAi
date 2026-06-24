import Foundation
import FoundationModels
import KodaiBenchKit

struct LiveEvent: Codable, Sendable {
    let text: String
    let snapshot_count: Int
    let tokens_approx: Int
    let tps: Double
    let ttft_ms: Double
    let memory_mb: Double
    let elapsed_ms: Double
    let done: Bool
    let thermal: String
}

@available(macOS 26.0, *)
struct LiveRunner: Sendable {
    func run(
        prompt: String,
        system: String,
        experimentId: String?,
        endpoint: URL?,
        token: String?
    ) async throws -> AsyncThrowingStream<LiveEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let session = LanguageModelSession(instructions: system)
                    let memBefore = MemoryMeasurement.physicalFootprintMB()
                    let start = ContinuousClock.now

                    var snapshotCount = 0
                    var ttftDuration: Duration?
                    var finalText = ""

                    let stream = session.streamResponse(to: prompt)
                    for try await snapshot in stream {
                        if ttftDuration == nil && !snapshot.content.isEmpty {
                            ttftDuration = start.duration(to: .now)
                        }
                        snapshotCount += 1
                        finalText = snapshot.content

                        let elapsed = start.duration(to: .now)
                        let elapsedMs = durationMs(elapsed)
                        let elapsedSec = elapsedMs / 1000.0
                        let approxTokens = max(snapshotCount, finalText.count / 4)
                        let tps = elapsedSec > 0 ? Double(approxTokens) / elapsedSec : 0

                        let event = LiveEvent(
                            text: finalText,
                            snapshot_count: snapshotCount,
                            tokens_approx: approxTokens,
                            tps: tps,
                            ttft_ms: ttftDuration.map(durationMs) ?? -1,
                            memory_mb: MemoryMeasurement.physicalFootprintMB(),
                            elapsed_ms: elapsedMs,
                            done: false,
                            thermal: thermalLabel()
                        )
                        continuation.yield(event)
                    }

                    let elapsed = start.duration(to: .now)
                    let elapsedMs = durationMs(elapsed)
                    let elapsedSec = elapsedMs / 1000.0
                    let approxTokens = max(snapshotCount, finalText.count / 4)
                    let tps = elapsedSec > 0 ? Double(approxTokens) / elapsedSec : 0
                    let memAfter = MemoryMeasurement.physicalFootprintMB()

                    let final = LiveEvent(
                        text: finalText,
                        snapshot_count: snapshotCount,
                        tokens_approx: approxTokens,
                        tps: tps,
                        ttft_ms: ttftDuration.map(durationMs) ?? -1,
                        memory_mb: memAfter > 0 ? memAfter : memBefore,
                        elapsed_ms: elapsedMs,
                        done: true,
                        thermal: thermalLabel()
                    )
                    continuation.yield(final)

                    if let expId = experimentId {
                        let run = BenchmarkRun(
                            experiment_id: expId,
                            model: "apple-foundation-model",
                            quant: "native",
                            prompt_id: "live-\(Int(Date().timeIntervalSince1970))",
                            tokens_per_sec: tps,
                            ttft_ms: ttftDuration.map(durationMs) ?? -1,
                            memory_mb: final.memory_mb,
                            timestamp: BenchmarkRun.timestampNow(),
                            device: DeviceInfo.current
                        )
                        if let ep = endpoint, let tk = token {
                            let uploader = ResultUploader(endpoint: ep, token: tk)
                            try? await uploader.upload([run])
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func durationMs(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000.0 + Double(d.components.attoseconds) / 1e15
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
