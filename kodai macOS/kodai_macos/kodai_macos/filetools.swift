//
//  filetools.swift
//  kodai_macos
//
//  The file tool ring: read_file / glob_files / grep_files run automatically
//  (read-only, inside granted folders only); write_file / edit_file suspend
//  on ConfirmBroker with a preview before touching disk. Every call resolves
//  through FolderGrantStore — outside-grant paths fail honestly, naming what
//  is granted. Results are structured ToolResults so the model reads ground
//  truth. Output is hard-capped to protect the 4096-token FM window.
//

import Darwin
import Foundation
import FoundationModels
import KodaiCore

// MARK: - Tool argument types

@Generable(description: "A request to read a text file from a granted folder")
struct FileReadRequest {
    @Guide(description: "File path, e.g. '~/life/kb/kodai.md'")
    var path: String

    @Guide(description: "1-based line to start from, or 0 for the beginning")
    var startLine: Int
}

@Generable(description: "A request to list files matching a glob pattern")
struct FileGlobRequest {
    @Guide(description: "Glob pattern matched against paths inside granted folders, e.g. '*.md' or 'kb/*.md'")
    var pattern: String
}

@Generable(description: "A request to search file contents in granted folders")
struct FileGrepRequest {
    @Guide(description: "Text to search for (case-insensitive)")
    var query: String

    @Guide(description: "Optional glob to limit which files are searched, e.g. '*.md'; empty string for all")
    var filePattern: String
}

@Generable(description: "A request to write a new file or fully replace one")
struct FileWriteRequest {
    @Guide(description: "File path inside a write-granted folder, e.g. '~/life/notes/idea.md'")
    var path: String

    @Guide(description: "The complete file content to write")
    var content: String
}

@Generable(description: "A request to replace text inside an existing file")
struct FileEditRequest {
    @Guide(description: "File path inside a write-granted folder")
    var path: String

    @Guide(description: "The exact existing text to replace — must match the file verbatim and appear exactly once")
    var oldText: String

    @Guide(description: "The replacement text")
    var newText: String
}

// MARK: - File tool executor

/// Runs file tool calls against granted folders. The ledger hook is bound by
/// ChatViewModel at the start of each turn (it captures that turn's
/// ModelContext) and cleared after, mirroring WorkspaceToolExecutor.
@MainActor
final class FileToolExecutor {
    static let readToolID = "file_read"
    static let globToolID = "file_glob"
    static let grepToolID = "file_grep"
    static let writeToolID = "file_write"
    static let editToolID = "file_edit"

    private enum Caps {
        static let readLines = 150
        static let readChars = 6_000
        static let globResults = 40
        static let grepMatches = 30
        static let grepLineChars = 160
        static let grepFileBytes = 1_048_576
        static let previewChars = 90
    }

    private static let skippedDirectories: Set<String> = [
        ".git", "node_modules", ".build", "DerivedData", ".Trash"
    ]

    let grants: FolderGrantStore
    let broker: ConfirmBroker

    var onActivity: ((ToolActivity) -> Void)?
    var recordToolRun: ((_ tool: String, _ summary: String) -> Void)?

    init(grants: FolderGrantStore, broker: ConfirmBroker) {
        self.grants = grants
        self.broker = broker
    }

    func clearTurnBindings() {
        onActivity = nil
        recordToolRun = nil
    }

    // MARK: - Read

    func readFile(path: String, startLine: Int) -> ToolResult {
        let toolID = Self.readToolID
        guard let resolved = grants.resolve(path) else {
            return outsideGrantFailure(toolID, path: path)
        }
        guard let content = try? String(contentsOf: resolved.url, encoding: .utf8) else {
            return .failure(tool: toolID, error: "cannot read \(resolved.relativeDescription) — not found or not a UTF-8 text file")
        }

        let lines = content.components(separatedBy: "\n")
        let first = max(startLine, 1)
        guard first <= lines.count else {
            return .failure(tool: toolID, error: "startLine \(first) is past the end (\(lines.count) lines)")
        }

        var slice = Array(lines[(first - 1)...].prefix(Caps.readLines))
        var body = slice.joined(separator: "\n")
        if body.count > Caps.readChars {
            body = String(body.prefix(Caps.readChars))
            slice = body.components(separatedBy: "\n")
        }
        let last = first + slice.count - 1
        let truncated = last < lines.count

        onActivity?(ToolActivity(tool: toolID, phase: .succeeded, detail: resolved.relativeDescription))
        recordToolRun?(toolID, "read \(resolved.relativeDescription) lines \(first)–\(last)")

        var fields = [
            "path": resolved.relativeDescription,
            "lines": "\(first)–\(last) of \(lines.count)",
            "content": body,
        ]
        if truncated {
            fields["note"] = "truncated — call file_read again with startLine \(last + 1) for more"
        }
        return .ok(tool: toolID, result: fields)
    }

