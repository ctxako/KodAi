import Foundation
import KodaiBenchKit

let args = CommandLine.arguments
let config = parseMacArgs(args)

let prompts: [BenchPrompt]
if let path = config.promptsPath {
    prompts = try BenchPrompt.load(from: path)
} else {
    prompts = BenchPrompt.defaultSet
}

let device = config.device ?? DeviceInfo.current
print("kodai-bench-mac: \(prompts.count) prompts, backend=Apple Foundation Model, device=\(device)")

if #available(macOS 26.0, *) {
    let runner = AppleModelRunner()
    let runs = try await runner.run(
        prompts: prompts,
        experimentId: config.experimentId,
        device: device,
        log: { print($0) }
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let jsonData = try encoder.encode(runs)
    print("\n--- Results ---")
    print(String(data: jsonData, encoding: .utf8)!)

    if let endpoint = config.endpoint, let token = config.token {
        print("\nUploading to \(endpoint)...")
        let uploader = ResultUploader(endpoint: endpoint, token: token)
        try await uploader.upload(runs)
        print("Uploaded \(runs.count) runs.")
    }
} else {
    fputs("kodai-bench-mac requires macOS 26.0 or later (Apple Foundation Models).\n", stderr)
    exit(1)
}

// MARK: - Arg parsing

struct MacBenchConfig {
    let promptsPath: String?
    let experimentId: String
    let device: String?
    let endpoint: URL?
    let token: String?
}

func parseMacArgs(_ args: [String]) -> MacBenchConfig {
    func flag(_ name: String) -> String? {
        guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    return MacBenchConfig(
        promptsPath: flag("--prompts"),
        experimentId: flag("--experiment-id") ?? "mac-unnamed",
        device: flag("--device"),
        endpoint: flag("--endpoint").flatMap(URL.init(string:)),
        token: flag("--token")
    )
}
