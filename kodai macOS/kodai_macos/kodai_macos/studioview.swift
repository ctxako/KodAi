//
//  studioview.swift
//  kodai_macos
//
//  The Studio — a native analytical dashboard for testing the on-device
//  models. Follows benchmarking protocol at learning-lab scale: each prompt is
//  run N times and shown as mean ± σ with the raw samples overlaid, latency as
//  p50/p90, plus a local run history you can A/B compare.
//

import SwiftUI
import Charts
import UniformTypeIdentifiers

struct StudioView: View {
    @Environment(\.kodaiTheme) private var theme

    @Bindable var viewModel: StudioViewModel
    let onClose: () -> Void

    @AppStorage("studio.upload.enabled") private var uploadEnabled = false
    @AppStorage("studio.upload.endpoint") private var uploadEndpoint = "https://bench-api.ctxa.ltd"
    @AppStorage("studio.upload.token") private var uploadToken = ""

    @State private var selectedMetric: StudioMetric = .throughput
    @State private var engineKind: StudioEngineKind = .foundationModels
    @State private var showModelImporter = false
    @AppStorage("studio.model.path") private var modelPath = ""

    @State private var studioMode: StudioMode = .suite
    @State private var scratchViewModel = StudioScratchViewModel()

    private enum StudioMode: String, CaseIterable, Identifiable {
        case suite, scratch
        var id: String { rawValue }
        var title: String { self == .suite ? "Suite" : "Scratch" }
    }

    private let cards = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                engineBar
                modeToggle

