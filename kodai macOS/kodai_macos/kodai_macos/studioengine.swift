//
//  studioengine.swift
//  kodai_macos
//
//  Engine abstraction for the Studio bench. The rigor harness (repetitions,
//  statistics, history) is engine-agnostic: it drives anything that can turn a
//  prompt into a measured StudioSample. Today that's Apple Foundation Models;
//  the same protocol carries a file-loaded llama.cpp model (StudioLlamaEngine)
//  with zero changes to the harness — the whole point of the abstraction.
//

import Foundation
import FoundationModels
import KodaiBenchKit
import KodaiCore

/// Which engine the Studio drives. The harness is identical for both.
enum StudioEngineKind: String, CaseIterable, Identifiable {
    case foundationModels
    case localGGUF
    var id: String { rawValue }
    var title: String {
        switch self {
        case .foundationModels: return "Foundation Models"
        case .localGGUF: return "Local GGUF"
        }
    }
}

/// One measured generation. `tokenCount` is nil when the engine can't report a
/// real count (Foundation Models), in which case throughput is approximated
/// from text length and `approxTokens` is surfaced honestly in the UI.
struct StudioSample: Sendable {
    let tokensPerSec: Double
    let ttftMs: Double
    let memoryMB: Double
    let text: String
    let thermal: String
    let tokenCount: Int?
    /// llama-only: tokens where the sampled pick differed from the raw argmax,
    /// and the total decisions seen — the seed of the observatory's "gold."
    let divergedTokens: Int?
    let totalDecisions: Int?
}

/// Anything the Studio can benchmark. One prompt in, one measured sample out.
protocol StudioEngine {
    var label: String { get }       // UI engine name
    var modelName: String { get }   // BenchmarkRun `model` column
    var quant: String { get }       // BenchmarkRun `quant` column
    var approxTokens: Bool { get }  // true → tok/s approximated from chars

    func warmup() async throws
    func sample(prompt: BenchPrompt) async throws -> StudioSample
}

// MARK: - Apple Foundation Models

/// Drives Apple Foundation Models in-process. FM is a sealed model: it exposes
/// no token count, so throughput is approximated from text length (the same
/// heuristic the CLI `AppleModelRunner` uses) and `approxTokens` is true.
struct StudioFoundationModelsEngine: StudioEngine {
    enum EngineError: LocalizedError {
        case modelUnavailable(String)
        var errorDescription: String? {
            switch self {
            case .modelUnavailable(let reason):
                return "Apple Intelligence unavailable: \(reason)"
            }
        }
    }

    let label = "Apple Foundation Models"
    let modelName = "apple-foundation-model"
    let quant = "native"
    let approxTokens = true

    func warmup() async throws {
        let model = SystemLanguageModel.default
        if case .unavailable(let reason) = model.availability {
            throw EngineError.modelUnavailable("\(reason)")
        }
        let warmup = LanguageModelSession(instructions: "Reply with one word.")
        _ = try await warmup.respond(to: "Hi")
    }

    func sample(prompt: BenchPrompt) async throws -> StudioSample {
        let memBefore = MemoryMeasurement.physicalFootprintMB()
        let start = ContinuousClock.now

        let session = LanguageModelSession(
            instructions: prompt.system ?? "You are a helpful assistant."
        )
        var snapshotCount = 0
        var ttftDuration: Duration?
        var finalText = ""

        for try await snapshot in session.streamResponse(to: prompt.text) {
            if ttftDuration == nil && !snapshot.content.isEmpty {
                ttftDuration = start.duration(to: .now)
            }
            snapshotCount += 1
            finalText = snapshot.content
        }

        let elapsedSec = StudioTiming.seconds(start.duration(to: .now))
        let memAfter = MemoryMeasurement.physicalFootprintMB()
        let approx = max(snapshotCount, finalText.count / 4)
        let tokPerSec = (elapsedSec > 0 && approx > 0) ? Double(approx) / elapsedSec : 0

        return StudioSample(
            tokensPerSec: tokPerSec,
            ttftMs: ttftDuration.map(StudioTiming.milliseconds) ?? -1,
            memoryMB: memAfter > 0 ? memAfter : memBefore,
            text: finalText,
            thermal: StudioThermal.label(),
            tokenCount: nil,            // FM reports no token count
            divergedTokens: nil,
            totalDecisions: nil
        )
    }
}

// MARK: - Local GGUF (llama.cpp via shared KodaiRuntime)

/// Resolves the model to the exact file the user picked (the app is not
/// sandboxed, so any path is readable).
private struct StudioFilePathResolver: ModelFileResolver {
    let url: URL
    func resolve(configuration: LocalModelConfiguration) throws -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LocalModelRuntimeError.modelFileMissing(expectedFileName: url.lastPathComponent)
        }
        return url
    }
}

