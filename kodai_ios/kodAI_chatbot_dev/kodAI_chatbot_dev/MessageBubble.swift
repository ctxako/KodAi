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
    let onToggleProcess: () -> Void
    let onEditComment: () -> Void

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble
                Spacer(minLength: 44)
            } else {
                Spacer(minLength: 44)
                bubble
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.role == .assistant {
                if let statusText {
                    if activeProcessSummary != nil,
                       message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ThinkingDotsView(isAnimated: !reduceMotion)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.8)))
                    }
                    processStatusView(statusText, summary: activeProcessSummary, isLive: true, generationStartDate: generationStartDate)
                } else if let processSummary = message.processSummary {
                    processStatusView(processSummary.compactText, summary: processSummary, isLive: false, generationStartDate: nil)
                }
            }

            Text(message.text.isEmpty ? " " : message.text)
                .font(messageFont)
                .foregroundStyle(.white)
                .textSelection(.enabled)
        }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .messageBubbleGlass(tint: bubbleTint, isUser: message.role == .user)
            .frame(maxWidth: maxBubbleWidth, alignment: message.role == .user ? .trailing : .leading)
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

                Divider()

                Button {} label: {
                    Label(
                        message.createdAt.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "clock"
                    )
                }
                .disabled(true)
            }
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
                        Text("\(summary.phaseHeading): \(summary.finalPhase.displayName)")

                        if !summary.phasesReached.isEmpty {
                            Text("Phase timeline: \(summary.phasesReached.map(\.displayName).joined(separator: " -> "))")
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !summary.diagnostics.isEmpty {
                            Text("Diagnostics: \(summary.diagnostics.joined(separator: "; "))")
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text("Total generated tokens: \(summary.generatedTokenCount)")

                        if let tokensPerSecondText = summary.tokensPerSecondText {
                            Text("tok/s: \(tokensPerSecondText)")
                        }

                        if let elapsedText = summary.elapsedText {
                            Text("Duration: \(elapsedText)")
                        }

                        if let modelName = summary.modelName {
                            Text("Model: \(modelName)")
                        }

                        if let failureMessage = summary.failureMessage {
                            Text("Error: \(failureMessage)")
                                .lineLimit(2)
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.42))
            }
        }
    }
}

struct ThinkingDotsView: View {
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

struct BouncingDot: View {
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
