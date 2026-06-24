import Foundation

/// One fixed prompt in a benchmark set.
public struct BenchPrompt: Codable, Sendable {
    public let id: String
    public let text: String
    public let system: String?

    public init(id: String, text: String, system: String? = nil) {
        self.id = id
        self.text = text
        self.system = system
    }

    /// Load a prompt set from a JSON file (CLI `--prompts`).
    public static func load(from path: String) throws -> [BenchPrompt] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode([BenchPrompt].self, from: data)
    }

    /// The canonical set, embedded in code so every device runs the same
    /// prompts without shipping a JSON file. Keep in sync across platforms
    /// for clean cross-device comparison.
    public static let defaultSet: [BenchPrompt] = [
        BenchPrompt(
            id: "greeting",
            text: "Hello, how are you today?",
            system: "You are a helpful assistant. Keep your response under 50 words."
        ),
        BenchPrompt(
            id: "explain-gravity",
            text: "Explain gravity to a five-year-old in simple terms.",
            system: "You are a science teacher for young children. Keep your response under 100 words."
        ),
        BenchPrompt(
            id: "code-fizzbuzz",
            text: "Write a FizzBuzz implementation in Python.",
            system: "You are a coding assistant. Provide only the code with brief comments."
        ),
        BenchPrompt(
            id: "summarize-short",
            text: "Summarize the key differences between TCP and UDP protocols.",
            system: "You are a networking expert. Be concise."
        ),
        BenchPrompt(
            id: "creative-haiku",
            text: "Write three haiku about the ocean.",
            system: "You are a poet. Respond only with the haiku."
        ),
    ]
}

/// Best-effort quantization label from a GGUF file name (e.g. "Q4_K_M").
public func extractQuant(fromModelName name: String) -> String {
    let quantPatterns = ["Q2_K", "Q3_K_S", "Q3_K_M", "Q3_K_L", "Q4_0", "Q4_K_S", "Q4_K_M",
                         "Q5_0", "Q5_K_S", "Q5_K_M", "Q6_K", "Q8_0", "F16", "F32"]
    let upper = name.uppercased()
    for q in quantPatterns where upper.contains(q) {
        return q
    }
    return "unknown"
}
