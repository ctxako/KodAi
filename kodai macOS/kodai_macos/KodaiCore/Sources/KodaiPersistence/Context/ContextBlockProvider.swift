import Foundation
import KodaiKernel

public protocol ContextBlockProvider {
    func provide(for chat: KodaiChatSession, query: String) -> ContextBlock?
}

public extension ContextAssembler {
    /// Session-based assembly: gathers blocks from providers, then applies
    /// the kernel's block-first budget logic.
    func assemble(
        for chat: KodaiChatSession,
        userMessage: String,
        providers: [any ContextBlockProvider]
    ) -> (prompt: String, manifest: ContextManifest) {
        let blocks = providers.compactMap { $0.provide(for: chat, query: userMessage) }
        return assemble(blocks: blocks)
    }
}
