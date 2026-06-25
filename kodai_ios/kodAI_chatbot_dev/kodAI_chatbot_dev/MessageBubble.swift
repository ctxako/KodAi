import KodaiKernel
import SwiftUI
import UIKit

struct MessageBubble: View {
    let message: ChatMessage
    let messageFont: Font
    let maxBubbleWidth: CGFloat
    let reduceMotion: Bool
    let statusText: String?
    let activeProcessSummary: InferenceProcessSummary?
    let isProcessExpanded: Bool
    let generationStartDate: Date?
    let tokenHistory: [TokenSnapshot]
    let onToggleProcess: () -> Void
    let onEditComment: () -> Void

    @State private var isAlternativesExpanded = false
    @State private var showsInspector = false
    @State private var showsTrace = false
    @State private var summaryAppeared = false
    @State private var selectedHeatmapStep: Int?
    @State private var heatMetric: HeatMetric = .confidence

    var body: some View {
        bubble
    }

    @ViewBuilder
    private var bubble: some View {
        Group {
            if message.role == .user {
                HStack(spacing: 0) {
                    Spacer(minLength: 48)
                    messageTextView
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .messageBubbleGlass(tint: bubbleTint, isUser: true)
                        .frame(maxWidth: maxBubbleWidth * 0.78)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if let statusText {
                        if activeProcessSummary != nil,
                           message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ThinkingDotsView(isAnimated: !reduceMotion)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.8)))
                        }
                        processStatusView(statusText, summary: activeProcessSummary, isLive: true, generationStartDate: generationStartDate)
                        if !tokenHistory.isEmpty {
                            liveTrajectoryView(tokenHistory)
                        }
                    } else if let processSummary = message.processSummary {
                        processStatusView(processSummary.compactText, summary: processSummary, isLive: false, generationStartDate: nil)
                    }
                    messageTextView
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.text
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button {
                onEditComment()
            } label: {
                Label(
                    message.exportComment == nil ? "Add Comment" : "Edit Comment",
                    systemImage: "text.bubble"
                )
            }

            Divider()

            Button {
                SpeechService.shared.speak(message.text)
            } label: {
                Label("Read Aloud", systemImage: "speaker.wave.2")
            }

            if SpeechService.shared.isSpeaking {
                Button {
                    SpeechService.shared.stop()
                } label: {
                    Label("Stop Reading", systemImage: "speaker.slash")
                }
            }

