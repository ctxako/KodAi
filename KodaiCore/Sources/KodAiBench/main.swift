import Foundation
import KodaiBenchKit
import KodaiKernel
import KodaiRuntime

let args = CommandLine.arguments
let config = try parseArgs(args)

let prompts: [BenchPrompt]
if let path = config.promptsPath {
    prompts = try BenchPrompt.load(from: path)
} else {
    prompts = BenchPrompt.defaultSet
}
print("kodai-bench: \(prompts.count) prompts, model=\(config.modelPath)")

let resolver = FilePathModelResolver(path: config.modelPath)
let runtime = LocalModelRuntime(modelFileResolver: resolver)

let modelName = URL(fileURLWithPath: config.modelPath).deletingPathExtension().lastPathComponent
let runner = BenchmarkRunner()
let runs = try await runner.run(
    runtime: runtime,
    modelName: modelName,
    quant: extractQuant(fromModelName: modelName),
    prompts: prompts,
    experimentId: config.experimentId,
    device: config.device,
    knobs: config.knobs,
    log: { print($0) }
)

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
    let promptsPath: String?
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
        fputs("Usage: kodai-bench --model-path <gguf> [--prompts <json>] --experiment-id <id> --device <name> [--endpoint <url>] [--token <bearer>]\n", stderr)
        throw ExitError()
    }

    return BenchConfig(
        modelPath: modelPath,
        promptsPath: flag("--prompts"),
        experimentId: flag("--experiment-id") ?? "unnamed",
        device: flag("--device") ?? "unknown",
        endpoint: flag("--endpoint").flatMap(URL.init(string:)),
        token: flag("--token"),
        knobs: LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M.defaultSamplerKnobs
    )
}

struct ExitError: Error {}
