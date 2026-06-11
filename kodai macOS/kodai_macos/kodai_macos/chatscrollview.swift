//
//  chatscrollview.swift
//  kodai_macos
//

import SwiftUI

struct ChatScrollView: View {
    let messages: [ChatMessage]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 32)
                    Rectangle()
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 32)
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
