import Foundation

/// POSTs a batch of runs to the bench Worker with Bearer auth.
public struct ResultUploader: Sendable {
    public let endpoint: URL
    public let token: String

    public init(endpoint: URL, token: String) {
        self.endpoint = endpoint
        self.token = token
    }

    public func upload(_ runs: [BenchmarkRun]) async throws {
        var request = URLRequest(url: endpoint.appendingPathComponent("runs"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(runs)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw UploadError.serverError(body)
        }
    }

    public enum UploadError: Error, CustomStringConvertible {
        case serverError(String)
        public var description: String {
            switch self {
            case .serverError(let msg): return "Upload failed: \(msg)"
            }
        }
    }
}
