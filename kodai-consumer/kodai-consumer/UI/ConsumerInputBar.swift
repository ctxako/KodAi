//
//  ConsumerInputBar.swift
//  kodai-consumer
//
//  A trimmed port of chatbot-dev's InputBar: a multi-line vertical text field
//  with a send button (accent fill when sendable) that swaps to a red stop
//  button while a turn is generating. No glass, no mode menu, no quick chips,
//  no slash-command picker, no mic — just the three colors it needs.
//

import SwiftUI
import UIKit

/// The app's palette — the three colors the input bar needs, plus the two
/// canvas tones the background gradient is built from (see ``CanvasBackground``).
enum ConsumerPalette {
    static let accentBlue = Color(red: 0.184, green: 0.490, blue: 0.965)
    static let elevatedSurface = Color(red: 0.094, green: 0.106, blue: 0.122)
    static let inputField = Color(red: 0.125, green: 0.141, blue: 0.161)
    static let mainCanvas = Color(red: 0.055, green: 0.061, blue: 0.071)
    static let canvasGlow = Color(red: 0.104, green: 0.145, blue: 0.188)
}

struct ConsumerInputBar: View {
    @Binding var text: String
    let isGenerating: Bool
    let isInputFocused: FocusState<Bool>.Binding
    var isDisabled: Bool = false
    let onSend: () -> Void
    let onStop: () -> Void

    private var canSend: Bool {
        !isGenerating && !isDisabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(isDisabled ? "Loading model…" : "What should I do?", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .disabled(isGenerating || isDisabled)
                .focused(isInputFocused)
                .onSubmit(sendIfPossible)
                .padding(.leading, 14)
                .padding(.vertical, 10)
                .accessibilityLabel("What would you like to do?")

            if isGenerating {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.red, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop")
            } else {
                Button(action: sendIfPossible) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(canSend ? ConsumerPalette.accentBlue : ConsumerPalette.elevatedSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 20).fill(ConsumerPalette.inputField))
        .animation(.smooth(duration: 0.18), value: canSend)
        .animation(.smooth(duration: 0.18), value: isGenerating)
    }

    private func sendIfPossible() {
        guard canSend else { return }
        isInputFocused.wrappedValue = false
        // FocusState alone can fail to resign a multi-line (axis: .vertical)
        // TextField, so force the keyboard down as well.
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        onSend()
    }
}
