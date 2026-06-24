import Foundation

/// One measured generation, matching the D1 `runs` schema.
public struct BenchmarkRun: Codable, Sendable {
    public let experiment_id: String
    public let model: String
    public let quant: String
    public let prompt_id: String
    public let tokens_per_sec: Double
    public let ttft_ms: Double
    public let memory_mb: Double
    public let timestamp: String
    public let device: String

    public init(
        experiment_id: String,
        model: String,
        quant: String,
        prompt_id: String,
        tokens_per_sec: Double,
        ttft_ms: Double,
        memory_mb: Double,
        timestamp: String,
        device: String
    ) {
        self.experiment_id = experiment_id
        self.model = model
        self.quant = quant
        self.prompt_id = prompt_id
        self.tokens_per_sec = tokens_per_sec
        self.ttft_ms = ttft_ms
        self.memory_mb = memory_mb
        self.timestamp = timestamp
        self.device = device
    }

    public static func timestampNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}
