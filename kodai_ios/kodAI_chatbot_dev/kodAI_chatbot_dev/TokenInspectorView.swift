//
//  TokenInspectorView.swift
//  kodAI_chatbot_dev
//
//  Interpretation mode: inspect the model's per-token choices, the
//  alternatives it weighed, and where it was uncertain.
//

import KodaiKernel
import SwiftUI

// MARK: - Shared token visuals

/// Rendering helpers shared by the live trajectory (MessageBubble) and the
/// post-generation inspector so confidence is encoded consistently.
enum TokenVisuals {
    /// 0.0 (uncertain) → warm red, 1.0 (confident) → green.
    static func confidenceColor(_ probability: Float) -> Color {
        let clamped = Double(max(0, min(1, probability)))
        return Color(hue: clamped * 0.33, saturation: 0.72, brightness: 0.92)
    }

    /// Makes whitespace-only and newline tokens legible in compact rows.
    static func displayText(_ text: String) -> String {
        guard !text.isEmpty else { return "(blank)" }
        return text
            .replacingOccurrences(of: "\n", with: "⏎")
            .replacingOccurrences(of: "\t", with: "⇥")
            .replacingOccurrences(of: " ", with: "␣")
    }

    /// Entropy (nats) treated as "maximally uncertain" for color normalization.
    /// ~4 nats ≈ a uniform choice over ~55 tokens.
    static let entropyReferenceMax: Float = 4.0

    /// Normalizes a snapshot to a 0–1 "goodness" score for the chosen metric
    /// (1 = confident/green, 0 = uncertain/red).
    static func metricValue(_ snapshot: TokenSnapshot, metric: HeatMetric) -> Float {
        switch metric {
        case .confidence:
            return snapshot.selectedProbability
        case .margin:
            return snapshot.margin
        case .entropy:
            return max(0, 1 - min(1, snapshot.entropy / entropyReferenceMax))
        }
    }

    static func color(_ snapshot: TokenSnapshot, metric: HeatMetric) -> Color {
        guard snapshot.isAnalyzed else { return Color.white.opacity(0.15) }
        return confidenceColor(metricValue(snapshot, metric: metric))
    }
}

/// Selectable lens for the confidence heatmap.
enum HeatMetric: String, CaseIterable, Identifiable {
    case confidence = "Confidence"
    case entropy = "Entropy"
    case margin = "Margin"
    var id: String { rawValue }
}

/// Top-N alternatives for a single token with probability bars.
struct TokenAlternativesList: View {
    let alternatives: [TokenAlternative]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(alternatives, id: \.tokenID) { alt in
                HStack(spacing: 6) {
                    Text(TokenVisuals.displayText(alt.text))
                        .font(.caption2.monospaced())
                        .foregroundStyle(alt.isSelected ? .white.opacity(0.9) : .white.opacity(0.5))
                        .frame(minWidth: 44, alignment: .leading)
                        .lineLimit(1)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(alt.isSelected ? Color.white.opacity(0.5) : Color.white.opacity(0.18))
                            .frame(width: max(2, geo.size.width * CGFloat(alt.probability)), height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 5, maxHeight: 5)

                    Text("\(Int((alt.probability * 100).rounded()))%")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.42))
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Inspector

struct TokenInspectorView: View {
    let messageText: String
    let history: [TokenSnapshot]

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .heatmap
    @State private var expandedSteps: Set<Int> = []

    enum Mode: String, CaseIterable, Identifiable {
        case heatmap = "Heatmap"
        case tokens = "Tokens"
        var id: String { rawValue }
    }

    private static let lowConfidenceThreshold: Float = 0.6

    private var averageConfidence: Double {
        guard !history.isEmpty else { return 0 }
        let total = history.reduce(0.0) { $0 + Double($1.selectedProbability) }
        return total / Double(history.count)
    }

    private var lowConfidenceCount: Int {
        history.filter { $0.selectedProbability < Self.lowConfidenceThreshold }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                ScrollView {
                    switch mode {
                    case .heatmap:
                        heatmapView
                            .padding()
                    case .tokens:
                        tokenListView
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                    }
                }
            }
            .background(Color.black.opacity(0.92).ignoresSafeArea())
            .navigationTitle("Model Reasoning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var summaryHeader: some View {
        HStack {
            stat("\(history.count)", "tokens")
            Spacer()
            stat("\(Int((averageConfidence * 100).rounded()))%", "avg confidence")
            Spacer()
            stat("\(lowConfidenceCount)", "uncertain")
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Heatmap (feature 4)

    private var heatmapView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(attributedHeatmap)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            heatmapLegend
        }
    }

    private var attributedHeatmap: AttributedString {
        guard !history.isEmpty else { return AttributedString(messageText) }

        var result = AttributedString()
        for snapshot in history {
            guard !snapshot.text.isEmpty else { continue }
            var piece = AttributedString(snapshot.text)
            let uncertainty = Double(1 - snapshot.selectedProbability)
            piece.foregroundColor = .white
            piece.backgroundColor = Color.orange.opacity(uncertainty * 0.55)
            result += piece
        }
        return result.characters.isEmpty ? AttributedString(messageText) : result
    }

    private var heatmapLegend: some View {
        HStack(spacing: 8) {
            Text("Confident")
                .font(.caption2)
                .foregroundStyle(.secondary)
            LinearGradient(
                colors: [Color.orange.opacity(0), Color.orange.opacity(0.55)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 6)
            .clipShape(Capsule())
            Text("Uncertain")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Token list (feature 3)

    private var tokenListView: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(history) { snapshot in
                tokenRow(snapshot)
            }
        }
    }

    private func tokenRow(_ snapshot: TokenSnapshot) -> some View {
        let percent = Int((snapshot.selectedProbability * 100).rounded())
        let isLowConfidence = snapshot.selectedProbability < Self.lowConfidenceThreshold
        let isExpandable = snapshot.alternatives.count > 1
        let isExpanded = expandedSteps.contains(snapshot.step)

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                guard isExpandable else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        expandedSteps.remove(snapshot.step)
                    } else {
                        expandedSteps.insert(snapshot.step)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(TokenVisuals.displayText(snapshot.text))
                        .font(.callout.monospaced())
                        .foregroundStyle(isLowConfidence ? .white : .white.opacity(0.55))
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text("\(percent)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(TokenVisuals.confidenceColor(snapshot.selectedProbability))

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .opacity(isExpandable ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                TokenAlternativesList(alternatives: snapshot.alternatives)
                    .padding(.leading, 10)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .opacity(isLowConfidence || isExpanded ? 1 : 0.7)
    }
}
