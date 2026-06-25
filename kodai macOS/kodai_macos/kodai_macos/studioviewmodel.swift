//
//  studioviewmodel.swift
//  kodai_macos
//
//  State coordinator for the Studio. Drives an engine-agnostic bench: for each
//  prompt it runs N repetitions through the selected StudioEngine, reduces them
//  to PromptStats (mean ± σ, percentiles), keeps a local run history you can
//  A/B compare, and optionally writes to the D1 system of record.
//

import Foundation
import Observation
import KodaiBenchKit

@Observable
final class StudioViewModel {

    enum RunState: Equatable {
        case idle
        case running(progress: String)
        case finished
        case failed(String)
    }

    // MARK: Inputs

    let prompts: [BenchPrompt] = BenchPrompt.defaultSet
    var experimentId: String = "mac-studio-001"
    let device: String = DeviceInfo.current
    var repetitions: Int = 3

    // MARK: Live state

    private(set) var state: RunState = .idle
    private(set) var liveStats: [PromptStats] = []
    private(set) var lastUploadMessage: String?
    private(set) var runs: [StudioRun] = []
    private(set) var activeEngineLabel: String = "Apple Foundation Models"
    private(set) var activeApproxTokens: Bool = true

    // A/B comparison selection (run ids)
    var compareA: UUID?
    var compareB: UUID?

    private var completedUnits = 0
    private var totalUnits = 0
    private var runTask: Task<Void, Never>?
    private let runStore = StudioRunStore()

    init() {
        runs = runStore.load()
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var engineLabel: String { activeEngineLabel }

    var progressFraction: Double {
        guard totalUnits > 0 else { return 0 }
        return min(1, Double(completedUnits) / Double(totalUnits))
    }

    var progressPercent: Int { Int((progressFraction * 100).rounded()) }

    // MARK: Derived summary (over completed prompts)

    var averageThroughput: Double {
        let vals = liveStats.map(\.throughput.mean).filter { $0 > 0 }
        guard !vals.isEmpty else { return 0 }
        return vals.reduce(0, +) / Double(vals.count)
    }

    /// Typical spread — the mean of per-prompt throughput std devs.
    var typicalThroughputSigma: Double {
        let vals = liveStats.map(\.throughput.stdDev)
        guard !vals.isEmpty else { return 0 }
        return vals.reduce(0, +) / Double(vals.count)
    }

    /// Latency percentiles pooled across every measurement (the standard way to
    /// report TTFT — p50/p90, not a bare mean).
    private var pooledLatency: MetricStats { MetricStats(values: liveStats.flatMap(\.rawLatency)) }
    var latencyP50: Double { pooledLatency.median }
    var latencyP90: Double { pooledLatency.p90 }

    var peakMemoryMB: Double { liveStats.map(\.memory.maximum).max() ?? 0 }
    var peakThermal: String { liveStats.last?.thermal ?? StudioThermal.label() }

    /// llama-only: mean fraction of decode steps where sampling overrode the
    /// argmax — the seed of the observatory's "gold", shown here as one stat.
    var meanDivergence: Double? {
        let ratios = liveStats.compactMap(\.divergenceRatio)
        guard !ratios.isEmpty else { return nil }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    // MARK: Run lifecycle

    func run(engineKind: StudioEngineKind, modelPath: String, uploadEndpoint: String?, uploadToken: String?) {
        guard !isRunning else { return }

        liveStats = []
        lastUploadMessage = nil
        completedUnits = 0
        totalUnits = prompts.count * max(1, repetitions)
        state = .running(progress: "warming up …")

        let engine = makeEngine(kind: engineKind, modelPath: modelPath)
        let prompts = prompts
        let reps = max(1, repetitions)
        let experimentId = experimentId.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = device

        activeEngineLabel = engine.label
        activeApproxTokens = engine.approxTokens

        runTask = Task { [weak self] in
            do {
                try await engine.warmup()

                for prompt in prompts {
                    try Task.checkCancellation()
                    var samples: [StudioSample] = []
                    for rep in 0..<reps {
                        let sample = try await engine.sample(prompt: prompt)
                        samples.append(sample)
                        guard let self else { return }
                        self.completedUnits += 1
                        self.state = .running(
                            progress: "\(prompt.id) · rep \(rep + 1)/\(reps)"
                        )
                    }
                    guard let self else { return }
                    self.liveStats.append(
                        PromptStats(id: prompt.id, samples: samples, approxTokens: engine.approxTokens)
                    )
                }

                guard let self else { return }
                self.state = .finished
                self.recordRun(
                    engine: engine,
                    experimentId: experimentId.isEmpty ? "mac-studio-adhoc" : experimentId,
                    device: device,
                    reps: reps
                )
                await self.uploadIfNeeded(
                    engine: engine,
                    experimentId: experimentId.isEmpty ? "mac-studio-adhoc" : experimentId,
                    device: device,
                    endpoint: uploadEndpoint,
                    token: uploadToken
                )
            } catch is CancellationError {
                self?.state = .idle
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
        state = .idle
    }

    func regenerateExperimentId() {
        experimentId = "mac-studio-\(Int(Date().timeIntervalSince1970))"
    }

    // MARK: Engine selection

    private func makeEngine(kind: StudioEngineKind, modelPath: String) -> StudioEngine {
        switch kind {
        case .localGGUF where !modelPath.trimmingCharacters(in: .whitespaces).isEmpty:
            return StudioLlamaEngine(fileURL: URL(fileURLWithPath: modelPath))
        default:
            return StudioFoundationModelsEngine()
        }
    }

    // MARK: History

    private func recordRun(engine: StudioEngine, experimentId: String, device: String, reps: Int) {
        let run = StudioRun(
            engineLabel: engine.label,
            modelName: engine.modelName,
            quant: engine.quant,
            device: device,
            repetitions: reps,
            experimentId: experimentId,
            approxTokens: engine.approxTokens,
            prompts: liveStats
        )
        runs.insert(run, at: 0)
        // Seed comparison with the two most recent runs for convenience.
        compareB = compareA
        compareA = run.id
        runStore.save(runs)
    }

    func deleteRun(_ run: StudioRun) {
        runs.removeAll { $0.id == run.id }
        if compareA == run.id { compareA = nil }
        if compareB == run.id { compareB = nil }
        runStore.save(runs)
    }

    func run(for id: UUID?) -> StudioRun? {
        guard let id else { return nil }
        return runs.first { $0.id == id }
    }

    // MARK: Upload

    private func uploadIfNeeded(
        engine: StudioEngine,
        experimentId: String,
        device: String,
        endpoint: String?,
        token: String?
    ) async {
        guard
            let endpoint = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines),
            let token = token?.trimmingCharacters(in: .whitespacesAndNewlines),
            !endpoint.isEmpty, !token.isEmpty,
            let url = URL(string: endpoint)
        else { return }

        // One row per prompt, using the mean over repetitions.
        let rows = liveStats.map { stat in
            BenchmarkRun(
                experiment_id: experimentId,
                model: engine.modelName,
                quant: engine.quant,
                prompt_id: stat.id,
                tokens_per_sec: stat.throughput.mean,
                ttft_ms: stat.latency.mean,
                memory_mb: stat.memory.maximum,
                timestamp: BenchmarkRun.timestampNow(),
                device: device
            )
        }

        let uploader = ResultUploader(endpoint: url, token: token)
        do {
            try await uploader.upload(rows)
            lastUploadMessage = "Uploaded \(rows.count) prompt means to \(url.host ?? endpoint)"
        } catch {
            lastUploadMessage = "Upload failed: \(error.localizedDescription)"
        }
    }
}
