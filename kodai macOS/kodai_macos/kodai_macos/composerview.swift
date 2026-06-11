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
    let telemetry: ChatTelemetry

    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Text(telemetry.composerBarText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)

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