                if studioMode == .scratch {
                    StudioScratchView(
                        viewModel: scratchViewModel,
                        engineKind: engineKind,
                        modelPath: modelPath
                    )
                } else {
                    controlBar
                    if viewModel.isRunning { runProgressBar }
                    uploadBar

                    if viewModel.liveStats.isEmpty {
                        emptyOrError
                    } else {
                        summaryGrid
                        metricChart
                        tradeoffChart
                        resultsTable
                    }

                    if !viewModel.runs.isEmpty {
                        historySection
                        if let a = viewModel.run(for: viewModel.compareA),
                           let b = viewModel.run(for: viewModel.compareB) {
                            compareSection(a, b)
                        }
                    }
                }
            }
            .padding(34)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("studio.detail")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Studio")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
                Text("Local model analytics · testing")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            Button(action: onClose) {
                Label("Back to chat", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .accessibilityIdentifier("studio.backToChat")
            .buttonStyle(.plain)
            .foregroundStyle(theme.secondaryText)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .contentShape(Capsule())
            .background(theme.glassSurface, in: Capsule())
            .overlay { Capsule().stroke(theme.glassBorder, lineWidth: 1) }
        }
    }

    // MARK: Mode toggle

    private var modeToggle: some View {
        HStack(spacing: 10) {
            Picker("Mode", selection: $studioMode) {
                ForEach(StudioMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 200)
            Text(studioMode == .suite
                 ? "Batch the fixed suite with repetitions and statistics."
                 : "One prompt, live — turn the knobs and watch the output move.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(theme.secondaryText.opacity(0.7))
            Spacer()
        }
    }

    // MARK: Engine bar

    private var engineBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("Engine", selection: $engineKind) {
                    ForEach(StudioEngineKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260)
                .disabled(viewModel.isRunning)

                if engineKind == .localGGUF {
                    Button { showModelImporter = true } label: {
                        Label(modelFileLabel, systemImage: "folder")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain).foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .kodaiGlass(cornerRadius: 12)
                    .disabled(viewModel.isRunning)
                }
                Spacer()
            }
            if engineKind == .localGGUF {
                Text("Load a .gguf (e.g. LFM2.5-1.2B-Instruct-Q4_K_M) — runs through the same harness with real token counts and divergence telemetry. Apple-silicon Mac recommended.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(theme.secondaryText.opacity(0.7))
            }
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .kodaiGlass(cornerRadius: 14)
        .fileImporter(
            isPresented: $showModelImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                modelPath = url.path
            }
        }
    }

    private var modelFileLabel: String {
        modelPath.isEmpty ? "Choose .gguf…" : URL(fileURLWithPath: modelPath).lastPathComponent
    }

    // MARK: Control bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            pill(icon: "cpu", text: viewModel.engineLabel)
            pill(icon: "desktopcomputer", text: viewModel.device)

            HStack(spacing: 6) {
                Text("Exp")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                TextField("experiment id", text: $viewModel.experimentId)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 130)
                Button { viewModel.regenerateExperimentId() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .kodaiGlass(cornerRadius: 12)

            repsControl

            Spacer()
            runButton
        }
    }

    private var repsControl: some View {
        HStack(spacing: 6) {
            Text("Reps")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
            Stepper(
                value: $viewModel.repetitions,
                in: 1...10
            ) {
                Text("\(viewModel.repetitions)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.primaryText)
                    .frame(minWidth: 16)
            }
            .labelsHidden()
            .disabled(viewModel.isRunning)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .kodaiGlass(cornerRadius: 12)
    }

    @ViewBuilder
    private var runButton: some View {
        if viewModel.isRunning {
            Button(role: .cancel) { viewModel.cancel() } label: {
                Label("Stop · \(viewModel.progressPercent)%", systemImage: "stop.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: viewModel.progressPercent)
                    .padding(.horizontal, 16).padding(.vertical, 9)
            }
            .buttonStyle(.plain).foregroundStyle(theme.primaryText)
            .background(theme.glassSurface, in: Capsule())
            .overlay { Capsule().stroke(theme.glassBorder, lineWidth: 1) }
        } else {
            Button {
                viewModel.run(
                    engineKind: engineKind,
                    modelPath: modelPath,
                    uploadEndpoint: uploadEnabled ? uploadEndpoint : nil,
                    uploadToken: uploadEnabled ? uploadToken : nil
                )
            } label: {
                Label("Run benchmark", systemImage: "play.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 16).padding(.vertical, 9)
            }
            .buttonStyle(.plain).foregroundStyle(.white)
            .background(theme.primaryAccent.opacity(0.9), in: Capsule())
            .disabled(engineKind == .localGGUF && modelPath.isEmpty)
        }
    }

    // MARK: Run progress

    private var runProgressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(runProgressLabel)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Text("\(viewModel.progressPercent)%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.primaryText)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: viewModel.progressPercent)
            }
            ProgressView(value: viewModel.progressFraction)
                .progressViewStyle(.linear)
                .tint(theme.primaryAccent)
        }
        .padding(14).frame(maxWidth: .infinity)
        .kodaiGlass(cornerRadius: 14)
    }

    private var runProgressLabel: String {
        if case .running(let progress) = viewModel.state {
            return viewModel.liveStats.isEmpty ? "warming up …" : progress
        }
        return "running …"
    }

    // MARK: Upload bar

    private var uploadBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $uploadEnabled) {
                Text("Upload prompt means to D1 (the gallery's system of record)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
            }
            .toggleStyle(.switch).tint(theme.primaryAccent)

            if uploadEnabled {
                HStack(spacing: 8) {
                    TextField("https://bench-api.ctxa.ltd", text: $uploadEndpoint)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.primaryText)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .kodaiGlass(cornerRadius: 10)
                    SecureField("bench token", text: $uploadToken)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.primaryText)
                        .frame(width: 180)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .kodaiGlass(cornerRadius: 10)
                }
            }
            if let message = viewModel.lastUploadMessage {
                Text(message)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(theme.secondaryText.opacity(0.85))
            }
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .kodaiGlass(cornerRadius: 14)
    }

    // MARK: Empty / running / error

    @ViewBuilder
    private var emptyOrError: some View {
        switch viewModel.state {
        case .failed(let message):
            statusBlock(icon: "exclamationmark.triangle", title: "Run failed", detail: message)
        case .running(let progress):
            statusBlock(icon: "hourglass", title: "Running …", detail: progress)
        default:
            statusBlock(
                icon: "chart.bar.xaxis",
                title: "Run the suite",
                detail: "\(viewModel.prompts.count) prompts × \(viewModel.repetitions) reps through \(viewModel.engineLabel), measured in-process. Press Run benchmark."
            )
        }
    }

    private func statusBlock(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30, weight: .light))
                .foregroundStyle(theme.secondaryText)
            Text(title).font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.primaryText)
            Text(detail).font(.system(size: 12, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center).frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
        .kodaiGlass(cornerRadius: 18)
    }

    // MARK: Summary

    private var summaryGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: cards, spacing: 10) {
                summaryCard(
                    "Throughput",
                    String(format: "%.1f", viewModel.averageThroughput),
                    sub: String(format: "± %.1f tok/s (1σ)", viewModel.typicalThroughputSigma)
                )
                summaryCard(
                    "TTFT p50 / p90",
                    String(format: "%.0f / %.0f", viewModel.latencyP50, viewModel.latencyP90),
                    sub: "ms — lower is better"
                )
                summaryCard(
                    "Peak memory",
                    String(format: "%.0f MB", viewModel.peakMemoryMB),
                    sub: "physical footprint"
                )
                summaryCard("Thermal", viewModel.peakThermal.capitalized, sub: "state at last prompt")
            }
            if viewModel.activeApproxTokens {
                Label(
                    "≈ throughput approximated from text length — Foundation Models reports no token count.",
                    systemImage: "info.circle"
                )
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(theme.secondaryText.opacity(0.75))
            } else if let divergence = viewModel.meanDivergence {
                Label(
                    String(format: "sampler diverged from the argmax on %.1f%% of tokens — the observatory's \u{201C}gold\u{201D}.", divergence * 100),
                    systemImage: "sparkles"
                )
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(theme.secondaryText.opacity(0.75))
            }
        }
    }

    private func summaryCard(_ title: String, _ value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
            Text(value).font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.primaryText).lineLimit(1)
            Text(sub).font(.system(size: 9, design: .rounded))
                .foregroundStyle(theme.secondaryText.opacity(0.7)).lineLimit(1)
        }
        .padding(13).frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .kodaiGlass(cornerRadius: 14)
    }

    // MARK: Primary chart — mean bars + ±σ whiskers + raw sample points

    private var metricChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Per prompt — mean, spread, samples")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Picker("Metric", selection: $selectedMetric) {
                    ForEach(StudioMetric.allCases) { Text($0.shortTitle).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 280)
            }

            Chart {
                ForEach(viewModel.liveStats) { stat in
                    let s = selectedMetric.stats(stat)
                    BarMark(
                        x: .value("Prompt", stat.id),
                        y: .value(selectedMetric.shortTitle, s.mean)
                    )
                    .foregroundStyle(theme.primaryAccent.gradient)
                    .cornerRadius(4)
                    .annotation(position: .top, alignment: .center) {
                        Text(selectedMetric.format(s.mean))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                    }

                    if s.stdDev > 0 {
                        RuleMark(
                            x: .value("Prompt", stat.id),
                            yStart: .value("low", max(0, s.mean - s.stdDev)),
                            yEnd: .value("high", s.mean + s.stdDev)
                        )
                        .foregroundStyle(theme.primaryText.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    }

                    ForEach(Array(selectedMetric.rawSamples(stat).enumerated()), id: \.offset) { _, value in
                        PointMark(
                            x: .value("Prompt", stat.id),
                            y: .value(selectedMetric.shortTitle, value)
                        )
                        .symbolSize(20)
                        .foregroundStyle(theme.primaryText.opacity(0.45))
                    }
                }
            }
            .chartYAxisLabel(selectedMetric.axisLabel)
            .frame(height: 240)
            .foregroundStyle(theme.secondaryText)

            Text(selectedMetric.legend)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(theme.secondaryText.opacity(0.7))
        }
        .padding(16).frame(maxWidth: .infinity)
        .kodaiGlass(cornerRadius: 16)
    }

    // MARK: Tradeoff scatter

    private var tradeoffChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Latency vs throughput")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.secondaryText)

            Chart(viewModel.liveStats) { stat in
                PointMark(
                    x: .value("TTFT (ms)", stat.latency.mean),
                    y: .value("tok/s", stat.throughput.mean)
                )
                .symbolSize(memorySymbolSize(stat))
                .foregroundStyle(theme.primaryAccent.opacity(0.85))
                .annotation(position: .top, alignment: .center, spacing: 3) {
                    Text(stat.id).font(.system(size: 9, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .chartXAxisLabel("mean time to first token (ms) — lower is better")
            .chartYAxisLabel("mean tokens / sec — higher is better")
            .frame(height: 230)
            .foregroundStyle(theme.secondaryText)

            Text("Each point is one prompt (mean of reps); bubble size ≈ peak memory. Top-left is the sweet spot.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(theme.secondaryText.opacity(0.7))
        }
        .padding(16).frame(maxWidth: .infinity)
        .kodaiGlass(cornerRadius: 16)
    }

    private func memorySymbolSize(_ stat: PromptStats) -> Double {
        let mems = viewModel.liveStats.map(\.memory.mean)
        guard let lo = mems.min(), let hi = mems.max(), hi > lo else { return 140 }
        let t = (stat.memory.mean - lo) / (hi - lo)
        return 70 + t * 240
    }

    // MARK: Results table

    private var resultsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                tableHead("Prompt", width: nil)
                tableHead("tok/s ±σ", width: 110)
                tableHead("TTFT", width: 80)
                tableHead("Memory", width: 90)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider().overlay(theme.glassBorder)

            ForEach(viewModel.liveStats) { stat in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.id).font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                        Text(stat.preview).font(.system(size: 10, design: .rounded))
                            .foregroundStyle(theme.secondaryText.opacity(0.7)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    tableCell(String(format: "%.1f ±%.1f", stat.throughput.mean, stat.throughput.stdDev), width: 110)
                    tableCell(String(format: "%.0fms", stat.latency.mean), width: 80)
                    tableCell(String(format: "%.0fMB", stat.memory.maximum), width: 90)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                if stat.id != viewModel.liveStats.last?.id {
                    Divider().overlay(theme.glassBorder.opacity(0.5))
                }
            }
        }
        .padding(.vertical, 4).frame(maxWidth: .infinity)
        .kodaiGlass(cornerRadius: 16)
    }

    // MARK: Run history + A/B compare

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Run history")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.secondaryText)
            Text("Tap two runs to A/B compare.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(theme.secondaryText.opacity(0.7))

            ForEach(viewModel.runs) { run in
                historyRow(run)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .kodaiGlass(cornerRadius: 16)
    }

    private func historyRow(_ run: StudioRun) -> some View {
        let slot = compareSlot(run.id)
        return HStack(spacing: 10) {
            ZStack {
                Circle().stroke(theme.glassBorder, lineWidth: 1).frame(width: 20, height: 20)
                if let slot {
                    Circle().fill(theme.primaryAccent.opacity(0.9)).frame(width: 20, height: 20)
                    Text(slot).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(run.shortLabel).font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.primaryText)
                Text("\(run.repetitions) reps · \(String(format: "%.1f", run.avgThroughput)) tok/s · \(String(format: "%.0f", run.avgLatency)) ms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.secondaryText.opacity(0.8))
            }
            Spacer()
            Button { viewModel.deleteRun(run) } label: {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundStyle(theme.secondaryText.opacity(0.6))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(slot != nil ? theme.primaryAccent.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { toggleCompare(run.id) }
    }

    private func compareSlot(_ id: UUID) -> String? {
        if viewModel.compareA == id { return "A" }
        if viewModel.compareB == id { return "B" }
        return nil
    }

    private func toggleCompare(_ id: UUID) {
        if viewModel.compareA == id { viewModel.compareA = nil; return }
        if viewModel.compareB == id { viewModel.compareB = nil; return }
        if viewModel.compareA == nil { viewModel.compareA = id }
        else if viewModel.compareB == nil { viewModel.compareB = id }
        else { viewModel.compareB = viewModel.compareA; viewModel.compareA = id }
    }

    private func compareSection(_ a: StudioRun, _ b: StudioRun) -> some View {
        let dThroughput = b.avgThroughput - a.avgThroughput
        let dLatency = b.avgLatency - a.avgLatency
        return VStack(alignment: .leading, spacing: 12) {
            Text("A/B compare")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.secondaryText)

            HStack(spacing: 10) {
                compareDelta("Δ throughput", dThroughput, unit: "tok/s", higherBetter: true)
                compareDelta("Δ latency", dLatency, unit: "ms", higherBetter: false)
                compareDelta("Δ peak mem", b.peakMemory - a.peakMemory, unit: "MB", higherBetter: false)
            }

            Chart {
                ForEach(comparePairs(a, b), id: \.key) { pair in
                    BarMark(
                        x: .value("Prompt", pair.prompt),
                        y: .value("tok/s", pair.value)
                    )
                    .position(by: .value("Run", pair.run))
                    .foregroundStyle(by: .value("Run", pair.run))
                }
            }
            .chartForegroundStyleScale([
                "A: \(a.modelName)": theme.secondaryText.opacity(0.7),
                "B: \(b.modelName)": theme.primaryAccent
            ])
            .chartYAxisLabel("tokens / sec")
            .frame(height: 220)
            .foregroundStyle(theme.secondaryText)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .kodaiGlass(cornerRadius: 16)
    }

    private struct ComparePair { let key: String; let prompt: String; let run: String; let value: Double }

    private func comparePairs(_ a: StudioRun, _ b: StudioRun) -> [ComparePair] {
        let aLabel = "A: \(a.modelName)"
        let bLabel = "B: \(b.modelName)"
        var pairs: [ComparePair] = []
        for p in a.prompts {
            pairs.append(ComparePair(key: "\(p.id)-A", prompt: p.id, run: aLabel, value: p.throughput.mean))
        }
        for p in b.prompts {
            pairs.append(ComparePair(key: "\(p.id)-B", prompt: p.id, run: bLabel, value: p.throughput.mean))
        }
        return pairs
    }

    private func compareDelta(_ title: String, _ value: Double, unit: String, higherBetter: Bool) -> some View {
        let good = higherBetter ? value > 0 : value < 0
        let color: Color = abs(value) < 0.05 ? theme.secondaryText : (good ? .green : .orange)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
            Text(String(format: "%@%.1f %@", value >= 0 ? "+" : "", value, unit))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .kodaiGlass(cornerRadius: 12)
    }

    // MARK: Bits

    private func tableHead(_ text: String, width: CGFloat?) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .textCase(.uppercase)
            .foregroundStyle(theme.secondaryText.opacity(0.7))
            .frame(width: width, alignment: width == nil ? .leading : .trailing)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func tableCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(theme.primaryText.opacity(0.9))
            .frame(width: width, alignment: .trailing)
    }

    private func pill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text).font(.system(size: 12, weight: .medium, design: .rounded)).lineLimit(1)
        }
        .foregroundStyle(theme.secondaryText)
        .padding(.horizontal, 11).padding(.vertical, 8)
        .kodaiGlass(cornerRadius: 12)
    }
}
