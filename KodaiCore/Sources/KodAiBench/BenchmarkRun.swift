import Foundation

struct BenchmarkRun: Codable {
    let experiment_id: String
    let model: String
    let quant: String
    let prompt_id: String
    let tokens_per_sec: Double
    let ttft_ms: Double
    let memory_mb: Double
    let timestamp: String
    let device: String

    static func timestampNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}
