import Foundation
import SwiftUI
import UniformTypeIdentifiers
import KodaiKernel

enum FilePickerRequest: Sendable {
    case save(name: String, content: String)
    case read(purpose: String)
}

enum FilePickerResult: Sendable {
    case saved(name: String)
    case read(name: String, content: String)
    case cancelled
    case error(String)
}

struct FileToolRouter: ToolRouter {
    let presentPicker: (FilePickerRequest) async -> FilePickerResult
    var confirm: (AssistantToolCall) async -> ConfirmDecision = { .accept($0) }

    func execute(_ call: AssistantToolCall) async -> ToolResult {
        switch call {
        case let .filesList(path):
            return listFiles(path: path)

        case let .filesRead(path):
            if let url = resolveContainedPath(path) {
                return readFile(at: url)
            }
            let result = await presentPicker(.read(purpose: path))
            switch result {
            case let .read(name, content):
                let truncated = content.count > 8000 ? String(content.prefix(8000)) + "\n[truncated]" : content
                return .ok(tool: "files_read", result: ["name": name, "content": truncated])
            case .cancelled:
                return .failure(tool: "files_read", error: "cancelled_by_user")
            case .error(let message):
                return .failure(tool: "files_read", error: message)
            default:
                return .failure(tool: "files_read", error: "unexpected_result")
            }

        case let .filesCreate(path, content):
            let decision = await confirm(call)
            guard case .accept = decision else {
                return .failure(tool: "files_create", error: "cancelled_by_user")
            }
            if let url = resolveContainedPath(path) {
                return createFile(at: url, content: content)
            }
            let result = await presentPicker(.save(name: path, content: content))
            switch result {
            case .saved(let name):
                return .ok(tool: "files_create", result: ["name": name])
            case .cancelled:
                return .failure(tool: "files_create", error: "cancelled_by_user")
            case .error(let message):
                return .failure(tool: "files_create", error: message)
            default:
                return .failure(tool: "files_create", error: "unexpected_result")
            }

        case let .filesCreateFolder(path):
            // Resolve before confirming: an unresolvable path goes back to the
            // model to self-correct instead of asking the user to approve a
            // call that can only fail.
            guard let url = resolveContainedPath(path) else {
                return .failure(tool: "files_create_folder", error: pathError(path))
            }
            let decision = await confirm(call)
            guard case .accept = decision else {
                return .failure(tool: "files_create_folder", error: "cancelled_by_user")
            }
            return createFolder(at: url, path: path)

        case let .filesDelete(path):
            guard let url = resolveContainedPath(path) else {
                return .failure(tool: "files_delete", error: pathError(path))
            }
            let decision = await confirm(call)
            guard case .accept = decision else {
                return .failure(tool: "files_delete", error: "cancelled_by_user")
            }
            return deleteFile(at: url, path: path)

        default:
            return .failure(tool: call.toolName, error: "not_implemented")
        }
    }

    // MARK: - Path resolution

    private func resolveContainedPath(_ path: String) -> URL? {
        if path.hasPrefix("local/") {
            let relative = String(path.dropFirst("local/".count))
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            return docs.appendingPathComponent(relative)
        }
        if path.hasPrefix("icloud/") {
            let relative = String(path.dropFirst("icloud/".count))
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
            return container.appendingPathComponent("Documents").appendingPathComponent(relative)
        }
        return nil
    }

    /// Distinguishes "iCloud isn't available" (signed out, or the container
    /// isn't provisioned) from a genuinely malformed path, so the agent can
    /// explain the real problem instead of blaming the path.
    private func pathError(_ path: String) -> String {
        if path.hasPrefix("icloud/") { return "icloud_unavailable" }
        return "invalid_path_prefix"
    }

    // MARK: - Operations

    private func listFiles(path: String) -> ToolResult {
        guard let url = resolveContainedPath(path) else {
            return .failure(tool: "files_list", error: pathError(path))
        }
        do {
            let keys: [URLResourceKey] = [.fileSizeKey, .contentTypeKey]
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)
            if contents.isEmpty {
                return .ok(tool: "files_list", result: ["summary": "Empty directory.", "count": "0"])
            }
            let lines = contents.prefix(50).map { item -> String in
                let values = try? item.resourceValues(forKeys: Set(keys))
                let size = values?.fileSize.map { "\($0) bytes" } ?? "unknown"
                let type = values?.contentType?.identifier ?? "unknown"
                return "• \(item.lastPathComponent) — \(size) (\(type))"
            }
            var summary = "\(contents.count) item\(contents.count == 1 ? "" : "s"):\n" + lines.joined(separator: "\n")
            if contents.count > 50 { summary += "\n… and \(contents.count - 50) more" }
            return .ok(tool: "files_list", result: ["summary": summary, "count": "\(contents.count)"])
        } catch {
            return .failure(tool: "files_list", error: error.localizedDescription)
        }
    }

    private func readFile(at url: URL) -> ToolResult {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let truncated = content.count > 8000 ? String(content.prefix(8000)) + "\n[truncated]" : content
            return .ok(tool: "files_read", result: ["name": url.lastPathComponent, "content": truncated])
        } catch {
            return .failure(tool: "files_read", error: error.localizedDescription)
        }
    }

    private func createFile(at url: URL, content: String) -> ToolResult {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return .ok(tool: "files_create", result: ["name": url.lastPathComponent])
        } catch {
            return .failure(tool: "files_create", error: error.localizedDescription)
        }
    }

    private func createFolder(at url: URL, path: String) -> ToolResult {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return .ok(tool: "files_create_folder", result: ["path": path])
        } catch {
            return .failure(tool: "files_create_folder", error: error.localizedDescription)
        }
    }

    private func deleteFile(at url: URL, path: String) -> ToolResult {
        do {
            try FileManager.default.removeItem(at: url)
            return .ok(tool: "files_delete", result: ["path": path, "deleted": "true"])
        } catch {
            return .failure(tool: "files_delete", error: error.localizedDescription)
        }
    }
}

struct DocumentPickerView: UIViewControllerRepresentable {
    let request: FilePickerRequest
    let onResult: (FilePickerResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        switch request {
        case let .save(name, content):
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? content.write(to: tempURL, atomically: true, encoding: .utf8)
            let picker = UIDocumentPickerViewController(forExporting: [tempURL], asCopy: true)
            picker.delegate = context.coordinator
            context.coordinator.tempURL = tempURL
            context.coordinator.fileName = name
            return picker

        case .read:
            let types: [UTType] = [.plainText, .json, .commaSeparatedText, .text]
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
            picker.delegate = context.coordinator
            picker.allowsMultipleSelection = false
            return picker
        }
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onResult: (FilePickerResult) -> Void
        var tempURL: URL?
        var fileName: String?

        init(onResult: @escaping (FilePickerResult) -> Void) {
            self.onResult = onResult
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let tempURL {
                try? FileManager.default.removeItem(at: tempURL)
                onResult(.saved(name: fileName ?? tempURL.lastPathComponent))
                return
            }

            guard let url = urls.first else {
                onResult(.error("no_file_selected"))
                return
            }

            guard url.startAccessingSecurityScopedResource() else {
                onResult(.error("access_denied"))
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                onResult(.read(name: url.lastPathComponent, content: content))
            } catch {
                onResult(.error(error.localizedDescription))
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
            onResult(.cancelled)
        }
    }
}
