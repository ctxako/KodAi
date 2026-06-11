import Foundation

public struct ProjectSummaryBlockProvider: ContextBlockProvider, Sendable {
    public init() {}

    public func provide(for chat: KodaiChatSession, query: String) -> ContextBlock? {
        guard let project = chat.project, !project.notes.isEmpty else { return nil }
        let content = "Project: \(project.title)\n\(project.notes)"
        return ContextBlock(
            kind: "project_summary",
            content: content,
            tokenEstimate: TokenEstimator.estimate(content),
            priority: 3,
            sourceID: project.id
        )
    }
}
