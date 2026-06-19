//
//  RiverView.swift
//  kodAI_chatbot_dev
//
//  "Follow the River" — a scroll-driven, full-screen visualization of a single
//  response as a flowing current of token decisions. The chosen path is the
//  spine; rejected candidates fan off as tributaries; sampling forks (where the
//  model didn't follow its own strongest current) bend the channel and leave a
//  red ghost branch behind. A fixed playhead at screen center expands whatever
//  token you've scrolled to, so you "follow" the generation one decision at a
//  time. Reuses TokenSnapshot/TokenAlternative and TokenVisuals so confidence
//  reads identically to the heatmap and inspector.
//

import KodaiKernel
import SwiftUI

// MARK: - Layout model

/// A token's resolved position in the river: where the spine sits and how wide
/// the channel runs at that step.
private struct RiverNode {
    let step: Int
    /// Spine position as a fraction of canvas width (0.5 = centered).
    let x: CGFloat
    /// Channel half-width as a 0–1 fraction (driven by entropy → turbulence).
    let channel: CGFloat
}

private enum RiverLayout {
    /// Resolves spine drift: forks bend the current to one side, calm tokens let
    /// it ease back toward center. Successive forks alternate sides so a noisy
    /// stretch reads as meander rather than a runaway diagonal.
    static func nodes(for tokens: [TokenSnapshot]) -> [RiverNode] {
        var result: [RiverNode] = []
        result.reserveCapacity(tokens.count)
        var drift: CGFloat = 0
        for (i, token) in tokens.enumerated() {
            let impulse: CGFloat = token.divergedFromGreedy ? (i % 2 == 0 ? 0.14 : -0.14) : 0
            drift = drift * 0.72 + impulse
            drift = min(0.22, max(-0.22, drift))
            let channel = CGFloat(min(1, token.entropy / TokenVisuals.entropyReferenceMax))
            result.append(RiverNode(step: token.step, x: 0.5 + drift, channel: channel))
        }
        return result
    }
}

/// Reports each token's vertical center in the scroll coordinate space so the
/// playhead can lock onto whichever decision sits nearest screen center.
private struct TokenCenterPreference: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - River

struct RiverView: View {
    let messageText: String
    let history: [TokenSnapshot]

    @Environment(\.dismiss) private var dismiss
    @State private var activeStep: Int?

    /// Only tokens carrying a distribution can be mapped; end-of-stream flush
    /// chunks are dropped so the river reflects real decisions.
    private var tokens: [TokenSnapshot] { history.filter(\.isAnalyzed) }

    private let rowHeight: CGFloat = 96

    private var activeToken: TokenSnapshot? {
        tokens.first { $0.step == activeStep } ?? tokens.first
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.06, blue: 0.10), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if tokens.isEmpty {
                emptyState
            } else {
                river
                centerBand
                playheadCard
            }

