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

private enum RiverPalette {
    static let midnight = Color(red: 0.015, green: 0.035, blue: 0.065)
    static let deepWater = Color(red: 0.025, green: 0.11, blue: 0.17)
    static let current = Color(red: 0.28, green: 0.82, blue: 0.94)
    static let calm = Color(red: 0.34, green: 0.88, blue: 0.84)
    static let uncertain = Color(red: 0.98, green: 0.58, blue: 0.24)
    static let fork = Color(red: 0.73, green: 0.48, blue: 0.98)

    /// A color-blind-friendlier orange-to-cyan scale. Brightness and line width
    /// also carry confidence so color is never the only signal.
    static func confidence(_ probability: Float) -> Color {
        let value = Double(max(0, min(1, probability)))
        return Color(
            red: 0.98 - 0.64 * value,
            green: 0.58 + 0.30 * value,
            blue: 0.24 + 0.60 * value
        )
    }
}

private enum RiverCopy {
    static func readableToken(_ text: String) -> String {
        if text.contains("\n") && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "line break"
        }
        if text.contains("\t") && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "tab"
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "space" : trimmed
    }

    static func probability(_ value: Float) -> String {
        guard value > 0 else { return "0%" }
        if value < 0.01 { return "<1%" }
        return "\(Int((value * 100).rounded()))%"
    }
}

