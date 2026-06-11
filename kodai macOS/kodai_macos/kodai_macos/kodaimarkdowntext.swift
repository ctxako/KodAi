//
//  kodaimarkdowntext.swift
//  kodai_macos
//
//  Created by Charles Thomas Xavier Austin III on 6/10/26.
//

import SwiftUI

struct KodaiMarkdownText: View {
    let text: String

    private enum Block {
        case paragraph(String)
        case section(title: String, body: String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(parsed.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let content):
                    Text(attributed(content))
                        .font(.system(.body, design: .rounded))
                        .lineSpacing(4)
                case .section(let title, let body):
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        if !body.isEmpty {
                            Text(attributed(body))
                                .font(.system(.body, design: .rounded))
                                .lineSpacing(4)
                                .foregroundStyle(.primary.opacity(0.85))
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    private func attributed(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }

    private var parsed: [Block] {
        var blocks: [Block] = []
        var paragraph = ""

        for line in text.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.isEmpty {
                if !paragraph.isEmpty {
                    blocks.append(contentsOf: splitSections(paragraph))
                    paragraph = ""
                }
            } else {
                paragraph = paragraph.isEmpty ? line : paragraph + " " + line
            }
        }
        if !paragraph.isEmpty {
            blocks.append(contentsOf: splitSections(paragraph))
        }

        return blocks.isEmpty ? [.paragraph(text)] : blocks
    }

    // Splits a paragraph on inline **Title**: patterns.
    private func splitSections(_ s: String) -> [Block] {
        var result: [Block] = []
        var remaining = s

        while !remaining.isEmpty {
            guard let openRange = remaining.range(of: "**") else {
                let trimmed = remaining.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { result.append(.paragraph(trimmed)) }
                break
            }

            let before = String(remaining[..<openRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !before.isEmpty { result.append(.paragraph(before)) }

            let afterOpen = String(remaining[openRange.upperBound...])

            guard let closeRange = afterOpen.range(of: "**:") else {
                // Not a section header — keep as paragraph with the bold marker intact.
                let trimmed = ("**" + afterOpen).trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { result.append(.paragraph(trimmed)) }
                break
            }

            let title = String(afterOpen[..<closeRange.lowerBound])
            let afterTitle = String(afterOpen[closeRange.upperBound...]).trimmingCharacters(in: .whitespaces)

            if let nextBold = afterTitle.range(of: "**") {
                let body = String(afterTitle[..<nextBold.lowerBound]).trimmingCharacters(in: .whitespaces)
                result.append(.section(title: title, body: body))
                remaining = String(afterTitle[nextBold.lowerBound...])
            } else {
                result.append(.section(title: title, body: afterTitle))
                break
            }
        }

        return result.isEmpty ? [.paragraph(s)] : result
    }
}