            header
        }
        .statusBarHidden()
    }

    // MARK: Scrolling canvas

    private var river: some View {
        GeometryReader { outer in
            let nodes = RiverLayout.nodes(for: tokens)
            let canvasHeight = rowHeight * CGFloat(max(tokens.count, 1))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Lead-in / run-out so the first and last tokens can each
                    // rest at the centered playhead.
                    Color.clear.frame(height: outer.size.height / 2)

                    ZStack(alignment: .topLeading) {
                        RiverCanvas(
                            tokens: tokens,
                            nodes: nodes,
                            rowHeight: rowHeight,
                            activeStep: activeStep
                        )
                        .frame(width: outer.size.width, height: canvasHeight)

                        wordsLayer(width: outer.size.width, nodes: nodes)
                    }
                    .frame(width: outer.size.width, height: canvasHeight)

                    Color.clear.frame(height: outer.size.height / 2)
                }
            }
            .coordinateSpace(.named("river"))
            .onPreferenceChange(TokenCenterPreference.self) { centers in
                let mid = outer.size.height / 2
                let nearest = centers.min { abs($0.value - mid) < abs($1.value - mid) }?.key
                if nearest != activeStep {
                    activeStep = nearest
                }
            }
        }
    }

    /// The token text labelling each node, dropped just beneath its star so the
    /// dot and the word never overlap. A zero-size anchor sits on the node itself
    /// so the playhead locks the *star* (not the label) to the center band. The
    /// active token swells and brightens; others fade by their own confidence.
    private func wordsLayer(width: CGFloat, nodes: [RiverNode]) -> some View {
        ForEach(Array(tokens.enumerated()), id: \.element.id) { index, token in
            let node = nodes[index]
            let isActive = token.step == activeStep
            let nodeY = rowHeight * (CGFloat(index) + 0.5)
            Group {
                Color.clear
                    .frame(width: 1, height: 1)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: TokenCenterPreference.self,
                                value: [token.step: geo.frame(in: .named("river")).midY]
                            )
                        }
                    )
                    .position(x: node.x * width, y: nodeY)

                Text(TokenVisuals.displayText(token.text))
                    .font(.system(
                        size: isActive ? 17 : 13,
                        weight: isActive ? .semibold : .regular,
                        design: .monospaced
                    ))
                    .foregroundStyle(.white.opacity(isActive ? 1 : 0.28 + 0.42 * Double(token.selectedProbability)))
                    .fixedSize()
                    .position(x: node.x * width, y: nodeY + 26)
                    .animation(.easeInOut(duration: 0.18), value: isActive)
            }
        }
    }

    // MARK: Playhead

    /// The fixed focus line the river flows through.
    private var centerBand: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.35), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var playheadCard: some View {
        if let token = activeToken {
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(TokenVisuals.displayText(token.text))
                            .font(.title3.monospaced().bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Text("\(percent(token.selectedProbability))%")
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(TokenVisuals.confidenceColor(token.selectedProbability))
                    }

                    if token.divergedFromGreedy, let greedy = token.greedyAlternative {
                        Label(
                            "Forked — the strongest current was “\(TokenVisuals.displayText(greedy.text))” at \(percent(greedy.probability))%",
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.9))
                    }

                    HStack(spacing: 18) {
                        metric("entropy", String(format: "%.2f", token.entropy))
                        metric("margin", "\(percent(token.margin))%")
                        metric("surprise", String(format: "%.2f", -log(max(token.selectedProbability, 1e-6))))
                    }

                    if token.alternatives.count > 1 {
                        Divider().overlay(.white.opacity(0.12))
                        TokenAlternativesList(alternatives: token.alternatives)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.18), value: token.step)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Chrome

    private var header: some View {
        VStack {
            HStack(alignment: .top) {
                if !tokens.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Follow the River")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("\(tokens.count) tokens · scroll to follow the current")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "water.waves")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No token trail for this response.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
    }

    private func percent(_ value: Float) -> Int { Int((value * 100).rounded()) }
}

// MARK: - Canvas

/// Draws the water: the entropy-driven channel, the per-segment spine, the
/// tributaries for rejected candidates, and the red ghost branch wherever
/// sampling diverged from the model's top pick. Emphasis fades with distance
/// from the playhead so the focused stretch stays readable.
private struct RiverCanvas: View {
    let tokens: [TokenSnapshot]
    let nodes: [RiverNode]
    let rowHeight: CGFloat
    let activeStep: Int?

    var body: some View {
        Canvas { context, size in
            guard nodes.count > 1 else { return }
            let width = size.width
            let activeIndex = activeStep.flatMap { step in tokens.firstIndex { $0.step == step } }

            func center(_ i: Int) -> CGPoint {
                CGPoint(x: nodes[i].x * width, y: rowHeight * (CGFloat(i) + 0.5))
            }
            func halfWidth(_ i: Int) -> CGFloat {
                4 + (width * 0.30 - 4) * nodes[i].channel
            }
            func emphasis(_ i: Int) -> Double {
                guard let active = activeIndex else { return 1 }
                return max(0.12, 1 - Double(abs(i - active)) / 6)
            }

            // Channel band (the water body), filled with a cool gradient.
            let left = nodes.indices.map { CGPoint(x: nodes[$0].x * width - halfWidth($0), y: center($0).y) }
            let right = nodes.indices.map { CGPoint(x: nodes[$0].x * width + halfWidth($0), y: center($0).y) }
            var channel = Path()
            appendSmooth(&channel, points: left, isStart: true)
            appendSmooth(&channel, points: right.reversed(), isStart: false)
            channel.closeSubpath()
            context.fill(
                channel,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(hue: 0.55, saturation: 0.6, brightness: 0.55).opacity(0.22),
                        Color(hue: 0.70, saturation: 0.6, brightness: 0.45).opacity(0.08)
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            // Tributaries + ghost branches for rejected candidates.
            for i in nodes.indices {
                let token = tokens[i]
                let origin = center(i)
                let em = emphasis(i)
                var side: CGFloat = 1
                for (rank, alt) in token.alternatives.prefix(5).enumerated() where !alt.isSelected {
                    let isGhost = rank == 0 && token.divergedFromGreedy
                    let dist = (0.05 + 0.05 * CGFloat(rank)) * width * CGFloat(0.6 + alt.probability)
                    let end = CGPoint(x: origin.x + side * dist, y: origin.y - rowHeight * 0.34)
                    let control = CGPoint(x: origin.x + side * dist * 0.45, y: origin.y - rowHeight * 0.08)
                    side *= -1

                    var trib = Path()
                    trib.move(to: origin)
                    trib.addQuadCurve(to: end, control: control)
                    let color: Color = isGhost ? .red : .white
                    let opacity = Double(alt.probability) * (isGhost ? 0.9 : 0.5) * (0.25 + 0.75 * em)
                    context.stroke(
                        trib,
                        with: .color(color.opacity(opacity)),
                        style: StrokeStyle(lineWidth: isGhost ? 2 : 1, lineCap: .round, dash: isGhost ? [4, 3] : [])
                    )
                    let r = 1.5 + 3 * CGFloat(alt.probability)
                    context.fill(
                        Path(ellipseIn: CGRect(x: end.x - r, y: end.y - r, width: r * 2, height: r * 2)),
                        with: .color(color.opacity(opacity * 0.9))
                    )
                }
            }

            // Spine: per-segment so each leg carries the confidence of the token
            // it flows into.
            for i in 1..<nodes.count {
                var seg = Path()
                seg.move(to: center(i - 1))
                seg.addLine(to: center(i))
                let em = emphasis(i)
                context.stroke(
                    seg,
                    with: .color(TokenVisuals.confidenceColor(tokens[i].selectedProbability).opacity(0.25 + 0.65 * em)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
            }

            // Nodes: bright stars on the spine, sized/brightened by confidence.
            for i in nodes.indices {
                let token = tokens[i]
                let c = center(i)
                let em = emphasis(i)
                let r = 3 + 7 * CGFloat(token.selectedProbability)
                let color = TokenVisuals.confidenceColor(token.selectedProbability)
                context.fill(
                    Path(ellipseIn: CGRect(x: c.x - r * 2.4, y: c.y - r * 2.4, width: r * 4.8, height: r * 4.8)),
                    with: .color(color.opacity(0.16 * (0.4 + 0.6 * em)))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                    with: .color(color.opacity(0.5 + 0.5 * em))
                )
                if token.step == activeStep {
                    context.stroke(
                        Path(ellipseIn: CGRect(x: c.x - r - 5, y: c.y - r - 5, width: (r + 5) * 2, height: (r + 5) * 2)),
                        with: .color(.white.opacity(0.9)),
                        lineWidth: 1.5
                    )
                }
            }
        }
    }

    /// Appends a smoothed polyline (quadratic curves through segment midpoints)
    /// so the channel edges read as flowing water rather than facets.
    private func appendSmooth(_ path: inout Path, points: [CGPoint], isStart: Bool) {
        guard let first = points.first else { return }
        if isStart { path.move(to: first) } else { path.addLine(to: first) }
        guard points.count > 1 else { return }
        for i in 1..<points.count {
            let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
            path.addQuadCurve(to: mid, control: points[i - 1])
        }
        path.addLine(to: points[points.count - 1])
    }
}
