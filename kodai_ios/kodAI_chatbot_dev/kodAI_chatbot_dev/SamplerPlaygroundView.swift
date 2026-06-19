//
//  SamplerPlaygroundView.swift
//  kodAI_chatbot_dev
//
//  The interactive card behind the toolbar's sliders icon. Drag the knobs and
//  watch the model's next-token distribution reshape live — entirely from
//  captured data, with no inference. See `SamplerPlayground` for the math.
//

import KodaiKernel
import SwiftUI

struct SamplerPlaygroundView: View {
    /// Real captured alternatives from the most recent token, if any exist yet.
    let liveAlternatives: [TokenAlternative]?

    @Environment(\.dismiss) private var dismiss
    @State private var knobs = SamplerKnobs.default
    @State private var seen: Set<Int32> = []
    @State private var source: Source = .example
    @State private var info: KnobInfo?

    enum Source: String, CaseIterable, Identifiable {
        case example = "Example"
        case live = "Last token"
        var id: String { rawValue }
    }

    private var hasLive: Bool { (liveAlternatives?.count ?? 0) > 1 }

    private var candidates: [SamplerCandidate] {
        switch source {
        case .example:
            return SamplerPlayground.exampleCandidates
        case .live:
            return (liveAlternatives ?? []).map(SamplerCandidate.init(alternative:))
        }
    }

    private var outcome: SamplerPlayground.Outcome {
        SamplerPlayground.reshape(candidates, knobs: knobs, seenTokenIDs: seen)
    }

    private var maxBarProbability: Float {
        max(outcome.candidates.map(\.probability).max() ?? 1, 0.0001)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if hasLive { sourcePicker }
                    contextCard
                    distributionBars
                    readout
                    knobSection
                    resetButton
                }
                .padding()
                .padding(.bottom, 24)
            }
            .background(Color.black.opacity(0.92).ignoresSafeArea())
            .navigationTitle("Sampler Playground")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $info) { infoSheet($0) }
        }
        .onChange(of: source) { _, _ in clampTopK() }
    }

    // MARK: Source

    private var sourcePicker: some View {
        Picker("Distribution", selection: $source) {
            ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source == .example ? "Predicting the next word after" : "The model's actual last choice")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if source == .example {
                Text("“\(SamplerPlayground.exampleContext) …”")
                    .font(.callout.italic())
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                Text("Reshaping the top candidates the model weighed for its most recent token.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Distribution

    private var distributionBars: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tap a token to mark it as already-said")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(outcome.candidates) { candidate in
                candidateRow(candidate)
            }
        }
        .animation(.snappy(duration: 0.28), value: knobs)
        .animation(.snappy(duration: 0.28), value: seen)
        .animation(.snappy(duration: 0.28), value: source)
    }

    private func candidateRow(_ candidate: ReshapedCandidate) -> some View {
        Button {
            toggleSeen(candidate.tokenID)
        } label: {
            HStack(spacing: 8) {
                Text(TokenVisuals.displayText(candidate.text))
                    .font(.caption.monospaced())
                    .foregroundStyle(candidate.isCut ? .white.opacity(0.3) : .white.opacity(0.9))
                    .strikethrough(candidate.isCut, color: .white.opacity(0.3))
                    .frame(width: 78, alignment: .leading)
                    .lineLimit(1)

                if candidate.isSeen {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange.opacity(0.8))
                }

                probabilityBar(candidate)

                Text("\(Int((candidate.probability * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(candidate.isCut ? .white.opacity(0.3) : .white.opacity(0.55))
                    .frame(width: 34, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func probabilityBar(_ candidate: ReshapedCandidate) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Ghost of the raw probability, so the before/after shift is visible.
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: barWidth(candidate.rawProbability, in: geo.size.width))

                Capsule()
                    .fill(barColor(candidate))
                    .frame(width: barWidth(candidate.probability, in: geo.size.width))
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 10)
    }

    private func barWidth(_ probability: Float, in totalWidth: CGFloat) -> CGFloat {
        let fraction = CGFloat(probability / maxBarProbability)
        return max(2, totalWidth * min(1, fraction))
    }

    private func barColor(_ candidate: ReshapedCandidate) -> Color {
        if candidate.isCut { return Color.white.opacity(0.12) }
        if candidate.isWinner { return Color.green.opacity(0.75) }
        return Color.white.opacity(0.4)
    }

    // MARK: Readout

    private var readout: some View {
        HStack {
            stat(outcome.winner.map { TokenVisuals.displayText($0.text) } ?? "—", "picks")
            Spacer()
            stat("\(outcome.survivingCount)/\(candidates.count)", "candidates")
            Spacer()
            stat(String(format: "%.2f", outcome.entropy), "entropy (nats)")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Knobs

    private var knobSection: some View {
        VStack(spacing: 18) {
            knob(
                title: "Temperature",
                value: String(format: "%.2f", knobs.temperature),
                info: .temperature
            ) {
                Slider(value: $knobs.temperature, in: SamplerPlayground.minTemperature...2.0, step: 0.05)
            }

            knob(
                title: "Top-P",
                value: String(format: "%.2f", knobs.topP),
                info: .topP
            ) {
                Slider(value: $knobs.topP, in: 0.0...1.0, step: 0.01)
            }

            knob(
                title: "Top-K",
                value: "\(min(knobs.topK, candidates.count)) / \(candidates.count)",
                info: .topK
            ) {
                Slider(value: topKBinding, in: 1...Double(max(candidates.count, 1)), step: 1)
            }

            knob(
                title: "Repeat penalty",
                value: String(format: "%.2f", knobs.repeatPenalty),
                info: .repeatPenalty
            ) {
                Slider(value: $knobs.repeatPenalty, in: 1.0...2.0, step: 0.05)
            }
        }
    }

    private func knob(
        title: String,
        value: String,
        info knobInfo: KnobInfo,
        @ViewBuilder slider: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Button {
                    info = knobInfo
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About \(title)")
                Spacer()
                Text(value)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
            slider()
                .tint(.green.opacity(0.85))
        }
    }

    private var topKBinding: Binding<Double> {
        Binding(
            get: { Double(min(knobs.topK, max(candidates.count, 1))) },
            set: { knobs.topK = Int($0) }
        )
    }

    private var resetButton: some View {
        Button {
            withAnimation(.snappy) {
                knobs = .default
                seen = []
            }
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.8))
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Info sheet

    private func infoSheet(_ knobInfo: KnobInfo) -> some View {
        NavigationStack {
            ScrollView {
                Text(knobInfo.body)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color.black.opacity(0.92).ignoresSafeArea())
            .navigationTitle(knobInfo.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { info = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Actions

    private func toggleSeen(_ tokenID: Int32) {
        if seen.contains(tokenID) {
            seen.remove(tokenID)
        } else {
            seen.insert(tokenID)
        }
    }

    private func clampTopK() {
        knobs.topK = min(knobs.topK, max(candidates.count, 1))
    }
}
