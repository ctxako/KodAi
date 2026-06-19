//
//  SamplerPlaygroundView.swift
//  kodAI_chatbot_dev
//
//  The tuning card behind the kodAI title pill. Every control here edits the
//  live `SamplerKnobs` bound from the chat view model, so changes steer the next
//  real generation — there is no mock visualization. Core knobs live on the card;
//  the rest sit behind an Advanced screen. Each row has an ⓘ that opens a
//  plain-language helper card (see `KnobInfo`). iOS 26 native throughout.
//

import SwiftUI

// MARK: - Tuning card (primary)

struct ModelTuningCard: View {
    /// The live tuning, owned by the chat view model so edits drive generation.
    @Binding var knobs: SamplerKnobs

    @Environment(\.dismiss) private var dismiss
    @State private var info: KnobInfo?

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassEffectContainer(spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        introNote
                        coreKnobs
                        advancedLink
                        resetButton
                    }
                }
                .padding()
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Tuning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $info) { KnobInfoSheet(info: $0) }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.regularMaterial)
    }

    private var introNote: some View {
        Text("Tune how the model writes its replies. Changes apply to the next message in this chat; a brand-new chat resets to the defaults. Tap ⓘ on any control to learn what it does.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var coreKnobs: some View {
        TuningGroup {
            TuningRow(title: "Temperature", value: String(format: "%.2f", knobs.temperature), info: .temperature, onInfo: showInfo) {
                Slider(value: $knobs.temperature, in: SamplerKnobs.minTemperature...2.0, step: 0.05)
            }
            .modifier(DimmedWhenGreedy(active: knobs.deterministic))

            Divider().opacity(0.4)

            TuningRow(title: "Top-K", value: "\(knobs.topK)", info: .topK, onInfo: showInfo) {
                Slider(value: intBinding(\.topK), in: 1...100, step: 1)
            }
            .modifier(DimmedWhenGreedy(active: knobs.deterministic))

            Divider().opacity(0.4)

            TuningRow(title: "Top-P", value: String(format: "%.2f", knobs.topP), info: .topP, onInfo: showInfo) {
                Slider(value: $knobs.topP, in: 0.0...1.0, step: 0.01)
            }
            .modifier(DimmedWhenGreedy(active: knobs.deterministic))

            Divider().opacity(0.4)

            TuningRow(title: "Repeat penalty", value: String(format: "%.2f", knobs.repeatPenalty), info: .repeatPenalty, onInfo: showInfo) {
                Slider(value: $knobs.repeatPenalty, in: 1.0...2.0, step: 0.05)
            }

            Divider().opacity(0.4)

            TuningRow(title: "Max response length", value: "\(knobs.maxOutputTokens)", info: .maxLength, onInfo: showInfo) {
                Slider(value: intBinding(\.maxOutputTokens), in: 64...1024, step: 32)
            }
        }
    }

    private var advancedLink: some View {
        NavigationLink {
            AdvancedTuningView(knobs: $knobs, info: $info)
        } label: {
            HStack {
                Label("Advanced", systemImage: "slider.horizontal.2.square")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    private var resetButton: some View {
        Button {
            withAnimation(.snappy) { knobs = .default }
        } label: {
            Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    private func showInfo(_ knobInfo: KnobInfo) { info = knobInfo }

    /// Bridges an Int knob to the Double a `Slider` needs.
    private func intBinding(_ keyPath: WritableKeyPath<SamplerKnobs, Int>) -> Binding<Double> {
        Binding(
            get: { Double(knobs[keyPath: keyPath]) },
            set: { knobs[keyPath: keyPath] = Int($0) }
        )
    }
}

// MARK: - Advanced screen

struct AdvancedTuningView: View {
    @Binding var knobs: SamplerKnobs
    /// Shared with the card so ⓘ helper sheets present from the same root.
    @Binding var info: KnobInfo?

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    introNote
                    samplingGroup
                    repetitionGroup
                }
            }
            .padding()
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .background(.regularMaterial)
    }

    private var introNote: some View {
        Text("Finer control over how the model picks words and avoids repeating itself. Safe to experiment — Reset on the previous screen restores everything.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var samplingGroup: some View {
        TuningGroup {
            TuningRow(title: "Min-P", value: String(format: "%.2f", knobs.minP), info: .minP, onInfo: showInfo) {
                Slider(value: $knobs.minP, in: 0.0...1.0, step: 0.01)
            }
            .modifier(DimmedWhenGreedy(active: knobs.deterministic))

            Divider().opacity(0.4)

            TuningRow(title: "Deterministic", value: knobs.deterministic ? "On" : "Off", info: .deterministic, onInfo: showInfo) {
                Toggle("Deterministic (greedy)", isOn: $knobs.deterministic)
                    .labelsHidden()
            }

            Divider().opacity(0.4)

            seedRow
        }
    }

    private var seedRow: some View {
        TuningRow(title: "Seed", value: knobs.seed.map { "\($0)" } ?? "Random", info: .seed, onInfo: showInfo) {
            HStack(spacing: 12) {
                Toggle("Lock seed", isOn: seedLocked)
                    .labelsHidden()
                if knobs.seed != nil {
                    Button {
                        knobs.seed = UInt32.random(in: 0...UInt32.max)
                    } label: {
                        Label("Reroll", systemImage: "die.face.5")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var repetitionGroup: some View {
        TuningGroup {
            TuningRow(title: "Frequency penalty", value: String(format: "%.2f", knobs.frequencyPenalty), info: .frequencyPenalty, onInfo: showInfo) {
                Slider(value: $knobs.frequencyPenalty, in: 0.0...2.0, step: 0.05)
            }

            Divider().opacity(0.4)

            TuningRow(title: "Presence penalty", value: String(format: "%.2f", knobs.presencePenalty), info: .presencePenalty, onInfo: showInfo) {
                Slider(value: $knobs.presencePenalty, in: 0.0...2.0, step: 0.05)
            }
        }
    }

    private func showInfo(_ knobInfo: KnobInfo) { info = knobInfo }

    private var seedLocked: Binding<Bool> {
        Binding(
            get: { knobs.seed != nil },
            set: { locked in
                knobs.seed = locked ? (knobs.seed ?? UInt32.random(in: 0...UInt32.max)) : nil
            }
        )
    }
}

// MARK: - Shared row + group

/// A glass card that groups related rows.
private struct TuningGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

/// One labeled control row: title · ⓘ · value on top, the control beneath.
private struct TuningRow<Control: View>: View {
    let title: String
    let value: String
    let info: KnobInfo
    let onInfo: (KnobInfo) -> Void
    @ViewBuilder var control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Button {
                    onInfo(info)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About \(title)")
                Spacer()
                Text(value)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            control
        }
    }
}

/// Dims and disables a row when greedy decoding makes it irrelevant.
private struct DimmedWhenGreedy: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .disabled(active)
            .opacity(active ? 0.35 : 1)
    }
}

// MARK: - Info helper sheet

private struct KnobInfoSheet: View {
    let info: KnobInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(info.body)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(info.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.regularMaterial)
    }
}