    // MARK: - Glob

    func globFiles(pattern: String) -> ToolResult {
        let toolID = Self.globToolID
        let cleanPattern = pattern.trimmingCharacters(in: .whitespaces)
        guard !cleanPattern.isEmpty else {
            return .failure(tool: toolID, error: "missing glob pattern")
        }
        let roots = grants.searchRoots
        guard !roots.isEmpty else {
            return .failure(tool: toolID, error: "no folders granted — the user can grant one in Settings → Folders")
        }

        var hits: [(path: String, modified: Date)] = []
        for root in roots {
            enumerateTextFiles(under: root.root) { url, relative in
                if Self.matches(cleanPattern, relative: relative, filename: url.lastPathComponent) {
                    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast
                    hits.append(("\(root.root.lastPathComponent)/\(relative)", modified))
                }
                return hits.count < Caps.globResults * 4
            }
        }

        hits.sort { $0.modified > $1.modified }
        let capped = hits.prefix(Caps.globResults)
        onActivity?(ToolActivity(tool: toolID, phase: .succeeded, detail: cleanPattern))
        recordToolRun?(toolID, "glob \(cleanPattern) → \(capped.count) files")

        guard !capped.isEmpty else {
            return .ok(tool: toolID, result: ["matches": "none", "searched": grants.grantedFoldersDescription])
        }
        return .ok(tool: toolID, result: [
            "count": "\(capped.count)\(hits.count > capped.count ? " (of \(hits.count), newest first)" : "")",
            "files": capped.map(\.path).joined(separator: "\n"),
        ])
    }

    // MARK: - Grep

    func grepFiles(query: String, filePattern: String) -> ToolResult {
        let toolID = Self.grepToolID
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            return .failure(tool: toolID, error: "missing search query")
        }
        let roots = grants.searchRoots
        guard !roots.isEmpty else {
            return .failure(tool: toolID, error: "no folders granted — the user can grant one in Settings → Folders")
        }

        let pattern = filePattern.trimmingCharacters(in: .whitespaces)
        let needle = cleanQuery.lowercased()
        var matches: [String] = []
        var filesHit = Set<String>()

        for root in roots {
            enumerateTextFiles(under: root.root) { url, relative in
                if !pattern.isEmpty,
                   !Self.matches(pattern, relative: relative, filename: url.lastPathComponent) {
                    return true
                }
                guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                      size <= Caps.grepFileBytes,
                      let content = try? String(contentsOf: url, encoding: .utf8) else {
                    return true
                }
                let display = "\(root.root.lastPathComponent)/\(relative)"
                for (index, line) in content.components(separatedBy: "\n").enumerated()
                where line.lowercased().contains(needle) {
                    matches.append("\(display):\(index + 1): \(String(line.trimmingCharacters(in: .whitespaces).prefix(Caps.grepLineChars)))")
                    filesHit.insert(display)
                    if matches.count >= Caps.grepMatches { return false }
                }
                return matches.count < Caps.grepMatches
            }
            if matches.count >= Caps.grepMatches { break }
        }

        onActivity?(ToolActivity(tool: toolID, phase: .succeeded, detail: cleanQuery))
        recordToolRun?(toolID, "grep \"\(cleanQuery)\" → \(matches.count) matches in \(filesHit.count) files")

