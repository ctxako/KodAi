import Foundation
import KodaiKernel
import KodaiRuntime

let args = CommandLine.arguments
let config = try parseArgs(args)

let prompts = try loadPrompts(from: config.promptsPath)
print("kodai-bench: \(prompts.count) prompts, model=\(config.modelPath)")

let resolver = FilePathModelResolver(path: config.modelPath)
let runtime = LocalModelRuntime(modelFileResolver: resolver)

// Warmup — load the model and prime Metal before timing, so the first measured
// prompt doesn't absorb cold-start model-load latency.
print("warmup … ", terminator: "")
fflush(stdout)
let warmupStream = await runtime.generate(
    messages: [KodaiRuntimeMessage(role: .user, text: "Hi")],
    systemPrompt: "Reply with one word.",
    samplerKnobs: config.knobs
)
for try await _ in warmupStream {}
print("ready")

var runs: [BenchmarkRun] = []

for (i, prompt) in prompts.enumerated() {
    print("[\(i+1)/\(prompts.count)] \"\(prompt.id)\" ... ", terminator: "")
    fflush(stdout)

    let memBefore = MemoryMeasurement.physicalFootprintMB()
    let startTime = ContinuousClock.now

    var tokenCount = 0
    var ttftDuration: Duration?
    var output = ""

    let messages = [KodaiRuntimeMessage(role: .user, text: prompt.text)]
    let stream = await runtime.generate(
        messages: messages,
        systemPrompt: prompt.system ?? "You are a helpful assistant.",
        samplerKnobs: config.knobs
    )

    for try await event in stream {
        switch event {
        case .token(let text, let count):
            if ttftDuration == nil {
                ttftDuration = startTime.duration(to: .now)
            }
            tokenCount = count
            output += text
        case .done:
            break
        default:
            break
        }
    }

    let elapsed = startTime.duration(to: .now)
    let elapsedSec = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    let memAfter = MemoryMeasurement.physicalFootprintMB()

    let tokPerSec = tokenCount > 0 ? Double(tokenCount) / elapsedSec : 0
    let ttftMs: Double
    if let ttft = ttftDuration {
        ttftMs = Double(ttft.components.seconds) * 1000 + Double(ttft.components.attoseconds) / 1e15
    } else {
        ttftMs = -1
    }

    let run = BenchmarkRun(
        experiment_id: config.experimentId,
        model: URL(fileURLWithPath: config.modelPath).deletingPathExtension().lastPathComponent,
        quant: extractQuant(from: config.modelPath),
        prompt_id: prompt.id,
        tokens_per_sec: tokPerSec,
        ttft_ms: ttftMs,
        memory_mb: memAfter > 0 ? memAfter : memBefore,
        timestamp: BenchmarkRun.timestampNow(),
        device: config.device
    )
    runs.append(run)

    print(String(format: "%.1f tok/s, TTFT %.0fms, %.0fMB", tokPerSec, ttftMs, run.memory_mb))
}

let jsonData = try JSONEncoder.prettyPrinting.encode(runs)
print("\n--- Results ---")
print(String(data: jsonData, encoding: .utf8)!)

if let endpoint = config.endpoint, let token = config.token {
    print("\nUploading to \(endpoint)...")
    let uploader = ResultUploader(endpoint: endpoint, token: token)
    try await uploader.upload(runs)
    print("Uploaded \(runs.count) runs.")
}

private extension JSONEncoder {
    static let prettyPrinting: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

// MARK: - Arg parsing

struct BenchConfig {
    let modelPath: String
    let promptsPath: String
    let experimentId: String
    let device: String
    let endpoint: URL?
    let token: String?
    let knobs: SamplerKnobs
}

func parseArgs(_ args: [String]) throws -> BenchConfig {
    func flag(_ name: String) -> String? {
        guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    guard let modelPath = flag("--model-path") else {
        fputs("Usage: KodAiBench --model-path <gguf> --prompts <json> --experiment-id <id> --device <name> [--endpoint <url>] [--token <bearer>]\n", stderr)
        throw ExitError()
    }

    return BenchConfig(
        modelPath: modelPath,
        promptsPath: flag("--prompts") ?? "prompts.json",
        experimentId: flag("--experiment-id") ?? "unnamed",
        device: flag("--device") ?? "unknown",
        endpoint: flag("--endpoint").flatMap(URL.init(string:)),
        token: flag("--token"),
        knobs: LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M.defaultSamplerKnobs
    )
}

struct ExitError: Error {}

// MARK: - Prompts

struct BenchPrompt: Codable {
    let id: String
    let text: String
    let system: String?
}

func loadPrompts(from path: String) throws -> [BenchPrompt] {
    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode([BenchPrompt].self, from: data)
}

// MARK: - Helpers

func extractQuant(from path: String) -> String {
    let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    let quantPatterns = ["Q2_K", "Q3_K_S", "Q3_K_M", "Q3_K_L", "Q4_0", "Q4_K_S", "Q4_K_M",
                         "Q5_0", "Q5_K_S", "Q5_K_M", "Q6_K", "Q8_0", "F16", "F32"]
    let upper = name.uppercased()
    for q in quantPatterns {
        if upper.contains(q) { return q }
    }
    return "unknown"
}