private enum RiverLayout {
    /// Resolves spine drift: forks bend the current to one side, calm tokens let
    /// it ease back toward center. Successive forks alternate sides so a noisy
    /// stretch reads as meander rather than a runaway diagonal.
    static func nodes(for tokens: [TokenSnapshot]) -> [RiverNode] {
        var result: [RiverNode] = []
        result.reserveCapacity(tokens.count)
        var drift: CGFloat = 0
        var forkDirection: CGFloat = 1
        for token in tokens {
            let gap = max(0, (token.greedyAlternative?.probability ?? token.selectedProbability) - token.selectedProbability)
            let forkStrength = CGFloat(min(1, gap / 0.5))
            let impulse: CGFloat = token.divergedFromGreedy
                ? forkDirection * (0.07 + 0.10 * forkStrength)
                : 0
            if token.divergedFromGreedy { forkDirection *= -1 }
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

// MARK: - Share helpers

private struct ShareURLWrapper: Identifiable {
    let id = UUID()
    let url: URL
}

private struct RiverShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct RiverTraceExportToken: Encodable {
    let step: Int
    let text: String
    let selectedProbability: Float
    let entropy: Float
    let margin: Float
}

private struct RiverTraceExport: Encodable {
    let prompt: String
    let response: String
    let tokens: [RiverTraceExportToken]
}

// MARK: - River

struct RiverView: View {
    let messageText: String
    let history: [TokenSnapshot]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeStep: Int?
    @State private var isLegendExpanded = false
    @State private var areAlternativesExpanded = false
    @State private var areMetricsExpanded = false
    @State private var zoomScale: CGFloat = 1.0
    @GestureState private var liveScale: CGFloat = 1.0
    @State private var shareURL: URL?

    /// Only tokens carrying a distribution can be mapped; end-of-stream flush
    /// chunks are dropped so the river reflects real decisions.
    private var tokens: [TokenSnapshot] { history.filter(\.isAnalyzed) }

    private let rowHeight: CGFloat = 104

    /// Pinch to zoom out compresses rows so the far end of the river is reachable
    /// with fewer scrolls. Current scale is the default/maximum (1.0); minimum is
    /// 0.3 (about 31 pt per token). Horizontal movement stays locked.
    private var effectiveRowHeight: CGFloat {
        min(rowHeight, max(rowHeight * 0.3, rowHeight * zoomScale * liveScale))
    }

    private var activeToken: TokenSnapshot? {
        tokens.first { $0.step == activeStep } ?? tokens.first
    }

    private var activeIndex: Int? {
        guard let activeToken else { return nil }
        return tokens.firstIndex { $0.step == activeToken.step }
    }

    var body: some View {
        ZStack {
            riverBackground

            if tokens.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    header

                    ZStack {
                        river
                        centerBand

                        if isLegendExpanded {
                            VStack {
                                riverLegend
                                    .padding(.horizontal, 12)
                                    .padding(.top, 8)
                                Spacer()
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }

                    playheadCard
                }
            }
        }
        .statusBarHidden()
    }

    private var riverBackground: some View {
        ZStack {
            LinearGradient(
                colors: [RiverPalette.midnight, .black, Color(red: 0.025, green: 0.01, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [RiverPalette.current.opacity(0.09), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }

    // MARK: Scrolling canvas

    private var river: some View {
        GeometryReader { outer in
            let nodes = RiverLayout.nodes(for: tokens)
            let rh = effectiveRowHeight
            let canvasHeight = rh * CGFloat(max(tokens.count, 1))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Lead-in / run-out so the first and last tokens can each
                    // rest at the centered playhead.
                    Color.clear.frame(height: outer.size.height / 2)

                    ZStack(alignment: .topLeading) {
                        RiverCanvas(
                            tokens: tokens,
                            nodes: nodes,
                            rowHeight: rh,
                            activeStep: activeStep
                        )
                        .frame(width: outer.size.width, height: canvasHeight)

                        wordsLayer(width: outer.size.width, nodes: nodes, rowHeight: rh)
                    }
                    .frame(width: outer.size.width, height: canvasHeight)

                    Color.clear.frame(height: outer.size.height / 2)
                }
            }
            .coordinateSpace(.named("river"))
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($liveScale) { value, state, _ in state = value }
                    .onEnded { value in
                        zoomScale = min(1.0, max(0.3, zoomScale * value))
                    }
            )
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
    private func wordsLayer(width: CGFloat, nodes: [RiverNode], rowHeight: CGFloat) -> some View {
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

                Text(RiverCopy.readableToken(token.text))
                    .font(.system(
                        size: isActive ? 17 : 12,
                        weight: isActive ? .semibold : .regular,
                        design: .monospaced
                    ))
                    .foregroundStyle(.white.opacity(isActive ? 1 : 0.28 + 0.42 * Double(token.selectedProbability)))
                    .padding(.horizontal, isActive ? 9 : 0)
                    .padding(.vertical, isActive ? 5 : 0)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(isActive ? 0.74 : 0))
                            .overlay(
                                Capsule().stroke(RiverPalette.current.opacity(isActive ? 0.34 : 0), lineWidth: 1)
                            )
                    )
                    .fixedSize()
                    .position(x: node.x * width, y: nodeY + rowHeight * 0.27)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isActive)
                    .accessibilityLabel("Decision \(index + 1): \(RiverCopy.readableToken(token.text))")
                    .accessibilityValue("\(RiverCopy.probability(token.selectedProbability)) probability")
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
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(RiverCopy.readableToken(token.text))
                            .font(.title3.monospaced().bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("raw token · \(TokenVisuals.displayText(token.text))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.38))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(RiverCopy.probability(token.selectedProbability))
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(RiverPalette.confidence(token.selectedProbability))
                        if let activeIndex {
                            Text("decision \(activeIndex + 1) of \(tokens.count)")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.38))
                        }
                    }
                }

                Label(insight(for: token), systemImage: token.divergedFromGreedy ? "arrow.triangle.branch" : "water.waves")
                    .font(.caption)
                    .foregroundStyle(token.divergedFromGreedy ? RiverPalette.fork : .white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { areMetricsExpanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text("metrics")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                            .rotationEffect(.degrees(areMetricsExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if areMetricsExpanded {
                    HStack(spacing: 7) {
                        metric(
                            "entropy",
                            String(format: "%.2f nats", token.entropy),
                            hint: "Uncertainty across the full vocabulary. Higher means more continuations were plausible."
                        )
                        metric(
                            "top margin",
                            "\(percent(token.margin)) pts",
                            hint: "The probability gap between the two strongest predictions."
                        )
                        metric(
                            "surprisal",
                            String(format: "%.2f nats", -log(max(token.selectedProbability, 1e-6))),
                            hint: "How unexpected the chosen token was, calculated as negative log probability."
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if token.alternatives.count > 1 {
                    Button {
                        areAlternativesExpanded = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .font(.caption2)
                            Text("Compare alternate currents")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("top \(min(5, token.alternatives.count)) + remainder")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.34))
                        }
                        .foregroundStyle(RiverPalette.current.opacity(0.9))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fieldNoteBackground)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: token.step)
            .sheet(isPresented: $areAlternativesExpanded) {
                AlternateCurrentsSheet(token: token)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(RiverPalette.midnight)
            }
        }
    }

    private func metric(_ label: String, _ value: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
        .accessibilityHint(hint)
    }

    private var responseContext: String {
        let collapsed = messageText
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return collapsed.isEmpty ? "Generated response" : "Response · \(collapsed)"
    }

    private func insight(for token: TokenSnapshot) -> String {
        if token.divergedFromGreedy, let greedy = token.greedyAlternative {
            return "Sampling chose this current at \(RiverCopy.probability(token.selectedProbability)); greedy decoding would choose “\(RiverCopy.readableToken(greedy.text))” at \(RiverCopy.probability(greedy.probability))."
        }
        if token.entropy >= 2.5 {
            return "Open water: many next tokens were plausible, even though this current won."
        }
        if token.selectedProbability >= 0.7 {
            return "A strong current: the model treated this as the clear next token."
        }
        return "Several currents competed here; this token remained the strongest choice."
    }

    private var fieldNoteBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [RiverPalette.deepWater.opacity(0.96), Color.black.opacity(0.94)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            FieldNoteCurrent()
                .stroke(RiverPalette.current.opacity(0.08), style: StrokeStyle(lineWidth: 58, lineCap: .round))
            FieldNoteCurrent()
                .stroke(
                    LinearGradient(
                        colors: [RiverPalette.current.opacity(0.12), RiverPalette.fork.opacity(0.16)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    LinearGradient(
                        colors: [RiverPalette.current.opacity(0.28), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Follow the River")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Decision \((activeIndex ?? 0) + 1) of \(tokens.count) · scroll to follow")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.42))
            }
            Spacer()
            if !tokens.isEmpty {
                Button { exportTrace() } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .accessibilityLabel("Export river trace")
            }
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    isLegendExpanded.toggle()
                }
            } label: {
                Image(systemName: "map")
                    .font(.body.weight(.medium))
                    .foregroundStyle(isLegendExpanded ? RiverPalette.current : .white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .accessibilityLabel(isLegendExpanded ? "Hide river legend" : "Show river legend")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("Close river")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.28))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RiverPalette.current.opacity(0.12))
                .frame(height: 1)
        }
        .sheet(item: Binding(
            get: { shareURL.map { ShareURLWrapper(url: $0) } },
            set: { if $0 == nil { shareURL = nil } }
        )) { wrapper in
            RiverShareSheet(url: wrapper.url)
                .ignoresSafeArea()
        }
    }

    private func exportTrace() {
        let response = history.map(\.visibleText).joined()
        let exportTokens = history.map { snap in
            RiverTraceExportToken(
                step: snap.step,
                text: snap.text,
                selectedProbability: snap.selectedProbability,
                entropy: snap.entropy,
                margin: snap.margin
            )
        }
        let export = RiverTraceExport(prompt: messageText, response: response, tokens: exportTokens)
        guard let data = try? JSONEncoder().encode(export) else { return }
        let filename = "river-trace-\(history.count)tok.json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        guard (try? data.write(to: url)) != nil else { return }
        shareURL = url
    }

    private var riverLegend: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("HOW TO READ THE CURRENT")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(RiverPalette.current.opacity(0.76))

            HStack(spacing: 8) {
                legendItem(
                    icon: "water.waves",
                    title: "Wider water",
                    detail: "more options"
                )
                legendItem(
                    icon: "circle.fill",
                    title: "Brighter path",
                    detail: "more likely"
                )
                legendItem(
                    icon: "arrow.triangle.branch",
                    title: "Dashed fork",
                    detail: "top pick not taken"
                )
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(RiverPalette.current.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("River legend. Wider water means more possible next tokens. A brighter path means the chosen token was more likely. A dashed fork marks the strongest prediction when sampling chose another token.")
    }

    private func legendItem(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(icon == "arrow.triangle.branch" ? RiverPalette.fork : RiverPalette.current)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.76))
                Text(detail)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct FieldNoteCurrent: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - 20, y: rect.maxY * 0.72))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.midY * 0.82),
            control1: CGPoint(x: rect.width * 0.18, y: rect.maxY * 0.45),
            control2: CGPoint(x: rect.width * 0.34, y: rect.maxY * 0.88)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX + 20, y: rect.maxY * 0.25),
            control1: CGPoint(x: rect.width * 0.66, y: rect.maxY * 0.18),
            control2: CGPoint(x: rect.width * 0.82, y: rect.maxY * 0.62)
        )
        return path
    }
}

