//
//  ChatExportService.swift
//  kodAI_chatbot_dev
//
//  Created by Codex on 6/7/26.
//

import Foundation

struct ChatExportSnapshot: Equatable {
    let id = UUID()
    let chatTitle: String?
    let createdAt: Date?
    let updatedAt: Date?
    let messages: [ChatMessage]
    let modelName: String?
    let contextLimit: Int?
    let streamID: UUID?
    let streamTitle: String?
}

struct ChatExportResult {
    let markdown: String
    let fileURL: URL
}

enum ChatExportService {
    private static let log = AppLog(category: "Export")

    static func export(
        title: String,
        description: String,
        snapshot: ChatExportSnapshot,
        includeComments: Bool = true
    ) throws -> ChatExportResult {
        let markdown = markdown(
            title: title,
            description: description,
            snapshot: snapshot,
            includeComments: includeComments
        )
        log.event("export markdown generated")

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(sanitizedFilename(from: title))
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        log.event("export file written path=\(fileURL.path)")

        return ChatExportResult(markdown: markdown, fileURL: fileURL)
    }

    static func sanitizedFilename(from title: String) -> String {
        let loweredTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let lowered = loweredTitle.hasSuffix(".md") ? String(loweredTitle.dropLast(3)) : loweredTitle
        let underscored = lowered.replacingOccurrences(of: " ", with: "_")
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_-")
        let sanitizedScalars = underscored.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : nil
        }.compactMap { $0 }
        let baseName = String(sanitizedScalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let filename = baseName.isEmpty ? "chat_export" : baseName

        return "\(filename).md"
    }

    private static func markdown(
        title: String,
        description: String,
        snapshot: ChatExportSnapshot,
        includeComments: Bool
    ) -> String {
        let exportTitle = normalizedTitle(title)
        let characterCount = snapshot.messages.reduce(0) { $0 + $1.text.count }
        let tokenCount = characterCount / 4
        let contextLimit = snapshot.contextLimit
        let contextPercent = contextLimit.flatMap { limit -> String? in
            guard limit > 0 else { return nil }
            let percent = (Double(tokenCount) / Double(limit)) * 100
            return "\(Int(percent.rounded()))%"
        }

        var lines: [String] = [
            "# \(exportTitle)",
            "",
            "## Description",
            description,
            "",
            "## Chat Contents",
            ""
        ]

        for message in snapshot.messages {
            lines.append("### \(message.role.exportTitle)")
            lines.append(message.text)
            if includeComments,
               let exportComment = message.exportComment,
               !exportComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("")
                lines.append("// Comment: \(exportComment)")
            }
            lines.append("")
        }

        lines.append(contentsOf: [
            "## Metadata",
            "- chat title: \(metadataValue(snapshot.chatTitle))",
            "- export title: \(exportTitle)",
            "- createdAt: \(dateValue(snapshot.createdAt))",
            "- updatedAt: \(dateValue(snapshot.updatedAt))",
            "- model name: \(metadataValue(snapshot.modelName))",
            "- message count: \(snapshot.messages.count)",
            "- approximate character count: \(characterCount)",
            "- approximate token count: \(tokenCount)",
            "- configured context limit: \(contextLimit.map(String.init) ?? "Unknown")",
            "- approximate context percent used: \(contextPercent ?? "Unknown")",
            "- stream title/id: \(streamValue(title: snapshot.streamTitle, id: snapshot.streamID))",
            "- exportedAt: \(dateValue(Date()))"
        ])

        return lines.joined(separator: "\n")
    }

    private static func normalizedTitle(_ title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Exported Chat" : trimmedTitle
    }

    private static func metadataValue(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Unknown"
        }

        return value
    }

    private static func streamValue(title: String?, id: UUID?) -> String {
        switch (title, id) {
        case (.some(let title), .some(let id)):
            return "\(title) (\(id.uuidString))"
        case (.some(let title), .none):
            return title
        case (.none, .some(let id)):
            return id.uuidString
        case (.none, .none):
            return "Unknown"
        }
    }

    private static func dateValue(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return ISO8601DateFormatter().string(from: date)
    }
}

private extension ChatRole {
    var exportTitle: String {
        switch self {
        case .user:
            return "User"
        case .assistant:
            return "Assistant"
        }
    }
}