        guard !matches.isEmpty else {
            return .ok(tool: toolID, result: ["matches": "none for: \(cleanQuery)", "searched": grants.grantedFoldersDescription])
        }
        var fields = [
            "count": "\(matches.count) matches in \(filesHit.count) files",
            "matches": matches.joined(separator: "\n"),
        ]
        if matches.count >= Caps.grepMatches {
            fields["note"] = "capped at \(Caps.grepMatches) — narrow the query or filePattern for more precision"
        }
        return .ok(tool: toolID, result: fields)
    }

    // MARK: - Write

    func writeFile(path: String, content: String) async -> ToolResult {
        let toolID = Self.writeToolID
        guard let resolved = grants.resolve(path) else {
            return outsideGrantFailure(toolID, path: path)
        }
        guard resolved.writable else {
            return .failure(tool: toolID, error: "\(resolved.relativeDescription) is in a read-only grant — the user can allow writes in Settings → Folders")
        }

        let existingSize = (try? resolved.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        let lineCount = content.components(separatedBy: "\n").count

        var details = [
            ToolConfirmationRequest.Detail(icon: "folder", text: resolved.root.lastPathComponent),
            ToolConfirmationRequest.Detail(icon: "doc.text", text: "\(lineCount) lines · \(content.utf8.count) bytes"),
            ToolConfirmationRequest.Detail(icon: "text.quote", text: String(content.prefix(Caps.previewChars))),
        ]
        if let existingSize {
            details.insert(
                ToolConfirmationRequest.Detail(icon: "exclamationmark.triangle", text: "replaces existing file (\(existingSize) bytes)"),
                at: 0
            )
        }

        onActivity?(ToolActivity(tool: toolID, phase: .awaitingConfirmation, detail: resolved.relativeDescription))
        let approved = await broker.request(ToolConfirmationRequest(
            heading: existingSize == nil ? "Write file?" : "Overwrite file?",
            subject: resolved.relativeDescription,
            details: details,
            confirmLabel: existingSize == nil ? "Write File" : "Overwrite"
        ))
        guard approved else {
            onActivity?(ToolActivity(tool: toolID, phase: .cancelled, detail: resolved.relativeDescription))
            return .failure(tool: toolID, error: "cancelled_by_user")
        }

        onActivity?(ToolActivity(tool: toolID, phase: .executing, detail: resolved.relativeDescription))
        do {
            try FileManager.default.createDirectory(
                at: resolved.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: resolved.url, atomically: true, encoding: .utf8)
        } catch {
            onActivity?(ToolActivity(tool: toolID, phase: .failed, detail: resolved.relativeDescription))
            return .failure(tool: toolID, error: "write failed: \(error.localizedDescription)")
        }

        onActivity?(ToolActivity(tool: toolID, phase: .succeeded, detail: resolved.relativeDescription))
        recordToolRun?(toolID, "\(existingSize == nil ? "wrote" : "overwrote") \(resolved.relativeDescription) (\(content.utf8.count) bytes)")
        return .ok(tool: toolID, result: [
            "path": resolved.relativeDescription,
            "bytes": "\(content.utf8.count)",
            "action": existingSize == nil ? "created" : "replaced",
        ])
    }

    // MARK: - Edit

    func editFile(path: String, oldText: String, newText: String) async -> ToolResult {
        let toolID = Self.editToolID
        guard !oldText.isEmpty else {
            return .failure(tool: toolID, error: "oldText is empty — use file_write to create or replace a whole file")
        }
        guard let resolved = grants.resolve(path) else {
            return outsideGrantFailure(toolID, path: path)
        }
        guard resolved.writable else {
            return .failure(tool: toolID, error: "\(resolved.relativeDescription) is in a read-only grant — the user can allow writes in Settings → Folders")
        }
        guard let content = try? String(contentsOf: resolved.url, encoding: .utf8) else {
            return .failure(tool: toolID, error: "cannot read \(resolved.relativeDescription) — not found or not a UTF-8 text file")
        }

        let occurrences = content.components(separatedBy: oldText).count - 1
        guard occurrences > 0 else {
            return .failure(tool: toolID, error: "oldText not found in \(resolved.relativeDescription) — re-read the file and copy the text exactly, including whitespace")
        }
        guard occurrences == 1 else {
            return .failure(tool: toolID, error: "oldText appears \(occurrences) times — include more surrounding lines so it matches exactly once")
        }

        let details = [
            ToolConfirmationRequest.Detail(icon: "minus.circle", text: String(oldText.prefix(Caps.previewChars))),
            ToolConfirmationRequest.Detail(icon: "plus.circle", text: String(newText.prefix(Caps.previewChars))),
        ]

        onActivity?(ToolActivity(tool: toolID, phase: .awaitingConfirmation, detail: resolved.relativeDescription))
        let approved = await broker.request(ToolConfirmationRequest(
            heading: "Edit file?",
            subject: resolved.relativeDescription,
            details: details,
            confirmLabel: "Apply Edit"
        ))
        guard approved else {
            onActivity?(ToolActivity(tool: toolID, phase: .cancelled, detail: resolved.relativeDescription))
            return .failure(tool: toolID, error: "cancelled_by_user")
        }

        onActivity?(ToolActivity(tool: toolID, phase: .executing, detail: resolved.relativeDescription))
        let updated = content.replacingOccurrences(of: oldText, with: newText)
        do {
            try updated.write(to: resolved.url, atomically: true, encoding: .utf8)
        } catch {
            onActivity?(ToolActivity(tool: toolID, phase: .failed, detail: resolved.relativeDescription))
            return .failure(tool: toolID, error: "write failed: \(error.localizedDescription)")
        }

        onActivity?(ToolActivity(tool: toolID, phase: .succeeded, detail: resolved.relativeDescription))
        recordToolRun?(toolID, "edited \(resolved.relativeDescription) (−\(oldText.count) +\(newText.count) chars)")
        return .ok(tool: toolID, result: [
            "path": resolved.relativeDescription,
            "action": "replaced 1 occurrence",
        ])
    }

    // MARK: - Helpers

    private func outsideGrantFailure(_ toolID: String, path: String) -> ToolResult {
        .failure(
            tool: toolID,
            error: "\(path) is not inside a granted folder (granted: \(grants.grantedFoldersDescription)) — the user can grant it in Settings → Folders"
        )
    }

    /// Walks regular files under root, skipping hidden entries and heavy
    /// directories. The visit closure returns false to stop early.
    private func enumerateTextFiles(under root: URL, visit: (URL, String) -> Bool) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }

        let rootPrefix = root.path + "/"
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if Self.skippedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            let relative = url.path.hasPrefix(rootPrefix)
                ? String(url.path.dropFirst(rootPrefix.count))
                : url.lastPathComponent
            if !visit(url, relative) { return }
        }
    }

    /// fnmatch without FNM_PATHNAME so `*` crosses directory separators —
    /// "*.md" finds nested markdown; "kb/*.md" still anchors to a subpath.
    nonisolated private static func matches(_ pattern: String, relative: String, filename: String) -> Bool {
        fnmatch(pattern, relative, 0) == 0 || fnmatch(pattern, filename, 0) == 0
    }
}