/// Drives a file-loaded GGUF through the *same* harness as Foundation Models —
/// the whole point of the engine abstraction. Reports real token counts (no
/// approximation) and, for free, counts the decode steps where sampling
/// diverged from the raw argmax (the observatory's "gold", surfaced here as a
/// single honest stat).
final class StudioLlamaEngine: StudioEngine {
    let label: String
    let modelName: String
    let quant: String
    let approxTokens = false

    private let runtime: LocalModelRuntime
    private let knobs: SamplerKnobs

    init(fileURL: URL) {
        let base = fileURL.deletingPathExtension().lastPathComponent
        self.modelName = base
        self.quant = extractQuant(fromModelName: base)
        self.label = "\(base) · GGUF"
        self.knobs = StudioLocalModel.config(for: fileURL).defaultSamplerKnobs
        self.runtime = StudioLocalModel.makeRuntime(for: fileURL)
    }

    func warmup() async throws {
        await runtime.prewarm { _ in }
    }

    func sample(prompt: BenchPrompt) async throws -> StudioSample {
        let memBefore = MemoryMeasurement.physicalFootprintMB()
        let start = ContinuousClock.now
        var ttft: Duration?
        var tokenCount = 0
        var text = ""
        var totalDecisions = 0
        var diverged = 0

        let stream = await runtime.generate(
            messages: [KodaiRuntimeMessage(role: .user, text: prompt.text)],
            systemPrompt: prompt.system ?? "You are a helpful assistant.",
            samplerKnobs: knobs
        )
        for try await event in stream {
            switch event {
            case .token(let chunk, let count):
                if ttft == nil { ttft = start.duration(to: .now) }
                tokenCount = count
                text += chunk                       // llama emits delta pieces
            case .tokenDecision(let decision):
                totalDecisions += 1
                if let argmax = decision.distribution.alternatives.max(by: { $0.probability < $1.probability }),
                   !argmax.isSelected {
                    diverged += 1                   // sampler overrode the favorite
                }
            default:
                break
            }
        }

        let elapsedSec = StudioTiming.seconds(start.duration(to: .now))
        let memAfter = MemoryMeasurement.physicalFootprintMB()
        let tokPerSec = (elapsedSec > 0 && tokenCount > 0) ? Double(tokenCount) / elapsedSec : 0

        return StudioSample(
            tokensPerSec: tokPerSec,
            ttftMs: ttft.map(StudioTiming.milliseconds) ?? -1,
            memoryMB: memAfter > 0 ? memAfter : memBefore,
            text: text,
            thermal: StudioThermal.label(),
            tokenCount: tokenCount,
            divergedTokens: totalDecisions > 0 ? diverged : nil,
            totalDecisions: totalDecisions > 0 ? totalDecisions : nil
        )
    }
}

/// Shared construction for a file-loaded GGUF: builds the configuration (LFM2.5
/// preset defaults, only the file name changes), short-circuits the runtime's
/// download fallback via a symlink, and makes the runtime. Used by both the
/// batch engine and the Scratch Bench (which supplies its own live knobs).
enum StudioLocalModel {
    static func config(for fileURL: URL) -> LocalModelConfiguration {
        let base = fileURL.deletingPathExtension().lastPathComponent
        let preset = LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M
        return LocalModelConfiguration(
            modelResourceName: base,
            modelResourceExtension: fileURL.pathExtension.isEmpty ? "gguf" : fileURL.pathExtension,
            shortDisplayName: base,
            contextSize: preset.contextSize,
            maxGeneratedTokens: preset.maxGeneratedTokens,
            temperature: preset.temperature,
            topP: preset.topP,
            topK: preset.topK,
            batchSize: preset.batchSize,
            repeatPenalty: preset.repeatPenalty
        )
    }

    static func makeRuntime(for fileURL: URL) -> LocalModelRuntime {
        let config = config(for: fileURL)
        linkIntoModelStore(fileURL: fileURL, expectedFileName: config.expectedModelFileName)
        return LocalModelRuntime(
            configuration: config,
            modelFileResolver: StudioFilePathResolver(url: fileURL)
        )
    }

    /// The runtime's loader has a download fallback keyed on the configuration's
    /// expected file name in Application Support. Symlink the chosen file there
    /// so the loader short-circuits — no copy, no network (offline by design).
    private static func linkIntoModelStore(fileURL: URL, expectedFileName: String) {
        let fm = FileManager.default
        guard let dest = try? ModelDownloader().localModelURL(fileName: expectedFileName) else { return }
        if fm.fileExists(atPath: dest.path) { return }
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.createSymbolicLink(at: dest, withDestinationURL: fileURL)
    }
}

// MARK: - Shared helpers

enum StudioTiming {
    static func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
    static func milliseconds(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
}

enum StudioThermal {
    static func label() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
