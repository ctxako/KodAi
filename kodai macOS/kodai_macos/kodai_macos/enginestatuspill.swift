//
//  enginestatuspill.swift
//  kodai_macos
//
//  The "lil thing": a composer-bar pill that always tells the truth about
//  which brain the app is using. Dot color = live health; click opens the
//  engine popover — engine picker, the Ollama setup checklist ("do this,
//  then this" with live re-checks), the running model's real stats (params,
//  quant, VRAM, context from /api/ps), and the last turn's measured speed.
//

import SwiftUI

struct EngineStatusPill: View {
    @Environment(\.kodaiTheme) private var theme

    @Binding var selectedEngine: ChatEngine
    @Binding var ollamaModel: String
    let monitor: EngineHealthMonitor
    let fmAvailable: Bool
    let lastOllamaStats: OllamaTurnStats?

    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover.toggle()
            if selectedEngine == .ollama {
                Task { await monitor.check(model: ollamaModel) }
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                Text(pillLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(0.06), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.08), lineWidth: 0.75) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Engine: \(engineDetailLine)")
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            EnginePopover(
                selectedEngine: $selectedEngine,
                ollamaModel: $ollamaModel,
                monitor: monitor,
                fmAvailable: fmAvailable,
                lastOllamaStats: lastOllamaStats
            )
        }
    }

    private var pillLabel: String {
        switch selectedEngine {
        case .appleFM:
            return "Apple FM"
        case .ollama:
            return ollamaModel.isEmpty ? "Ollama" : ollamaModel
        }
    }

    private var dotColor: Color {
        switch selectedEngine {
        case .appleFM:
            return fmAvailable ? .green : .orange
        case .ollama:
            switch monitor.health {
            case .serverDown: return .red
            case .modelMissing: return .orange
            case .coldStart: return .yellow
            case .ready: return .green
            }
        }
    }

    private var engineDetailLine: String {
        switch selectedEngine {
        case .appleFM:
            return "Apple Foundation Models · on-device · 4096-token window"
        case .ollama:
            switch monitor.health {
            case .serverDown: return "Ollama not reachable"
            case .modelMissing: return "model not installed"
            case .coldStart: return "ready — model loads on first message"
            case .ready(let running): return "\(running.name) · \(running.vramDisplay) VRAM"
            }
        }
    }
}

// MARK: - Popover

private struct EnginePopover: View {
    @Environment(\.kodaiTheme) private var theme

    @Binding var selectedEngine: ChatEngine
    @Binding var ollamaModel: String
    let monitor: EngineHealthMonitor
    let fmAvailable: Bool
    let lastOllamaStats: OllamaTurnStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Engine")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Picker("Engine", selection: $selectedEngine) {
                ForEach(ChatEngine.allCases, id: \.self) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: selectedEngine) { _, engine in
                if engine == .ollama {
                    Task { await monitor.check(model: ollamaModel) }
                }
            }

            Divider().opacity(0.15)

            switch selectedEngine {
            case .appleFM:
                fmSection
            case .ollama:
                ollamaSection
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }

    // MARK: FM

    private var fmSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            checklistRow(
                ok: fmAvailable,
                title: fmAvailable ? "Apple Intelligence ready" : "Apple Intelligence unavailable",
                detail: fmAvailable
                    ? "SystemLanguageModel · on-device · 4096-token window"
                    : "Enable Apple Intelligence in System Settings → Apple Intelligence & Siri"
            )
        }
    }

    // MARK: Ollama

    @ViewBuilder
    private var ollamaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Rung 1 — server
            switch monitor.health {
            case .serverDown:
                checklistRow(
                    ok: false,
                    title: "Ollama isn't running",
                    detail: "1. Install: brew install ollama (or ollama.com)\n2. Start it: open the Ollama app, or run `ollama serve`"
                )
                copyRow(command: "brew install ollama && ollama serve")
            default:
                checklistRow(
                    ok: true,
                    title: "Ollama running",
                    detail: monitor.serverVersion.map { "v\($0) · 127.0.0.1:11434 · local only" } ?? "127.0.0.1:11434"
                )
            }

            // Rung 2 — model
            if case .modelMissing(let installed) = monitor.health {
                checklistRow(
                    ok: false,
                    title: ollamaModel.isEmpty ? "No model selected" : "\(ollamaModel) not installed",
                    detail: installed.isEmpty
                        ? "Pull a model, then re-check:"
                        : "Pick an installed model below, or pull it:"
                )
                if !ollamaModel.isEmpty {
                    copyRow(command: "ollama pull \(ollamaModel)")
                }
            }

            if !monitor.installedModels.isEmpty {
                HStack {
                    Text("Model")
                        .font(.system(size: 12, design: .rounded))
                    Spacer()
                    Picker("Model", selection: $ollamaModel) {
                        if ollamaModel.isEmpty { Text("Select…").tag("") }
                        ForEach(monitor.installedModels, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: ollamaModel) { _, model in
                        Task { await monitor.check(model: model) }
                    }
                }
            }

            // Rung 3 — warm
            switch monitor.health {
            case .coldStart:
                checklistRow(
                    ok: true,
                    title: "Installed — loads on first message",
                    detail: "First reply will be slower while the model loads into memory",
                    icon: "clock"
                )
            case .ready(let running):
                checklistRow(
                    ok: true,
                    title: "\(running.name) loaded",
                    detail: "\(running.parameterSize) · \(running.quantization) · \(running.vramDisplay) VRAM · ctx \(running.contextLength)"
                )
            default:
                EmptyView()
            }

            if let stats = lastOllamaStats {
                Divider().opacity(0.15)
                Text("Last turn — \(stats.model)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("\(Int(stats.tokensPerSecond)) tok/s · \(stats.promptTokens) in · \(stats.outputTokens) out · \(String(format: "%.1f", stats.totalSeconds))s\(stats.loadSeconds > 0.5 ? String(format: " (+%.1fs load)", stats.loadSeconds) : "")")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Divider().opacity(0.15)

            HStack {
                if let checked = monitor.lastChecked {
                    Text("checked \(checked.formatted(date: .omitted, time: .standard))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                Spacer()
                Button {
                    Task { await monitor.check(model: ollamaModel) }
                } label: {
                    if monitor.isChecking {
                        ProgressView().controlSize(.mini)
                    } else {
                        Label("Re-check", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, design: .rounded))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: Rows

    private func checklistRow(ok: Bool, title: String, detail: String, icon: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon ?? (ok ? "checkmark.circle.fill" : "xmark.circle.fill"))
                .font(.system(size: 13))
                .foregroundStyle(ok ? .green : .orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Text(detail)
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func copyRow(command: String) -> some View {
        HStack(spacing: 6) {
            Text(command)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .help("Copy command")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
