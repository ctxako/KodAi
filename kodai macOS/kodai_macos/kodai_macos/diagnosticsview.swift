//
//  diagnosticsview.swift
//  kodai_macos
//

import SwiftUI

struct DiagnosticsTabView: View {
    let telemetryStore: TelemetryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(statLine1)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.84))
                Text(statLine2)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .opacity(0.10)
                .padding(.horizontal, 16)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(telemetryStore.flatEvents) { event in
                            Text("[\(formatOffset(event.relativeOffset))] \(event.name.rawValue)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 220)
                .onChange(of: telemetryStore.flatEvents.count) { _, _ in
                    if let last = telemetryStore.flatEvents.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var statLine1: String {
        var parts = ["Apple Intelligence"]
        if telemetryStore.rollingTokensPerSecond > 0 {
            parts.append(String(format: "%.1f tok/s", telemetryStore.rollingTokensPerSecond))
        }
        if telemetryStore.rollingLatencyAverage > 0 {
            parts.append(String(format: "%.1fs latency", telemetryStore.rollingLatencyAverage))
        }
        return parts.joined(separator: " · ")
    }

    private var statLine2: String {
        var parts: [String] = []
        if telemetryStore.rollingTimeToFirstTokenAverage > 0 {
            parts.append(String(format: "%.1fs TTFT", telemetryStore.rollingTimeToFirstTokenAverage))
        }
        parts.append(String(format: "%.1f%% failures", telemetryStore.rollingFailureRate))
        parts.append("\(telemetryStore.activeRequestCount) active")
        return parts.joined(separator: " · ")
    }

    private func formatOffset(_ t: TimeInterval) -> String {
        String(
            format: "%02d:%02d.%03d",
            Int(t / 60),
            Int(t) % 60,
            Int((t.truncatingRemainder(dividingBy: 1)) * 1000)
        )
    }
}
