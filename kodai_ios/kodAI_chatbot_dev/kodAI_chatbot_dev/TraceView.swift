//
//  TraceView.swift
//  kodAI_chatbot_dev
//
//  "The Trace" — the single representation of how a response was generated.
//  It draws itself the way the model wrote it: one node per committed token,
//  growing out as generation streams (or replaying that growth when opened after
//  the fact). The bright, continuous path is the *spine* — the chosen tokens.
//  Off each node, the considered-but-rejected candidates hang as short, faded
//  *branches*, their length and opacity carrying how much probability the model
//  gave each road not taken. A token where sampling overrode the model's own top
//  pick leaves a gold flare. Confidence is color (cool = sure, warm = surprised),
//  uncertainty is node size, and the spine meanders sideways through contested
//  moments so a confident passage runs straight and a surprising one wanders.
//
//  Reuses TokenSnapshot/TokenAlternative and TokenVisuals so confidence reads
//  identically here, in the inline heatmap, and in the inspector. One canvas,
//  one legend, every scale. This is a decision trace through probability space —
//  not "thoughts."
//

import KodaiKernel
import SwiftUI

// MARK: - Layout

/// A token's resolved horizontal position on the spine. The spine drifts sideways
/// through contested moments (where sampling left the model's strongest pick) and
/// eases back toward center when the model is confident, so a noisy stretch reads
/// as meander rather than a runaway diagonal. The recurrence is causal — it only
/// depends on tokens seen so far — so it lays out a partially-revealed spine the
/// same way it lays out the finished one.
private struct TraceNode {
    let step: Int
    /// Spine position as a fraction of canvas width (0.5 = centered).
    let x: CGFloat
}

private enum TraceLayout {
    static func nodes(for tokens: ArraySlice<TokenSnapshot>) -> [TraceNode] {
        var result: [TraceNode] = []
        result.reserveCapacity(tokens.count)
        var drift: CGFloat = 0
        var forkDirection: CGFloat = 1
        for token in tokens {
            let gap = max(0, (token.greedyAlternative?.probability ?? token.selectedProbability) - token.selectedProbability)
            let forkStrength = CGFloat(min(1, gap / 0.5))
            let impulse: CGFloat = token.divergedFromGreedy
                ? forkDirection * (0.06 + 0.10 * forkStrength)
                : 0
            if token.divergedFromGreedy { forkDirection *= -1 }
            drift = drift * 0.74 + impulse
            drift = min(0.2, max(-0.2, drift))
            result.append(TraceNode(step: token.step, x: 0.5 + drift))
        }
        return result
    }
}

/// One token resolved to a screen position, ready to draw and to hit-test.
private struct PlacedNode {
    let token: TokenSnapshot
    let point: CGPoint
    /// 0 = oldest visible (faded into the past), 1 = the growing tip.
    let age: CGFloat
}

// MARK: - Trace

struct TraceView: View {
    let messageText: String
    let history: [TokenSnapshot]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How many tokens of the spine are currently drawn. Animates up from zero on
    /// appear (the spine "writes itself") and chases the live token count during
    /// generation, so the same mechanism handles replay and live growth.
    @State private var drawnCount = 0
    /// A node the reader pinned by tapping; otherwise the active node is the tip.
    @State private var pinnedStep: Int?

    /// Only tokens carrying a distribution can be placed; end-of-stream flush
    /// chunks are dropped so the spine reflects real decisions.
    private var tokens: [TokenSnapshot] { history.filter(\.isAnalyzed) }

    /// Most recent visible tokens. Long responses scroll the oldest off the top so
    /// the tip and its recent trail always stay on screen without a scroll view.
    private let maxVisible = 130

    private var revealed: Int { min(drawnCount, tokens.count) }

    private var activeStep: Int? {
        pinnedStep ?? tokens[..<revealed].last?.step
    }

    private var activeToken: TokenSnapshot? {
        guard let activeStep else { return nil }
        return tokens.first { $0.step == activeStep }
    }

    private var activeIndex: Int? {
        guard let activeStep else { return nil }
        return tokens.firstIndex { $0.step == activeStep }
    }

