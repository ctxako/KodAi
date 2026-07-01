import Foundation
import UIKit
import KodaiKernel

struct SystemToolRouter: ToolRouter {
    let confirm: (AssistantToolCall) async -> ConfirmDecision

    func execute(_ call: AssistantToolCall) async -> ToolResult {
        switch call {
        case let .webFetch(urlString):
            return await fetchURL(urlString)

        case let .openUrl(urlString):
            let decision = await confirm(call)
            guard case .accept = decision else {
                return .failure(tool: "open_url", error: "cancelled_by_user")
            }
            return await openURL(urlString)

        default:
            return .failure(tool: call.toolName, error: "not_implemented")
        }
    }

    /// 10s cap: the user may be intentionally offline — fail fast, never retry.
    private static let fetchTimeout: TimeInterval = 10

    private func fetchURL(_ urlString: String) async -> ToolResult {
        guard let url = URL(string: urlString) else {
            return .failure(tool: "web_fetch", error: "invalid_url")
        }
        // http(s) only — anything else (file://, ftp://) sidesteps the
        // sandboxed file flow and its confirm gates.
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return .failure(tool: "web_fetch", error: "unsupported_url_scheme")
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = Self.fetchTimeout
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .failure(tool: "web_fetch", error: "http_\(http.statusCode)")
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            let truncated = body.count > 4000 ? String(body.prefix(4000)) + "\n[truncated]" : body
            return .ok(tool: "web_fetch", result: ["content": truncated, "url": urlString])
        } catch {
            return .failure(tool: "web_fetch", error: error.localizedDescription)
        }
    }

    @MainActor
    private func openURL(_ urlString: String) async -> ToolResult {
        guard let url = URL(string: urlString) else {
            return .failure(tool: "open_url", error: "invalid_url")
        }
        let opened = await UIApplication.shared.open(url)
        if opened {
            return .ok(tool: "open_url", result: ["url": urlString, "opened": "true"])
        } else {
            return .failure(tool: "open_url", error: "could_not_open_url")
        }
    }
}