private struct AlternateCurrentsSheet: View {
    let token: TokenSnapshot

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [RiverPalette.deepWater, RiverPalette.midnight, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Alternate Currents")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("What the local model considered for this next token")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .accessibilityLabel("Close alternate currents")
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Chosen · \(RiverCopy.readableToken(token.text))")
                        .font(.headline.monospaced())
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text(RiverCopy.probability(token.selectedProbability))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(RiverPalette.confidence(token.selectedProbability))
                }

                if token.divergedFromGreedy, let greedy = token.greedyAlternative {
                    Label(
                        "Sampling left the strongest current, “\(RiverCopy.readableToken(greedy.text))” at \(RiverCopy.probability(greedy.probability)).",
                        systemImage: "arrow.triangle.branch"
                    )
                    .font(.caption)
                    .foregroundStyle(RiverPalette.fork)
                }

                RiverAlternativesList(alternatives: token.alternatives)
                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }
}

private struct RiverAlternativesList: View {
    let alternatives: [TokenAlternative]

    private var displayed: [TokenAlternative] { Array(alternatives.prefix(6)) }

    private var remainder: Float {
        max(0, 1 - displayed.reduce(0) { $0 + $1.probability })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(displayed.enumerated()), id: \.element.tokenID) { index, alternative in
                row(
                    text: RiverCopy.readableToken(alternative.text),
                    probability: alternative.probability,
                    badge: alternative.isSelected ? "chosen" : (index == 0 ? "top" : nil),
                    tint: alternative.isSelected ? RiverPalette.current : (index == 0 ? RiverPalette.fork : .white)
                )
            }

