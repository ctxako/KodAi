//
//  diagnosticstelemetry.swift
//  kodai_macos
//

import Foundation

enum TelemetryEventName: String {
    case requestStarted
    case promptCounted
    case contextChecked
    case modelPrefillStarted
    case firstTokenReceived
    case tokenReceived
    case responseFinished
    case responseFailed
}

struct TelemetryEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let name: TelemetryEventName
    let relativeOffset: TimeInterval
}

struct RequestTimeline {
    let id: UUID
    let startedAt: Date
    var events: [TelemetryEvent] = []
}

struct RequestSummary {
    let tokensPerSecond: Double
    let totalLatency: Double
    let timeToFirstToken: Double?
    let failed: Bool
}

@MainActor
@Observable
final class TelemetryStore {
    private(set) var recentTimelines: [RequestTimeline] = []
    private(set) var recentSummaries: [RequestSummary] = []
    private(set) var activeRequestCount: Int = 0

    private let cap = 10

    func beginRequest() -> UUID {
        let timeline = RequestTimeline(id: UUID(), startedAt: .now)
        if recentTimelines.count >= cap {
            recentTimelines.removeFirst()
        }
        recentTimelines.append(timeline)
        activeRequestCount += 1
        return timeline.id
    }

    func emit(_ name: TelemetryEventName, to requestID: UUID) {
        guard let index = recentTimelines.firstIndex(where: { $0.id == requestID }) else { return }
        let offset = Date().timeIntervalSince(recentTimelines[index].startedAt)
        recentTimelines[index].events.append(
            TelemetryEvent(timestamp: .now, name: name, relativeOffset: offset)
        )
    }

    func finishRequest(id: UUID, summary: RequestSummary) {
        if recentSummaries.count >= cap {
            recentSummaries.removeFirst()
        }
        recentSummaries.append(summary)
        activeRequestCount = max(0, activeRequestCount - 1)
    }

    func cancelRequest() {
        activeRequestCount = max(0, activeRequestCount - 1)
    }

    var flatEvents: [TelemetryEvent] {
        let all = recentTimelines.flatMap { $0.events }
        guard all.count > 100 else { return all }
        return Array(all.suffix(100))
    }

    var rollingTokensPerSecond: Double {
        let speeds = recentSummaries.map { $0.tokensPerSecond }.filter { $0 > 0 }
        guard !speeds.isEmpty else { return 0 }
        return speeds.reduce(0, +) / Double(speeds.count)
    }

    var rollingLatencyAverage: Double {
        guard !recentSummaries.isEmpty else { return 0 }
        return recentSummaries.map { $0.totalLatency }.reduce(0, +) / Double(recentSummaries.count)
    }

    var rollingTimeToFirstTokenAverage: Double {
        let ttfts = recentSummaries.compactMap { $0.timeToFirstToken }
        guard !ttfts.isEmpty else { return 0 }
        return ttfts.reduce(0, +) / Double(ttfts.count)
    }

    var rollingFailureRate: Double {
        guard !recentSummaries.isEmpty else { return 0 }
        let failed = recentSummaries.filter { $0.failed }.count
        return Double(failed) / Double(recentSummaries.count) * 100
    }
}
