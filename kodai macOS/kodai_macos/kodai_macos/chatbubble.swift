//
//  chatbubble.swift
//  kodai_macos
//

import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if isUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: .leading, spacing: 0) {
                KodaiMarkdownText(text: message.text)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                if !isUser, let metrics = message.metrics {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(height: 1)

                    Text(metrics.displayText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isUser ? .blue.opacity(0.15) : .white.opacity(0.055))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isUser ? .blue.opacity(0.30) : .white.opacity(0.12), lineWidth: 1)
            }
            .frame(maxWidth: 560, alignment: isUser ? .trailing : .leading)

            if !isUser {
                Spacer(minLength: 60)
            }
        }
        .transition(.move(edge: isUser ? .trailing : .leading).combined(with: .opacity))
    }
}
