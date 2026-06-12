import Foundation

public protocol ContextBlockProvider {
    func provide(for chat: KodaiChatSession, query: String) -> ContextBlock?
}
