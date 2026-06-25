//
//  studioscratchview.swift
//  kodai_macos
//
//  The Studio Scratch Bench — the development pillar. A single-prompt
//  playground: edit the prompt, turn the sampler knobs, and watch the output
//  and metrics move. Cause-and-effect you can feel (raise temperature → more
//  divergence on the local model). The prompt-stack inspector shows exactly
//  what the model is fed and what each block costs in tokens — the honest
//  glass box at the prompt level.
//

import SwiftUI
import Observation
import FoundationModels
import KodaiCore

// MARK: - View model

@Observable
final class StudioScratchViewModel {
    var systemPrompt = "You are a helpful assistant. Keep it under 80 words."
    var userPrompt = "Explain gravity to a five-year-old."
    var knobs = SamplerKnobs(
        temperature: 0.45, topP: 0.92, topK: 40,
        repeatPenalty: 1.05, maxOutputTokens: 256
    )

    private(set) var output = ""
    private(set) var isRunning = false
    private(set) var errorText: String?
    private(set) var tokensPerSec: Double = 0
    private(set) var ttftMs: Double = 0
    private(set) var tokenCount = 0
    private(set) var divergencePercent: Double?
    /// Per-token decision trace (llama only) — the observatory's raw data.
    private(set) var tokenTrace: [TokenDecision] = []

    private var task: Task<Void, Never>?

    struct PromptBlock: Identifiable {
        let id = UUID()
        let label: String
        let text: String
        var tokens: Int { TokenEstimator.estimate(text) }
    }

    var promptBlocks: [PromptBlock] {
        [
            PromptBlock(label: "system", text: systemPrompt),
            PromptBlock(label: "user", text: userPrompt)
        ]
    }
    var totalPromptTokens: Int { promptBlocks.reduce(0) { $0 + $1.tokens } }

    func run(engineKind: StudioEngineKind, modelPath: String) {
        guard !isRunning else { return }
        output = ""; errorText = nil
        tokensPerSec = 0; ttftMs = 0; tokenCount = 0; divergencePercent = nil
        tokenTrace = []
        isRunning = true

        let sys = systemPrompt, usr = userPrompt, knobs = knobs
        let useLlama = engineKind == .localGGUF
            && !modelPath.trimmingCharacters(in: .whitespaces).isEmpty

        task = Task { [weak self] in
            do {
                if useLlama {
                    try await self?.runLlama(modelPath: modelPath, system: sys, user: usr, knobs: knobs)
                } else {
                    try await self?.runFoundationModels(system: sys, user: usr)
                }
            } catch is CancellationError {
            } catch {
                self?.errorText = error.localizedDescription
            }
            self?.isRunning = false
        }
    }

    func cancel() {
        task?.cancel(); task = nil; isRunning = false
    }

    private func runLlama(modelPath: String, system: String, user: String, knobs: SamplerKnobs) async throws {
        let runtime = StudioLocalModel.makeRuntime(for: URL(fileURLWithPath: modelPath))
        let start = ContinuousClock.now
        var ttft: Duration?
        var total = 0, diverged = 0

        let stream = await runtime.generate(
            messages: [KodaiRuntimeMessage(role: .user, text: user)],
            systemPrompt: system,
            samplerKnobs: knobs
        )
        for try await event in stream {
            switch event {
            case .token(let chunk, let count):
                if ttft == nil { ttft = start.duration(to: .now); ttftMs = StudioTiming.milliseconds(ttft!) }
                tokenCount = count
                output += chunk
            case .tokenDecision(let d):
                total += 1
                tokenTrace.append(d)
                if let argmax = d.distribution.alternatives.max(by: { $0.probability < $1.probability }),
                   !argmax.isSelected {
                    diverged += 1
                }
            default:
                break
            }
        }
        let elapsed = StudioTiming.seconds(start.duration(to: .now))
        tokensPerSec = (elapsed > 0 && tokenCount > 0) ? Double(tokenCount) / elapsed : 0
        divergencePercent = total > 0 ? Double(diverged) / Double(total) * 100 : nil
    }

    private func runFoundationModels(system: String, user: String) async throws {
        let session = LanguageModelSession(instructions: system)
        let start = ContinuousClock.now
        var ttft: Duration?
        var snapshots = 0

        for try await snapshot in session.streamResponse(to: user) {
            if ttft == nil && !snapshot.content.isEmpty {
                ttft = start.duration(to: .now); ttftMs = StudioTiming.milliseconds(ttft!)
            }
            snapshots += 1
            output = snapshot.content
        }
        let elapsed = StudioTiming.seconds(start.duration(to: .now))
        let approx = max(snapshots, output.count / 4)
        tokenCount = approx
        tokensPerSec = (elapsed > 0 && approx > 0) ? Double(approx) / elapsed : 0
    }
}

// MARK: - View

struct StudioScratchView: View {
    @Environment(\.kodaiTheme) private var theme
    @Bindable var viewModel: StudioScratchViewModel
    let engineKind: StudioEngineKind
    let modelPath: String

