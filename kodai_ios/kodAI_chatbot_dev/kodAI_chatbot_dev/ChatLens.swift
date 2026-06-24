//
//  ChatLens.swift
//  kodAI_chatbot_dev
//
//  The viewing "lens" for a chat: how a response is watched.
//  Tracer = one response as the river/globe (the moment). Atlas = the whole
//  conversation as a planet (the zoom-out). See docs/kodai_ship_plan.md.
//

import SwiftUI

/// How the user is currently watching the conversation.
enum ChatLens: String, CaseIterable, Identifiable {
    /// One response, rendered as the river/globe. The default "moment" lens.
    case tracer
    /// The whole conversation as a globe of token continents. The "journey" lens.
    case atlas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tracer: return "Tracer"
        case .atlas: return "Atlas"
        }
    }

    var systemImage: String {
        switch self {
        case .tracer: return "water.waves"
        case .atlas: return "globe.americas"
        }
    }
}

/// A single completed response to watch in the Tracer lens, pairing the text with
/// its per-token telemetry so it can drive `fullScreenCover(item:)`.
struct TracerTarget: Identifiable {
    let id: ChatMessage.ID
    let messageText: String
    let history: [TokenSnapshot]
}

/// Two-state lens selector for the chat header. Tapping a lens selects it and asks
/// the caller (via `onSelect`) to watch that instrument now.
struct ChatLensToggle: View {
    @Binding var lens: ChatLens
    var onSelect: (ChatLens) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ChatLens.allCases) { option in
                Button {
                    lens = option
                    onSelect(option)
                } label: {
                    Image(systemName: option.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(lens == option ? .white : Color.white.opacity(0.5))
                        .frame(width: 34, height: 30)
                        .background {
                            if lens == option {
                                Capsule().fill(ChatPalette.accentBlue.opacity(0.55))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.title) lens")
                .accessibilityAddTraits(lens == option ? [.isSelected] : [])
            }
        }
        .padding(2)
        .glassEffect(.regular.tint(ChatPalette.elevatedSurface).interactive(), in: Capsule())
        .accessibilityElement(children: .contain)
    }
}
