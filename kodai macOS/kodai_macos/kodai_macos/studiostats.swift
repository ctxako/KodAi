//
//  studiostats.swift
//  kodai_macos
//
//  The statistical layer — the benchmarking protocol the lab follows: never
//  report a single sample. Each prompt is run N times and reduced to mean,
//  sample std dev, and percentiles, so the charts can show spread, not just a
//  point estimate.
//

import Foundation

/// Summary statistics for one metric over the repetitions of one prompt.
struct MetricStats: Sendable, Codable {
    let mean: Double
    let stdDev: Double        // sample std dev (n-1); 0 for a single sample
    let minimum: Double
    let median: Double
    let p90: Double
    let maximum: Double
    let count: Int

    init(values raw: [Double]) {
        let values = raw.filter { $0 >= 0 }   // drop unmeasured (e.g. ttft = -1)
        let n = values.count
        self.count = n
        guard n > 0 else {
            mean = 0; stdDev = 0; minimum = 0; median = 0; p90 = 0; maximum = 0
            return
        }
        let sorted = values.sorted()
        let m = values.reduce(0, +) / Double(n)
        self.mean = m
        self.minimum = sorted.first!
        self.maximum = sorted.last!
        self.median = MetricStats.percentile(sorted, 0.5)
        self.p90 = MetricStats.percentile(sorted, 0.9)
        if n > 1 {
            let variance = values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(n - 1)
            self.stdDev = variance.squareRoot()
        } else {
            self.stdDev = 0
        }
    }

    /// Linear-interpolation percentile on already-sorted values.
    private static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        guard sorted.count > 1 else { return sorted.first ?? 0 }
        let rank = q * Double(sorted.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        let frac = rank - Double(lo)
        return sorted[lo] + (sorted[hi] - sorted[lo]) * frac
    }
}

/// All metrics for one prompt across its repetitions, plus the raw samples (so
/// the distribution strip can plot every measurement).
struct PromptStats: Identifiable, Sendable, Codable {
    let id: String              // prompt id
    let throughput: MetricStats // tok/s
    let latency: MetricStats    // ttft ms
    let memory: MetricStats     // MB
    let rawThroughput: [Double] // per-rep tok/s, for the distribution strip
    let rawLatency: [Double]
    let approxTokens: Bool
    let preview: String
    let thermal: String
    let tokenCount: Int?
    let divergenceRatio: Double?   // llama-only: mean fraction of sampled≠argmax

    init(id: String, samples: [StudioSample], approxTokens: Bool) {
        self.id = id
        self.approxTokens = approxTokens
        self.throughput = MetricStats(values: samples.map(\.tokensPerSec))
        self.latency = MetricStats(values: samples.map(\.ttftMs))
        self.memory = MetricStats(values: samples.map(\.memoryMB))
        self.rawThroughput = samples.map(\.tokensPerSec)
        self.rawLatency = samples.map { max($0.ttftMs, 0) }
        self.preview = String((samples.first?.text ?? "").prefix(90))
        self.thermal = samples.last?.thermal ?? StudioThermal.label()
        self.tokenCount = samples.compactMap(\.tokenCount).last
        let ratios = samples.compactMap { s -> Double? in
            guard let d = s.divergedTokens, let t = s.totalDecisions, t > 0 else { return nil }
            return Double(d) / Double(t)
        }
        self.divergenceRatio = ratios.isEmpty ? nil : ratios.reduce(0, +) / Double(ratios.count)
    }
}

/// The metric driving the primary chart — one chart, three standard views.
enum StudioMetric: String, CaseIterable, Identifiable {
    case throughput
    case latency
    case memory

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .throughput: return "Throughput"
        case .latency: return "Latency"
        case .memory: return "Memory"
        }
    }

    var axisLabel: String {
        switch self {
        case .throughput: return "tokens / sec"
        case .latency: return "time to first token (ms)"
        case .memory: return "footprint (MB)"
        }
    }

    var legend: String {
        switch self {
        case .throughput: return "Tokens per second — higher is better. Bar = mean, whisker = ±1σ."
        case .latency: return "Time to first token — lower is better. Bar = mean, whisker = ±1σ."
        case .memory: return "Peak footprint — lower is better. Bar = mean, whisker = ±1σ."
        }
    }

    func stats(_ p: PromptStats) -> MetricStats {
        switch self {
        case .throughput: return p.throughput
        case .latency: return p.latency
        case .memory: return p.memory
        }
    }

    /// Raw per-rep samples for the distribution strip (memory not retained raw).
    func rawSamples(_ p: PromptStats) -> [Double] {
        switch self {
        case .throughput: return p.rawThroughput
        case .latency: return p.rawLatency
        case .memory: return [p.memory.mean]
        }
    }

    func format(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}