            if !tokenHistory.isEmpty {
                Divider()

                Button {
                    showsTrace = true
                } label: {
                    Label("Trace", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }

                Button {
                    showsInspector = true
                } label: {
                    Label("Inspect Tokens", systemImage: "brain")
                }
            }

            Divider()

            Button {} label: {
                Label(
                    message.createdAt.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "clock"
                )
            }
            .disabled(true)
        }
        .sheet(isPresented: $showsInspector) {
            TokenInspectorView(messageText: message.text, history: tokenHistory)
        }
        .fullScreenCover(isPresented: $showsTrace) {
            TraceView(messageText: message.text, history: tokenHistory)
        }
    }

    /// The message text, rendered plainly.
    private var messageTextView: some View {
        Text(message.text.isEmpty ? " " : message.text)
            .font(messageFont)
            .foregroundStyle(.white)
            .textSelection(.enabled)
    }

    private var bubbleTint: Color {
        message.role == .user ? ChatPalette.userBubble : ChatPalette.assistantBubble
    }

    private func processStatusView(_ text: String, summary: InferenceProcessSummary?, isLive: Bool, generationStartDate: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                onToggleProcess()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(isProcessExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.15), value: isProcessExpanded)

                    if isLive, let startDate = generationStartDate {
                        TimelineView(.periodic(from: startDate, by: 1.0)) { context in
                            let elapsed = max(1, Int(context.date.timeIntervalSince(startDate)))
                            let label = message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "Thinking… \(elapsed)s"
                                : "Responding… \(elapsed)s"
                            Text(label)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .contentTransition(.numericText(countsDown: false))
                                .animation(.easeInOut(duration: 0.4), value: elapsed)
                        }
                    } else {
                        Text(text)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                    }

                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .frame(height: 18)
            }
            .buttonStyle(.plain)

            if isProcessExpanded, let summary {
                VStack(alignment: .leading, spacing: 3) {
                    if isLive {
                        if let currentPhase = summary.phasesReached.last {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color.secondary.opacity(0.5))
                                    .frame(width: 4, height: 4)
                                    .phaseAnimator([0.3, 1.0]) { view, opacity in
                                        view.opacity(opacity)
                                    } animation: { _ in .easeInOut(duration: 0.6) }

                                Text(currentPhase.displayName)
                                    .id(currentPhase)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                            .animation(.spring(duration: 0.25), value: currentPhase)
                        }
                    } else {
                        completedSummaryView(summary)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.42))
            }
        }
    }

    // MARK: - Completed summary (confidence-first, rolls in)

    @ViewBuilder
    private func completedSummaryView(_ summary: InferenceProcessSummary) -> some View {
        let stats = ConfidenceStats(history: tokenHistory)

        VStack(alignment: .leading, spacing: 8) {
            essentialsLine(summary, stats: stats)
                .modifier(RevealModifier(appeared: summaryAppeared, index: 0, reduceMotion: reduceMotion))

            if !tokenHistory.isEmpty {
                confidenceHeatmap()
                    .modifier(RevealModifier(appeared: summaryAppeared, index: 1, reduceMotion: reduceMotion))
            }

            metadataFooter(summary)
                .modifier(RevealModifier(appeared: summaryAppeared, index: 2, reduceMotion: reduceMotion))
        }
        .onAppear {
            guard !reduceMotion else {
                summaryAppeared = true
                return
            }
            summaryAppeared = false
            withAnimation(.easeOut(duration: 0.35)) {
                summaryAppeared = true
            }
        }
    }

    private func essentialsLine(_ summary: InferenceProcessSummary, stats: ConfidenceStats?) -> some View {
        var parts: [String] = []
        if let stats {
            parts.append(String(format: "PPL %.1f", stats.perplexity))
        }
        if let tokensPerSecondText = summary.tokensPerSecondText {
            parts.append("\(tokensPerSecondText) tok/s")
        }
        if let elapsedText = summary.elapsedText {
            parts.append(elapsedText)
        }
        return Text(parts.joined(separator: " · "))
            .foregroundStyle(.white.opacity(0.55))
    }

    // MARK: Confidence heatmap (replaces the static detail lines)

    private func confidenceHeatmap() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            heatmapHeader
            metricCaption
            divergenceNote

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 13), spacing: 3)],
                spacing: 3
            ) {
                ForEach(tokenHistory) { snapshot in
                    let isSelected = selectedHeatmapStep == snapshot.step
                    RoundedRectangle(cornerRadius: 2)
                        .fill(TokenVisuals.color(snapshot, metric: heatMetric).opacity(0.85))
                        .frame(height: 13)
                        .overlay(alignment: .topTrailing) {
                            if snapshot.divergedFromGreedy {
                                Circle()
                                    .fill(TokenVisuals.divergenceColor.opacity(0.9))
                                    .frame(width: 3, height: 3)
                                    .padding(1.5)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Color.white.opacity(isSelected ? 0.9 : 0), lineWidth: 1)
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedHeatmapStep = isSelected ? nil : snapshot.step
                            }
                        }
                }
            }

            if let step = selectedHeatmapStep,
               let snapshot = tokenHistory.first(where: { $0.step == step }) {
                selectedTokenDetail(snapshot)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var heatmapHeader: some View {
        HStack(spacing: 4) {
            ForEach(HeatMetric.allCases) { metric in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        heatMetric = metric
                    }
                } label: {
                    Text(metric.rawValue)
                        .font(.system(size: 9, weight: heatMetric == metric ? .semibold : .regular))
                        .foregroundStyle(heatMetric == metric ? .white : .white.opacity(0.4))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Color.white.opacity(heatMetric == metric ? 0.12 : 0),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 6)

            LinearGradient(
                colors: [
                    TokenVisuals.confidenceColor(0),
                    TokenVisuals.confidenceColor(0.5),
                    TokenVisuals.confidenceColor(1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 44, height: 4)
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var divergenceNote: some View {
        let divergedCount = tokenHistory.filter(\.divergedFromGreedy).count
        if divergedCount > 0 {
            HStack(spacing: 4) {
                Circle()
                    .fill(TokenVisuals.divergenceColor.opacity(0.9))
                    .frame(width: 4, height: 4)
                Text("sampling overrode the top pick · \(divergedCount)×")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer(minLength: 0)
            }
        }
    }

    /// Plain-English explanation of the selected metric, so the lens is
    /// self-documenting right in the view.
    private var metricCaption: some View {
        HStack(spacing: 6) {
            Text(metricDescription)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 6)

            Text(selectedHeatmapStep == nil ? "tap a cell · raw probs" : "tap again to close")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.3))
                .layoutPriority(-1)
        }
    }

    private var metricDescription: String {
        switch heatMetric {
        case .confidence:
            return "Confidence — how sure it was about the word it picked"
        case .entropy:
            return "Entropy — how many ways this word could've gone"
        case .margin:
            return "Margin — how close the call was between the top two"
        case .surprise:
            return "Surprise — how unexpected this word was (−log of its odds)"
        }
    }

    private func selectedTokenDetail(_ snapshot: TokenSnapshot) -> some View {
        let selected = snapshot.alternatives.first(where: \.isSelected)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(TokenVisuals.displayText(selected?.text ?? snapshot.text))
                    .font(.caption.monospaced())
                    .foregroundStyle(.white)
                Text("\(Int((snapshot.selectedProbability * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(TokenVisuals.confidenceColor(snapshot.selectedProbability))
                Spacer(minLength: 0)
                Text("token \(snapshot.step + 1)")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Text(String(format: "entropy %.2f nats · margin %d%%", snapshot.entropy, Int((snapshot.margin * 100).rounded())))
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))

            if snapshot.divergedFromGreedy, let greedy = snapshot.greedyAlternative {
                Text("Greedy would've picked \"\(TokenVisuals.displayText(greedy.text))\" \(Int((greedy.probability * 100).rounded()))%")
                    .font(.system(size: 9))
                    .foregroundStyle(TokenVisuals.divergenceColor.opacity(0.85))
            }

            if !snapshot.alternatives.isEmpty {
                TokenAlternativesList(alternatives: snapshot.alternatives)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metadataFooter(_ summary: InferenceProcessSummary) -> some View {
        var headlineParts: [String] = []
        if let modelName = summary.modelName {
            headlineParts.append(modelName)
        }
        headlineParts.append("\(summary.generatedTokenCount) tokens")

        return VStack(alignment: .leading, spacing: 2) {
            Text(headlineParts.joined(separator: " · "))
                .foregroundStyle(.white.opacity(0.35))

            if !summary.diagnostics.isEmpty {
                Text(summary.diagnostics.joined(separator: "; "))
                    .foregroundStyle(.white.opacity(0.3))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let failureMessage = summary.failureMessage {
                Text("Error: \(failureMessage)")
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
            }
        }
    }

    /// Real-time view of the decode trajectory: a moving strip of the last few
    /// tokens' confidence plus the current token, expandable to its alternatives.
    private func liveTrajectoryView(_ history: [TokenSnapshot]) -> some View {
        let recent = Array(history.suffix(14))
        let current = history.last

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isAlternativesExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(isAlternativesExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.15), value: isAlternativesExpanded)

                    trajectoryStrip(recent)

                    if let current {
                        let selectedText = current.alternatives.first(where: \.isSelected)?.text ?? current.text
                        Text(TokenVisuals.displayText(selectedText))
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("\(Int((current.selectedProbability * 100).rounded()))%")
                            .font(.caption2.monospacedDigit())
                    }

                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .frame(height: 18)
            }
            .buttonStyle(.plain)

            if isAlternativesExpanded, let current, !current.alternatives.isEmpty {
                TokenAlternativesList(alternatives: current.alternatives)
                    .padding(.leading, 12)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func trajectoryStrip(_ snapshots: [TokenSnapshot]) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(snapshots) { snapshot in
                RoundedRectangle(cornerRadius: 1)
                    .fill(TokenVisuals.confidenceColor(snapshot.selectedProbability).opacity(0.85))
                    .frame(width: 3, height: max(3, 14 * CGFloat(snapshot.selectedProbability)))
            }
        }
        .frame(height: 14, alignment: .bottom)
        .animation(.easeOut(duration: 0.2), value: snapshots.count)
    }
}

