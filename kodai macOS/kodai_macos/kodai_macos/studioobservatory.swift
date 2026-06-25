//
//  studioobservatory.swift
//  kodai_macos
//
//  The token observatory — Phase 4's honest core. Painted entirely from the
//  per-token decision trace the shared KodaiRuntime emits on a local GGUF run
//  (probability, entropy, margin, top-K alternatives, argmax divergence). This
//  is only truthful on llama.cpp, where the raw pre-sampling distribution is
//  readable — never faked on Foundation Models.
//
//  This is the 2D foundation (heatmap + inspector). The immersive River/Globe
//  views are later slices on the same telemetry contract.
//

import SwiftUI
import KodaiCore

// MARK: - Visual grammar (one source of truth for color meaning)

enum StudioTokenVisuals {
    /// Probability → color: muted slate-indigo (uncertain) to luminous cyan
    /// (confident). Brightness carries the signal too, so it reads without
    /// relying on hue alone.
    static func color(forProbability p: Double) -> Color {
        let t = max(0, min(1, p))
        return Color(
            red: 0.36,
            green: 0.40 + (0.85 - 0.40) * t,
            blue: 0.62 + (0.98 - 0.62) * t
        )
    }

    /// Reserved warm accent — the one place gold appears: the sampler overrode
    /// the model's favorite token.
    static let gold = Color(red: 0.98, green: 0.80, blue: 0.35)

    static func glyph(_ s: String) -> String {
        if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if s.contains("\n") { return "⏎" }
            if s.contains("\t") { return "⇥" }
            return "␣"
        }
        return s.replacingOccurrences(of: "\n", with: "⏎")
    }
}

// MARK: - View model token

struct ObservatoryToken: Identifiable {
    let id: Int
    let display: String
    let probability: Double
    let entropy: Double
    let margin: Double
    let diverged: Bool
    let alternatives: [Alt]

    var surprise: Double { probability > 0 ? -log(probability) : 0 }

    struct Alt: Identifiable {
        let id = UUID()
        let text: String
        let prob: Double
        let isSelected: Bool
    }

    init(decision: TokenDecision) {
        id = decision.step
        display = StudioTokenVisuals.glyph(decision.text)
        let dist = decision.distribution
        probability = Double(dist.selectedProbability)
        entropy = Double(dist.entropy)
        margin = Double(dist.margin)
        let sorted = dist.alternatives.sorted { $0.probability > $1.probability }
        diverged = sorted.first.map { !$0.isSelected } ?? false
        alternatives = sorted.prefix(5).map {
            Alt(text: StudioTokenVisuals.glyph($0.text), prob: Double($0.probability), isSelected: $0.isSelected)
        }
    }
}

// MARK: - Observatory

struct StudioObservatoryView: View {
    @Environment(\.kodaiTheme) private var theme
    let trace: [TokenDecision]
    @State private var selected: Int?

    private var tokens: [ObservatoryToken] { trace.map(ObservatoryToken.init) }

    private var meanEntropy: Double {
        guard !tokens.isEmpty else { return 0 }
        return tokens.map(\.entropy).reduce(0, +) / Double(tokens.count)
    }
    private var divergedCount: Int { tokens.filter(\.diverged).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            legend
            heatmap
            if let id = selected, let token = tokens.first(where: { $0.id == id }) {
                inspector(token)
            } else {
                Text("Tap a token to inspect the alternatives the model weighed.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(theme.secondaryText.opacity(0.7))
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .kodaiGlass(cornerRadius: 16)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Token observatory")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.secondaryText)
            Spacer()
            Text("\(tokens.count) tokens · mean entropy \(String(format: "%.2f", meanEntropy)) nats · diverged \(divergedCount)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.secondaryText.opacity(0.8))
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                LinearGradient(
                    colors: [StudioTokenVisuals.color(forProbability: 0.1),
                             StudioTokenVisuals.color(forProbability: 1.0)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 60, height: 8).clipShape(Capsule())
                Text("uncertain → confident")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(theme.secondaryText.opacity(0.7))
            }
            HStack(spacing: 5) {
                Circle().fill(StudioTokenVisuals.gold).frame(width: 8, height: 8)
                Text("sampler overrode the favorite")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(theme.secondaryText.opacity(0.7))
            }
            Spacer()
        }
    }

    private var heatmap: some View {
        FlowLayout(spacing: 4) {
            ForEach(tokens) { token in
                chip(token)
            }
        }
    }

    private func chip(_ token: ObservatoryToken) -> some View {
        let color = StudioTokenVisuals.color(forProbability: token.probability)
        let isSelected = selected == token.id
        return Text(token.display)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(
                        isSelected ? theme.primaryText.opacity(0.8)
                            : (token.diverged ? StudioTokenVisuals.gold : .clear),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture { selected = isSelected ? nil : token.id }
    }

    private func inspector(_ token: ObservatoryToken) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(theme.glassBorder)
            HStack(spacing: 18) {
                inspectorStat("chosen p", String(format: "%.3f", token.probability))
                inspectorStat("entropy", String(format: "%.2f", token.entropy))
                inspectorStat("margin", String(format: "%.3f", token.margin))
                inspectorStat("surprise", String(format: "%.2f", token.surprise))
                if token.diverged {
                    Text("sampler overrode the favorite")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTokenVisuals.gold)
                }
                Spacer()
            }

            Text("Top alternatives the model weighed")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText.opacity(0.8))

            ForEach(token.alternatives) { alt in
                HStack(spacing: 8) {
                    Text(alt.text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.primaryText)
                        .frame(width: 90, alignment: .leading).lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.glassSurface)
                            Capsule()
                                .fill(alt.isSelected ? StudioTokenVisuals.color(forProbability: alt.prob) : theme.secondaryText.opacity(0.4))
                                .frame(width: max(4, geo.size.width * alt.prob))
                        }
                    }
                    .frame(height: 10)
                    Text(String(format: "%.3f", alt.prob))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.secondaryText).frame(width: 44, alignment: .trailing)
                    Image(systemName: alt.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(alt.isSelected ? theme.primaryAccent : theme.secondaryText.opacity(0.4))
                }
            }
        }
    }

    private func inspectorStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.primaryText)
            Text(label).font(.system(size: 9, design: .rounded))
                .foregroundStyle(theme.secondaryText.opacity(0.7))
        }
    }
}

// MARK: - Minimal flow layout for the heatmap chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