            if remainder >= 0.005 {
                row(
                    text: "all other tokens",
                    probability: remainder,
                    badge: nil,
                    tint: .white.opacity(0.45)
                )
            }

            Text("Probabilities are the model’s raw next-token estimates before sampling.")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.top, 3)
    }

    private func row(text: String, probability: Float, badge: String?, tint: Color) -> some View {
        HStack(spacing: 7) {
            Text(text)
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.76))
                .frame(width: 82, alignment: .leading)
                .lineLimit(1)

            GeometryReader { geometry in
                Capsule()
                    .fill(tint.opacity(0.72))
                    .frame(width: max(2, geometry.size.width * CGFloat(probability)), height: 5)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, minHeight: 8, maxHeight: 8)

            if let badge {
                Text(badge)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 38, alignment: .trailing)
            } else {
                Color.clear.frame(width: 38, height: 1)
            }

            Text(RiverCopy.probability(probability))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.54))
                .frame(width: 32, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Canvas

/// Draws the water: the entropy-driven channel, the per-segment spine, the
/// tributaries for rejected candidates, and the violet ghost branch wherever
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
                5 + (width * 0.26 - 5) * nodes[i].channel
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
                        RiverPalette.current.opacity(0.22),
                        RiverPalette.fork.opacity(0.07)
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            var leftEdge = Path()
            appendSmooth(&leftEdge, points: left, isStart: true)
            context.stroke(leftEdge, with: .color(RiverPalette.current.opacity(0.12)), lineWidth: 1)
            var rightEdge = Path()
            appendSmooth(&rightEdge, points: right, isStart: true)
            context.stroke(rightEdge, with: .color(RiverPalette.current.opacity(0.12)), lineWidth: 1)

            // Tributaries + ghost branches for rejected candidates.
            for i in nodes.indices {
                let token = tokens[i]
                let origin = center(i)
                let em = emphasis(i)
                var side: CGFloat = 1
                for (rank, alt) in token.alternatives.prefix(5).enumerated() where !alt.isSelected {
                    let isGhost = rank == 0 && token.divergedFromGreedy
                    let strength = CGFloat(alt.probability).squareRoot()
                    let dist = width * (0.08 + 0.22 * strength)
                    let end = CGPoint(x: origin.x + side * dist, y: origin.y - rowHeight * 0.34)
                    let control = CGPoint(x: origin.x + side * dist * 0.45, y: origin.y - rowHeight * 0.08)
                    side *= -1

                    var trib = Path()
                    trib.move(to: origin)
                    trib.addQuadCurve(to: end, control: control)
                    let color: Color = isGhost ? RiverPalette.fork : RiverPalette.current
                    let baseOpacity = (0.08 + 0.56 * Double(strength)) * (0.28 + 0.72 * em)
                    let opacity = isGhost ? max(0.42, baseOpacity) : max(0.10, baseOpacity)
                    context.stroke(
                        trib,
                        with: .color(color.opacity(opacity)),
                        style: StrokeStyle(
                            lineWidth: isGhost ? 3.2 : 1.0 + 2.3 * strength,
                            lineCap: .round,
                            dash: isGhost ? [6, 3] : []
                        )
                    )
                    let r = 1.5 + 2.5 * strength
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
                let probability = tokens[i].selectedProbability
                context.stroke(
                    seg,
                    with: .color(RiverPalette.confidence(probability).opacity(0.3 + 0.65 * em)),
                    style: StrokeStyle(lineWidth: 1.4 + 2.1 * CGFloat(probability), lineCap: .round)
                )
            }

            // Nodes: bright stars on the spine, sized/brightened by confidence.
            for i in nodes.indices {
                let token = tokens[i]
                let c = center(i)
                let em = emphasis(i)
                let r = 3.5 + 4.5 * CGFloat(token.selectedProbability).squareRoot()
                let color = RiverPalette.confidence(token.selectedProbability)
                context.fill(
                    Path(ellipseIn: CGRect(x: c.x - r * 2.6, y: c.y - r * 2.6, width: r * 5.2, height: r * 5.2)),
                    with: .color(color.opacity(0.13 * (0.4 + 0.6 * em)))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                    with: .color(color.opacity(0.5 + 0.5 * em))
                )
                if token.step == activeStep {
                    context.stroke(
                        Path(ellipseIn: CGRect(x: c.x - r - 6, y: c.y - r - 6, width: (r + 6) * 2, height: (r + 6) * 2)),
                        with: .color(RiverPalette.current.opacity(0.95)),
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
