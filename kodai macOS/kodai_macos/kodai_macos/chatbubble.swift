//
//  chatbubble.swift
//  kodai_macos

import SwiftUI
import KodaiCore

struct ChatBubble: View {
    let message: ChatMessage
    var turnRecord: TurnRecord? = nil

    @State private var expanded = false

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

                if !isUser {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(height: 1)

                    HStack(spacing: 8) {
                        if let metrics = message.metrics {
                            Text(metrics.displayText)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary.opacity(0.7))
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                expanded.toggle()
                            }
                        } label: {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(expanded ? 0.5 : 0.3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(expanded ? "Hide context details" : "Show why this answer")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    if expanded {
                        Rectangle()
                            .fill(.white.opacity(0.08))
                            .frame(height: 1)

                        if let record = turnRecord {
                            WhyThisAnswerPanel(turn: record)
                        } else {
                            Text("No context record available")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                    }
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