    var body: some View {
        ZStack {
            background

            if tokens.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    header
                    field
                    card
                }
            }
        }
        .statusBarHidden()
        .task { await revealLoop() }
    }

    // MARK: Growth

    /// Advances `drawnCount` toward the available token count. Under Reduce Motion
    /// it snaps; otherwise it reveals in bounded steps so even a long response
    /// draws itself in roughly the same short beat. Clamps back down if the live
    /// history windows out its oldest tokens.
    private func revealLoop() async {
        while !Task.isCancelled {
            let target = tokens.count
            if drawnCount > target { drawnCount = target }
            if drawnCount < target {
                let step = reduceMotion ? target : max(1, target / 120)
                withAnimation(.easeOut(duration: 0.18)) {
                    drawnCount = min(target, drawnCount + step)
                }
                try? await Task.sleep(for: .milliseconds(16))
            } else {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    // MARK: Field (the canvas)

    private var field: some View {
        GeometryReader { geo in
            let placed = placedNodes(in: geo.size)
            ZStack(alignment: .topLeading) {
                TraceCanvas(placed: placed, activeStep: activeStep)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: revealed)

                if let active = activeToken, let point = placed.first(where: { $0.token.step == active.step })?.point {
                    tokenLabel(active)
                        .position(x: point.x.clamped(to: 60...(geo.size.width - 60)), y: max(28, point.y - 26))
                        .allowsHitTesting(false)
                }

                legend.padding(14)
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                selectNearest(to: location, in: placed)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Decision trace")
        .accessibilityValue(accessibilitySummary)
    }

    /// Resolves the visible window of the spine to screen positions. The meander is
    /// computed over the whole revealed prefix (so it stays continuous) but only the
    /// trailing window is placed: newest at the bottom, oldest fading at the top.
    private func placedNodes(in size: CGSize) -> [PlacedNode] {
        let count = revealed
        guard count > 0 else { return [] }
        let nodes = TraceLayout.nodes(for: tokens[..<count])
        let start = max(0, count - maxVisible)
        let windowCount = count - start
        let topInset: CGFloat = 64
        let bottomInset: CGFloat = 36
        let usable = max(1, size.height - topInset - bottomInset)

        var placed: [PlacedNode] = []
        placed.reserveCapacity(windowCount)
        for i in start..<count {
            let p = i - start
            let frac = windowCount > 1 ? CGFloat(p) / CGFloat(windowCount - 1) : 1
            let y = topInset + frac * usable
            let x = nodes[i].x * size.width
            placed.append(PlacedNode(token: tokens[i], point: CGPoint(x: x, y: y), age: frac))
        }
        return placed
    }

    private func selectNearest(to location: CGPoint, in placed: [PlacedNode]) {
        guard let nearest = placed.min(by: { $0.point.distance(to: location) < $1.point.distance(to: location) }),
              nearest.point.distance(to: location) < 60 else {
            if pinnedStep != nil { pinnedStep = nil; Haptics.lightTap() }
            return
        }
        pinnedStep = (pinnedStep == nearest.token.step) ? nil : nearest.token.step
        Haptics.lightTap()
    }

    // MARK: Chrome

    private var background: some View {
        ZStack {
            LiquidGlassBackground()
            LinearGradient(
                colors: [Color(red: 0.015, green: 0.03, blue: 0.06).opacity(0.92), .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [ChatPalette.accentBlue.opacity(0.10), .clear],
                center: .center, startRadius: 20, endRadius: 360
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Trace")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Decision \((activeIndex ?? 0) + 1) of \(tokens.count)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(ChatPalette.elevatedSurface).interactive(), in: Circle())
            .accessibilityLabel("Close trace")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// A wordless-first key: three swatches for the only colors that carry meaning.
    private var legend: some View {
        HStack(spacing: 10) {
            swatch(TokenVisuals.confidenceColor(0.95), "sure")
            swatch(TokenVisuals.confidenceColor(0.12), "surprised")
            swatch(TokenVisuals.divergenceColor, "overrode")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(.regular.tint(ChatPalette.elevatedSurface.opacity(0.7)), in: Capsule())
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private func tokenLabel(_ token: TokenSnapshot) -> some View {
        Text(readableToken(token.text))
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.black.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(ChatPalette.accentBlue.opacity(0.34), lineWidth: 1))
            .fixedSize()
    }

    // MARK: Card (the active decision)

    @ViewBuilder
    private var card: some View {
        if let token = activeToken {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(readableToken(token.text))
                        .font(.title3.monospaced().bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(percent(token.selectedProbability))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(TokenVisuals.confidenceColor(token.selectedProbability))
                }

                Label(insight(for: token), systemImage: token.divergedFromGreedy ? "arrow.triangle.branch" : "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.caption)
                    .foregroundStyle(token.divergedFromGreedy ? TokenVisuals.divergenceColor : .white.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)

                if pinnedStep != nil, token.alternatives.count > 1 {
                    TokenAlternativesList(alternatives: token.alternatives)
                        .padding(.top, 2)
                } else if token.alternatives.count > 1 {
                    Text("Tap a node to read the roads not taken")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.34))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassPanel(tint: ChatPalette.elevatedSurface.opacity(0.72), cornerRadius: 22)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: token.step)
        }
    }

    private func insight(for token: TokenSnapshot) -> String {
        if token.divergedFromGreedy, let greedy = token.greedyAlternative {
            return "Sampling chose “\(readableToken(token.text))” at \(percent(token.selectedProbability)); the model's top pick was “\(readableToken(greedy.text))” at \(percent(greedy.probability))."
        }
        if token.entropy >= 2.5 {
            return "Many next tokens were plausible here, even though this one won."
        }
        if token.selectedProbability >= 0.7 {
            return "A confident step — the model treated this as the clear next token."
        }
        return "Several candidates competed; this token stayed the strongest choice."
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No decision trace for this response.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
    }

    private var accessibilitySummary: String {
        guard let token = activeToken, let activeIndex else { return "No decisions yet." }
        return "Decision \(activeIndex + 1) of \(tokens.count): \(readableToken(token.text)), \(percent(token.selectedProbability)) probability."
    }

    private func readableToken(_ text: String) -> String {
        if text.contains("\n"), text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "line break" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "space" : trimmed
    }

    private func percent(_ value: Float) -> String {
        guard value > 0 else { return "0%" }
        if value < 0.01 { return "<1%" }
        return "\(Int((value * 100).rounded()))%"
    }
}

// MARK: - Canvas

/// Draws the spine, the faded branches for the roads not taken, and the gold
/// flares where sampling overrode the model's own top pick. Everything fades with
/// age toward the top so the freshest stretch stays the most legible.
private struct TraceCanvas: View {
    let placed: [PlacedNode]
    let activeStep: Int?

    var body: some View {
        Canvas { context, size in
            guard !placed.isEmpty else { return }
            let width = size.width

            // Branches first, so the spine and nodes sit on top of them.
            for node in placed {
                let token = node.token
                let origin = node.point
                let age = 0.25 + 0.75 * node.age
                var side: CGFloat = 1
                for (rank, alt) in token.alternatives.prefix(5).enumerated() where !alt.isSelected {
                    let isOverride = rank == 0 && token.divergedFromGreedy
                    let strength = CGFloat(alt.probability).squareRoot()
                    let reach = width * (0.04 + 0.18 * strength)
                    let end = CGPoint(x: origin.x + side * reach, y: origin.y - reach * 0.5)
                    let control = CGPoint(x: origin.x + side * reach * 0.5, y: origin.y - reach * 0.18)
                    side *= -1

                    var branch = Path()
                    branch.move(to: origin)
                    branch.addQuadCurve(to: end, control: control)
                    let color: Color = isOverride ? TokenVisuals.divergenceColor : TokenVisuals.alternativeColor
                    let opacity = isOverride
                        ? max(0.4, (0.3 + 0.5 * Double(strength)) * age)
                        : max(0.06, (0.06 + 0.46 * Double(strength)) * age)
                    context.stroke(
                        branch,
                        with: .color(color.opacity(opacity)),
                        style: StrokeStyle(
                            lineWidth: isOverride ? 2.4 : 0.8 + 1.8 * strength,
                            lineCap: .round,
                            dash: isOverride ? [5, 3] : []
                        )
                    )
                    let r = 1.2 + 2.2 * strength
                    context.fill(
                        Path(ellipseIn: CGRect(x: end.x - r, y: end.y - r, width: r * 2, height: r * 2)),
                        with: .color(color.opacity(opacity * 0.9))
                    )
                }
            }

            // Spine: one segment per leg, each carrying the confidence of the
            // token it flows into.
            for i in 1..<placed.count {
                let a = placed[i - 1].point
                let b = placed[i].point
                let age = 0.25 + 0.75 * placed[i].age
                let probability = placed[i].token.selectedProbability
                var seg = Path()
                seg.move(to: a)
                seg.addLine(to: b)
                context.stroke(
                    seg,
                    with: .color(TokenVisuals.confidenceColor(probability).opacity(0.3 + 0.6 * age)),
                    style: StrokeStyle(lineWidth: 1.2 + 2.0 * CGFloat(probability), lineCap: .round)
                )
            }

            // Nodes: brightness and size carry confidence; a faint halo carries
            // uncertainty; gold ring marks an override; the active node glows.
            for node in placed {
                let token = node.token
                let c = node.point
                let age = 0.3 + 0.7 * node.age
                let conf = CGFloat(token.selectedProbability)
                let r = 2.5 + 4.0 * conf.squareRoot()
                let color = TokenVisuals.confidenceColor(token.selectedProbability)

                let haloR = r * (1.6 + 1.4 * CGFloat(min(1, token.entropy / TokenVisuals.entropyReferenceMax)))
                context.fill(
                    Path(ellipseIn: CGRect(x: c.x - haloR, y: c.y - haloR, width: haloR * 2, height: haloR * 2)),
                    with: .color(color.opacity(0.10 * age))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                    with: .color(color.opacity(0.5 + 0.5 * age))
                )
                if token.divergedFromGreedy {
                    context.stroke(
                        Path(ellipseIn: CGRect(x: c.x - r - 2.5, y: c.y - r - 2.5, width: (r + 2.5) * 2, height: (r + 2.5) * 2)),
                        with: .color(TokenVisuals.divergenceColor.opacity(0.85 * age)),
                        lineWidth: 1.4
                    )
                }
                if token.step == activeStep {
                    context.stroke(
                        Path(ellipseIn: CGRect(x: c.x - r - 6, y: c.y - r - 6, width: (r + 6) * 2, height: (r + 6) * 2)),
                        with: .color(ChatPalette.accentBlue.opacity(0.95)),
                        lineWidth: 1.5
                    )
                }
            }
        }
    }
}

// MARK: - Geometry helpers

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
