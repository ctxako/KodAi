//
//  chatscrollview.swift
//  kodai_macos
//

import SwiftUI
import KodaiCore

struct ChatScrollView: View {
    let messages: [ChatMessage]
    var turnRecords: [UUID: TurnRecord] = [:]

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        if messages.isEmpty {
                            ChatEmptyState()
                                .padding(.bottom, 68)
                        } else {
                            ForEach(messages) { message in
                                ChatBubble(message: message, turnRecord: turnRecords[message.id])
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(
                        minHeight: max(0, geometry.size.height - 24),
                        alignment: .bottom
                    )
                }
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [.clear, .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 24)
                        Rectangle()
                        LinearGradient(
                            colors: [.black, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 20)
                    }
                }
                .onChange(of: messages.last?.text) {
                    if let lastID = messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct ChatEmptyState: View {
    @Environment(\.kodaiTheme) private var theme

    var body: some View {
        VStack(spacing: 7) {
            Text("KodAi")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.primaryText.opacity(0.9))

            Text("What are we building today?")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(theme.secondaryText.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat.emptyState")
    }
}
