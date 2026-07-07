//
//  kodaicomposerbar.swift
//  kodai_macos
//

import SwiftUI

struct KodaiComposerBar: View {
    private enum Metrics {
        static let cornerRadius: CGFloat = 18
        static let horizontalPadding: CGFloat = 12
        static let sendButtonSize: CGFloat = 44
    }

    @Environment(\.kodaiTheme) private var theme

    @Binding var inputText: String
    @FocusState.Binding var composerFocused: Bool

    let isLoading: Bool
    let isSummarizing: Bool
    let telemetry: ChatTelemetry

    @Binding var selectedEngine: ChatEngine
    @Binding var ollamaModel: String
    let engineHealth: EngineHealthMonitor
    let fmAvailable: Bool
    let lastOllamaStats: OllamaTurnStats?

    let onSend: () -> Void
    let onStop: () -> Void

    @AppStorage("composerHintDismissed") private var hintDismissed = false

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activityText: String? {
        if isSummarizing {
            return "summarizing"
        }
        if isLoading {
            return "generating"
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if !hintDismissed {
                HStack(spacing: 6) {
                    Text("Tip: Use /task to create tasks from chat")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            hintDismissed = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message Kodai...", text: $inputText, axis: .vertical)
                        .focused($composerFocused)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .rounded))
                        .lineLimit(1...5)
                        .padding(.leading, Metrics.horizontalPadding)
                        .padding(.trailing, 4)
                        .padding(.vertical, 8)
                        .onKeyPress(.return, phases: .down) { press in
                            if press.modifiers.contains(.shift) {
                                return .ignored
                            }
                            guard !trimmedInput.isEmpty, !isLoading else { return .handled }
                            onSend()
                            return .handled
                        }

                    Button {
                        if isLoading {
                            onStop()
                        } else {
                            onSend()
                        }
                    } label: {
                        Image(systemName: isLoading ? "stop.fill" : "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .frame(
                                width: Metrics.sendButtonSize,
                                height: Metrics.sendButtonSize
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Circle())
                    .disabled(!isLoading && trimmedInput.isEmpty)
                    .padding(.trailing, 4)
                }
                .frame(minHeight: Metrics.sendButtonSize)

                HStack(spacing: 8) {
                    EngineStatusPill(
                        selectedEngine: $selectedEngine,
                        ollamaModel: $ollamaModel,
                        monitor: engineHealth,
                        fmAvailable: fmAvailable,
                        lastOllamaStats: lastOllamaStats
                    )

                    Text(telemetry.composerBarText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.46))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let activityText {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white.opacity(0.4))
                            Text(activityText)
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.38))
                        }
                        .transition(.opacity)
                    }

                    ContextArcView(
                        percent: telemetry.contextPercent,
                        activeTokens: telemetry.activeTokens,
                        contextWindowSize: telemetry.contextWindowSize,
                        color: telemetry.contextRiskColor
                    )
                }
                .padding(.horizontal, Metrics.horizontalPadding)
                .padding(.vertical, 6)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(.white.opacity(0.055))
                        .frame(height: 0.5)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                            .fill(theme.glassSurface)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 0.75)
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
    }
}

private struct ContextArcView: View {
    let percent: Int
    let activeTokens: Int
    let contextWindowSize: Int
    let color: Color

    @State private var isHovering = false
    private var fraction: Double { min(Double(percent) / 100.0, 1.0) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.10), lineWidth: 2)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    color.opacity(fraction < 0.02 ? 0 : 1),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: fraction)
        }
        .frame(width: 18, height: 18)
        .onHover { isHovering = $0 }
        .popover(isPresented: $isHovering, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(percent)%")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)

                Text("\(formatCount(activeTokens)) / \(formatCount(contextWindowSize))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .preferredColorScheme(.dark)
        }
    }

    private func formatCount(_ n: Int) -> String {
        guard n >= 1_000 else { return "\(n)" }
        return String(format: "%d,%03d", n / 1_000, n % 1_000)
    }
}
