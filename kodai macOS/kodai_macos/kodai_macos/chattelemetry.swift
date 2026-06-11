//
//  chattelemetry.swift
//  kodai_macos
//

import SwiftUI

struct ChatTelemetry {
    let contextPercent: Int
    let activeTokens: Int
    let contextWindowSize: Int
    let messageCount: Int
    let summaryAge: Int
    let failureCount: Int
    let averageSpeed: Double
    let averageLatency: Double
    let averageTimeToFirstToken: Double
    let streamName: String?

    var contextRiskColor: Color {
        if contextPercent >= 80 { return .red }
        if contextPercent >= 60 { return Color(red: 1.0, green: 0.85, blue: 0.0) }
        return Color(red: 0.22, green: 0.92, blue: 0.48)
    }

    var composerBarText: String {
        var parts: [String] = []
        if let streamName {
            parts.append(streamName)
        }
        parts.append("\(messageCount) chats")
        if averageSpeed > 0 {
            parts.append("\(String(format: "%.1f", averageSpeed)) tok/s")
        }
        if failureCount > 0 {
            parts.append("\(failureCount) failures")
        }
        return parts.joined(separator: " · ")
    }

    private func formatCount(_ n: Int) -> String {
        guard n >= 1_000 else { return "\(n)" }
        return String(format: "%d,%03d", n / 1_000, n % 1_000)
    }
}
