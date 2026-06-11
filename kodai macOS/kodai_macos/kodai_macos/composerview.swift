//
//  composerview.swift
//  kodai_macos
//

import SwiftUI

struct ComposerView: View {
    @Binding var inputText: String
    @Binding var selectedMode: OutputMode
    @FocusState.Binding var composerFocused: Bool

    let isLoading: Bool
    let isSummarizing: Bool
    let telemetry: ChatTelemetry

    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(telemetry.composerBarText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)

                    if isSummarizing {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white.opacity(0.45))
                            Text("summarizing")
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .transition(.opacity)
                    }

                    Spacer(minLength: 4)

                    ContextArcView(
                        percent: telemetry.contextPercent,
                        activeTokens: telemetry.activeTokens,
                        contextWindowSize: telemetry.contextWindowSize,
                        color: telemetry.contextRiskColor
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)

                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Message Kodai...")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $inputText)
                        .focused($composerFocused)
                        .font(.system(.body, design: .rounded))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 35, maxHeight: 110)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .onKeyPress(.return, phases: .down) { press in
                            if press.modifiers.contains(.shift) {
                                return .ignored
                            }
                            let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty, !isLoading else { return .handled }
                            onSend()
                            return .handled
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .kodaiGlass(cornerRadius: 22)

            Button {
                    if isLoading {
                        onStop()
                    } else {
                        onSend()
                    }
                } label: {
                    Image(systemName: isLoading ? "stop.fill" : "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 42, height: 42)
                }
            .buttonStyle(.borderedProminent)
            .clipShape(Circle())
            .disabled(!isLoading && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
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
