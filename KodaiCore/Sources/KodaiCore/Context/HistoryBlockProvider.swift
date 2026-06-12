import Foundation

public struct HistoryBlockProvider: ContextBlockProvider, Sendable {
    public var maxMessages: Int

    public init(maxMessages: Int = 20) {
        self.maxMessages = maxMessages
    }

    public func provide(for chat: KodaiChatSession, query: String) -> ContextBlock? {
        let sorted = chat.messages.sorted { $0.createdAt < $1.createdAt }
        guard !sorted.isEmpty else { return nil }

        let recent = sorted.suffix(maxMessages)
        let lines = recent.map { msg -> String in
            let label: String
            switch msg.role {
            case ChatRole.user.rawValue: label = "User"
            case ChatRole.assistant.rawValue: label = "Assistant"
            case ChatRole.system.rawValue: label = "System"
            default: label = msg.role.capitalized
            }
            return "\(label): \(msg.content)"
        }
        let content = lines.joined(separator: "\n")
        let tokens = recent.reduce(0) { $0 + TokenEstimator.estimate($1.content) }
        return ContextBlock(
            kind: "history",
            content: content,
            tokenEstimate: tokens,
            priority: 10
        )
    }
}