/// Confidence rollup for one message, derived from its token history. Now just
/// perplexity for the essentials line — the chips and sparkline that consumed the
/// other rollups were retired in favor of the Trace.
private struct ConfidenceStats {
    /// exp(mean(−ln p_selected)) — 1.0 = fully confident, higher = more hesitant.
    let perplexity: Float

    init?(history: [TokenSnapshot]) {
        let analyzed = history.filter(\.isAnalyzed)
        guard !analyzed.isEmpty else { return nil }
        let count = Float(analyzed.count)
        let meanNegativeLogProb = analyzed.reduce(Float(0)) { $0 - log(max($1.selectedProbability, 1e-6)) } / count
        perplexity = exp(meanNegativeLogProb)
    }
}

/// Staggered fade/slide-in keyed off a shared `appeared` flag so a group of
/// rows cascades in order. No-ops when reduce-motion is enabled.
private struct RevealModifier: ViewModifier {
    let appeared: Bool
    let index: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)
                .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.07), value: appeared)
        }
    }
}

private struct ThinkingDotsView: View {
    let isAnimated: Bool

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                BouncingDot(delay: Double(i) * 0.15, isAnimated: isAnimated)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct BouncingDot: View {
    let delay: Double
    let isAnimated: Bool
    @State private var isUp = false

    var body: some View {
        Circle()
            .fill(Color.secondary.opacity(0.55))
            .frame(width: 7, height: 7)
            .offset(y: isUp ? -5 : 0)
            .onAppear {
                guard isAnimated else { return }
                withAnimation(
                    .easeInOut(duration: 0.45)
                    .delay(delay)
                    .repeatForever(autoreverses: true)
                ) {
                    isUp = true
                }
            }
    }
}
