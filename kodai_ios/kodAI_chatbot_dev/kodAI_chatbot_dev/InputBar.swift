import KodaiKernel
import SwiftUI

private let quickChips: [(label: String, prompt: String)] = [
    ("Haiku", "Write a haiku about the ocean."),
    ("Explain", "Explain gravity in two sentences."),
    ("Continue", "Finish this story: The old house at the end of the street had been empty for years, until—")
]

struct InputBar: View {
    @Binding var text: String

    let isGenerating: Bool
    let isInputFocused: FocusState<Bool>.Binding
    @Binding var modeSelection: AssistantMode
    let onQuickSend: (String) -> Void
    let onSend: () -> Void
    let onStop: () -> Void
    let onSpeechInput: (() -> Void)?

    private var canSend: Bool {
        !isGenerating && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowCommandPicker: Bool {
        guard text.hasPrefix("/"), !isGenerating else { return false }
        let parts = text.split(separator: " ", maxSplits: 1)
        guard let first = parts.first else { return true }
        let commandPart = String(first).lowercased()
        if parts.count > 1 {
            return SlashCommand.all.contains { $0.name == commandPart && $0.acceptsArgument }
                ? false
                : true
        }
        return true
    }

    private var filteredCommands: [SlashCommand] {
        let query = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count > 1 else { return SlashCommand.all }
        return SlashCommand.all.filter { $0.name.lowercased().hasPrefix(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldShowCommandPicker {
                commandPicker
                    .transition(.opacity)
            }

            GlassEffectContainer(spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    HStack(alignment: .center, spacing: 6) {
                        Menu {
                            Picker("Mode", selection: $modeSelection) {
                                ForEach(AssistantMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.inline)

                            Section("Quick Prompts") {
                                ForEach(quickChips, id: \.label) { chip in
                                    Button(chip.label) {
                                        onQuickSend(chip.prompt)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 28, height: 28)
                        }
                        .accessibilityLabel("Quick actions")

                        TextField("Give it a prompt to watch", text: $text, axis: .vertical)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.white)
                            .lineLimit(1...6)
                            .disabled(isGenerating)
                            .focused(isInputFocused)
                            .onSubmit(sendIfPossible)

                        if isGenerating {
                            Button { onStop() } label: {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(.red, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Stop generating")
                        } else if !canSend, let onSpeechInput {
                            Button { onSpeechInput() } label: {
                                Image(systemName: "mic")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(ChatPalette.elevatedSurface, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Dictate message")
                            .transition(.scale.combined(with: .opacity))
                        } else {
                            Button { sendIfPossible() } label: {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(canSend ? ChatPalette.accentBlue : ChatPalette.elevatedSurface, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSend)
                            .accessibilityLabel("Send message")
                        }
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 6)
                    .padding(.vertical, 6)
                    .liquidGlassPanel(tint: .clear, cornerRadius: 20)
                }
            }
            .animation(.smooth(duration: 0.18), value: canSend)
            .animation(.smooth(duration: 0.18), value: isGenerating)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
    }

    private var commandPicker: some View {
        VStack(spacing: 0) {
            if filteredCommands.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "slash.circle")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))

                    Text("No commands")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.62))

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                ForEach(filteredCommands) { command in
                    Button {
                        text = command.name
                        isInputFocused.wrappedValue = true
                    } label: {
                        HStack(spacing: 10) {
                            Text(command.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 84, alignment: .leading)

                            Text(command.description)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.68))
                                .lineLimit(1)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if command.id != filteredCommands.last?.id {
                        Divider()
                            .background(ChatPalette.glassStroke)
                            .padding(.leading, 90)
                    }
                }
            }
        }
        .liquidGlassPanel(tint: ChatPalette.elevatedSurface, cornerRadius: 14)
    }

    private func sendIfPossible() {
        guard canSend else { return }
        isInputFocused.wrappedValue = false
        onSend()
    }
}