    private var knobsActive: Bool { engineKind == .localGGUF && !modelPath.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            promptEditors
            knobsPanel
            runRow
            if let error = viewModel.errorText { errorBlock(error) }
            if !viewModel.output.isEmpty || viewModel.isRunning { outputBlock }
            if !viewModel.tokenTrace.isEmpty && !viewModel.isRunning {
                StudioObservatoryView(trace: viewModel.tokenTrace)
            }
            inspectorBlock
        }
    }

    // MARK: Prompt editors

    private var promptEditors: some View {
        VStack(alignment: .leading, spacing: 10) {
            promptField("System", text: $viewModel.systemPrompt, height: 56)
            promptField("Prompt", text: $viewModel.userPrompt, height: 72)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .kodaiGlass(cornerRadius: 16)
    }

    private func promptField(_ label: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(theme.secondaryText.opacity(0.7))
            TextEditor(text: text)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: height)
                .background(theme.glassSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(theme.glassBorder, lineWidth: 1) }
                .disabled(viewModel.isRunning)
        }
    }

    // MARK: Sampler knobs

    private var knobsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sampler")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                if !knobsActive {
                    Text("knobs apply to Local GGUF — Foundation Models samples internally")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(theme.secondaryText.opacity(0.7))
                }
            }

            knobSlider("Temperature", value: $viewModel.knobs.temperature, range: 0.05...1.5, spec: "%.2f")
            knobSlider("Top-P", value: $viewModel.knobs.topP, range: 0.1...1.0, spec: "%.2f")
            knobStepper("Top-K", value: $viewModel.knobs.topK, range: 1...100)
            knobSlider("Repeat penalty", value: $viewModel.knobs.repeatPenalty, range: 1.0...1.5, spec: "%.2f")
            knobStepper("Max tokens", value: $viewModel.knobs.maxOutputTokens, range: 16...1024, step: 16)

            Toggle(isOn: $viewModel.knobs.deterministic) {
                Text("Deterministic (greedy — no sampling)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
            }
            .toggleStyle(.switch).tint(theme.primaryAccent)
            .disabled(!knobsActive || viewModel.isRunning)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .kodaiGlass(cornerRadius: 16)
        .opacity(knobsActive ? 1 : 0.55)
    }

    private func knobSlider(_ label: String, value: Binding<Float>, range: ClosedRange<Float>, spec: String) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 11, design: .rounded))
                .foregroundStyle(theme.secondaryText).frame(width: 110, alignment: .leading)
            Slider(value: Binding(get: { Double(value.wrappedValue) },
                                  set: { value.wrappedValue = Float($0) }),
                   in: Double(range.lowerBound)...Double(range.upperBound))
                .tint(theme.primaryAccent)
                .disabled(!knobsActive || viewModel.isRunning)
            Text(String(format: spec, value.wrappedValue))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.primaryText).frame(width: 44, alignment: .trailing)
        }
    }

    private func knobStepper(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 11, design: .rounded))
                .foregroundStyle(theme.secondaryText).frame(width: 110, alignment: .leading)
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.primaryText)
            }
            .disabled(!knobsActive || viewModel.isRunning)
            Spacer()
        }
    }

    // MARK: Run

    private var runRow: some View {
        HStack(spacing: 14) {
            if viewModel.isRunning {
                Button(role: .cancel) { viewModel.cancel() } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                }
                .buttonStyle(.plain).foregroundStyle(theme.primaryText)
                .background(theme.glassSurface, in: Capsule())
                .overlay { Capsule().stroke(theme.glassBorder, lineWidth: 1) }
            } else {
                Button { viewModel.run(engineKind: engineKind, modelPath: modelPath) } label: {
                    Label("Run once", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .background(theme.primaryAccent.opacity(0.9), in: Capsule())
            }

            if viewModel.tokenCount > 0 {
                metric("tok/s", String(format: "%.1f", viewModel.tokensPerSec))
                metric("TTFT", String(format: "%.0f ms", viewModel.ttftMs))
                metric("tokens", "\(viewModel.tokenCount)")
                if let div = viewModel.divergencePercent {
                    metric("divergence", String(format: "%.1f%%", div))
                }
            }
            Spacer()
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.primaryText)
            Text(label).font(.system(size: 9, design: .rounded))
                .foregroundStyle(theme.secondaryText.opacity(0.7))
        }
    }

    // MARK: Output

    private var outputBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output").font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.secondaryText)
            Text(viewModel.output.isEmpty ? "…" : viewModel.output)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .kodaiGlass(cornerRadius: 16)
    }

    private func errorBlock(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(.orange)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .kodaiGlass(cornerRadius: 14)
    }

    // MARK: Prompt-stack inspector (the honest glass box at prompt level)

    private var inspectorBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Prompt stack — what the model is fed")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.secondaryText)

            ForEach(viewModel.promptBlocks) { block in
                HStack(spacing: 10) {
                    Image(systemName: block.label == "system" ? "gearshape" : "person.fill")
                        .font(.system(size: 11)).frame(width: 16)
                        .foregroundStyle(theme.secondaryText)
                    Text(block.label)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                    Spacer()
                    Text("~\(block.tokens) tok")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                }
                .padding(.vertical, 2)
            }

            Divider().overlay(theme.glassBorder)
            HStack {
                Spacer()
                Text("~\(viewModel.totalPromptTokens) prompt tokens (est.)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .kodaiGlass(cornerRadius: 16)
    }
}
