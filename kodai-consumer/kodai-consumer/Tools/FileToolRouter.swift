import Foundation
import SwiftUI
import UniformTypeIdentifiers

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

    func execute(_ call: AssistantToolCall) async -> ToolResult {
        switch call {
        case let .saveFile(name, content):
            let result = await presentPicker(.save(name: name, content: content))
            switch result {
            case .saved(let name):
                return .ok(tool: "save_file", result: ["name": name])
            case .cancelled:
                return .failure(tool: "save_file", error: "cancelled_by_user")
            case .error(let message):
                return .failure(tool: "save_file", error: message)
            default:
                return .failure(tool: "save_file", error: "unexpected_result")
            }

        case let .readFile(purpose):
            let result = await presentPicker(.read(purpose: purpose))
            switch result {
            case let .read(name, content):
                let truncated = content.count > 2000 ? String(content.prefix(2000)) + "\n[truncated]" : content
                return .ok(tool: "read_file", result: ["name": name, "content": truncated])
            case .cancelled:
                return .failure(tool: "read_file", error: "cancelled_by_user")
            case .error(let message):
                return .failure(tool: "read_file", error: message)
            default:
                return .failure(tool: "read_file", error: "unexpected_result")
            }

        default:
            return .failure(tool: "unknown", error: "not_a_file_tool")
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
