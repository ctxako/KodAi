//
//  chatbubble.swift
//  kodai_macos

import SwiftUI
import KodaiCore

private enum ChatTypography {
    static let assistantBody = Font.system(size: 15.5, weight: .regular, design: .monospaced)
    static let assistantSectionTitle = Font.system(size: 15.5, weight: .semibold, design: .monospaced)
    static let userBody = Font.system(size: 14.5, weight: .regular, design: .default)
    static let userSectionTitle = Font.system(size: 14.5, weight: .semibold, design: .default)
}

struct ChatBubble: View {
    @Environment(\.kodaiTheme) private var theme

    let message: ChatMessage
    var turnRecord: TurnRecord? = nil

    @State private var expanded = false

    private var isUser: Bool {
        message.role == .user
    }

    private var bodyFont: Font {
        isUser ? ChatTypography.userBody : ChatTypography.assistantBody
    }

    private var sectionTitleFont: Font {
        isUser ? ChatTypography.userSectionTitle : ChatTypography.assistantSectionTitle
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if isUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: .leading, spacing: 0) {
                KodaiMarkdownText(
                    text: message.text,
                    bodyFont: bodyFont,
                    sectionTitleFont: sectionTitleFont
                )
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
                    .fill(isUser ? theme.primaryAccent.opacity(0.15) : theme.glassSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        isUser ? theme.primaryAccent.opacity(0.22) : .white.opacity(0.045),
                        lineWidth: 0.75
                    )
            }
            .frame(maxWidth: 560, alignment: isUser ? .trailing : .leading)

            if !isUser {
                Spacer(minLength: 60)
            }
        }
        .transition(.move(edge: isUser ? .trailing : .leading).combined(with: .opacity))
    }
}
