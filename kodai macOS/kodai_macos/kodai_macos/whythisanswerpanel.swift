//
//  whythisanswerpanel.swift
//  kodai_macos

import SwiftUI
import KodaiCore

struct WhyThisAnswerPanel: View {
    let turn: TurnRecord

    private var manifest: ContextManifest? {
        guard let data = turn.contextManifestJSON else { return nil }
        return try? JSONDecoder().decode(ContextManifest.self, from: data)
    }

    private var tokensPerSec: Double? {
        guard turn.latencyMs > 0 else { return nil }
        let outputTokens = turn.performanceMetric?.outputTokenEstimate ?? turn.outputTokenEstimate
        guard outputTokens > 0 else { return nil }
        return Double(outputTokens) / (turn.latencyMs / 1000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            modelRow
            timingRow
            if let manifest {
                contextBlocksSection(manifest)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var modelRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(turn.modelName ?? "SystemLanguageModel.default")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("·")
                .font(.caption)
                .foregroundStyle(.quaternary)
            Text(turn.backend ?? "FoundationModels")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Model: \(turn.modelName ?? "SystemLanguageModel.default"), backend: \(turn.backend ?? "FoundationModels")")
    }

    private var timingRow: some View {
        HStack(spacing: 20) {
            TimingChip(
                label: "total",
                value: String(format: "%.2fs", turn.latencyMs / 1000)
            )
            if let ttft = turn.timeToFirstTokenMs {
                TimingChip(
                    label: "first token",
                    value: String(format: "%.2fs", ttft / 1000)
                )
            }
            if let tps = tokensPerSec {
                TimingChip(
                    label: "tok/s",
                    value: String(format: "%.0f", tps)
                )
            }
        }
    }

    @ViewBuilder
    private func contextBlocksSection(_ manifest: ContextManifest) -> some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 1)

        VStack(alignment: .leading, spacing: 4) {
            Text("Context blocks")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.quaternary)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.bottom, 2)

            ForEach(manifest.blocks, id: \.kind) { block in
                BlockRow(block: block)
            }

            HStack {
                Spacer()
                Text("\(manifest.totalTokens) / \(manifest.budgetLimit) tokens")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
            .padding(.top, 2)
        }
    }
}

private struct TimingChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

private struct BlockRow: View {
    let block: ContextBlockRecord

    private var icon: String {
        switch block.kind {
        case "persona":  return "person.fill"
        case "time":     return "clock.fill"
        case "mode":     return "slider.horizontal.3"
        case "meta":     return "info.circle.fill"
        case "history":  return "clock.arrow.circlepath"
        case "memory":   return "brain.head.profile"
        case "task":     return "checklist"
        case "summary":  return "doc.text"
        default:         return "square.grid.2x2"
        }
    }

    private var statusColor: Color {
        switch block.status {
        case .included: return .green
        case .truncated: return .orange
        case .excluded:  return .red
        }
    }

    private var statusLabel: String { block.status.rawValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 14)
                    .foregroundStyle(.secondary)

                Text(block.kind)
                    .font(.caption)
                    .foregroundStyle(.primary)

                Spacer()

                Text("~\(block.tokenEstimate) tok")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

                StatusBadge(label: statusLabel, color: statusColor)
            }

            if let reason = block.reason, block.status != .included {
                Text(reason)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 22)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(block.kind) block, \(block.tokenEstimate) tokens, \(statusLabel)\(block.reason.map { ", \($0)" } ?? "")")
    }
}

private struct StatusBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}