// MARK: - Foundation Models tools

struct ReadFileTool: Tool {
    typealias Arguments = FileReadRequest
    let executor: FileToolExecutor

    var name: String { "file_read" }
    var description: String {
        "Read a text file from the user's granted folders. Returns up to 150 lines; pass startLine to continue a long file. Read-only, runs without confirmation."
    }

    func call(arguments: FileReadRequest) async throws -> String {
        await executor.readFile(path: arguments.path, startLine: arguments.startLine).asContextJSON()
    }
}

struct GlobFilesTool: Tool {
    typealias Arguments = FileGlobRequest
    let executor: FileToolExecutor

    var name: String { "file_glob" }
    var description: String {
        "List files matching a glob pattern (e.g. '*.md') inside the user's granted folders, newest first. Use it to discover files before reading them."
    }

    func call(arguments: FileGlobRequest) async throws -> String {
        await executor.globFiles(pattern: arguments.pattern).asContextJSON()
    }
}

struct GrepFilesTool: Tool {
    typealias Arguments = FileGrepRequest
    let executor: FileToolExecutor

    var name: String { "file_grep" }
    var description: String {
        "Search file contents in the user's granted folders (case-insensitive). Returns path:line matches. Use it to locate where something is mentioned, then file_read for detail."
    }

    func call(arguments: FileGrepRequest) async throws -> String {
        await executor.grepFiles(query: arguments.query, filePattern: arguments.filePattern).asContextJSON()
    }
}

struct WriteFileTool: Tool {
    typealias Arguments = FileWriteRequest
    let executor: FileToolExecutor

    var name: String { "file_write" }
    var description: String {
        "Create or fully replace a text file in a write-granted folder. The user approves every write before it happens. The returned JSON is the real outcome — report it truthfully."
    }

    func call(arguments: FileWriteRequest) async throws -> String {
        await executor.writeFile(path: arguments.path, content: arguments.content).asContextJSON()
    }
}

struct EditFileTool: Tool {
    typealias Arguments = FileEditRequest
    let executor: FileToolExecutor

    var name: String { "file_edit" }
    var description: String {
        "Replace text inside an existing file in a write-granted folder. oldText must match the file exactly once — file_read first, then copy the text verbatim. The user approves every edit. The returned JSON is the real outcome — report it truthfully."
    }

    func call(arguments: FileEditRequest) async throws -> String {
        await executor.editFile(
            path: arguments.path,
            oldText: arguments.oldText,
            newText: arguments.newText
        ).asContextJSON()
    }
}
