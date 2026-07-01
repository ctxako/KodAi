import Foundation
import UIKit
import KodaiKernel

struct ClipboardToolRouter: ToolRouter {
    let confirm: (AssistantToolCall) async -> ConfirmDecision

    func execute(_ call: AssistantToolCall) async -> ToolResult {
        switch call {
        case .clipboardRead:
            let content = UIPasteboard.general.string ?? ""
            if content.isEmpty {
                return .ok(tool: "clipboard_read", result: ["content": "Clipboard is empty."])
            }
            return .ok(tool: "clipboard_read", result: ["content": content])

        case let .clipboardWrite(content):
            let decision = await confirm(call)
            guard case .accept = decision else {
                return .failure(tool: "clipboard_write", error: "cancelled_by_user")
            }
            UIPasteboard.general.string = content
            return .ok(tool: "clipboard_write", result: ["copied": "true"])

        default:
            return .failure(tool: call.toolName, error: "not_implemented")
        }
    }
}
