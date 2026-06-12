import Foundation
import KodaiKernel

public struct ProjectSummaryBlockProvider: ContextBlockProvider {
    // Chat sessions reference projects by scalar projectID (no SwiftData
    // relationship across the chat/workspace boundary), so the caller supplies
    // the lookup — typically a fetch against the workspace store.
    private let resolveProject: (UUID) -> KodaiProject?

    public init(resolveProject: @escaping (UUID) -> KodaiProject? = { _ in nil }) {
        self.resolveProject = resolveProject
    }

    public func provide(for chat: KodaiChatSession, query: String) -> ContextBlock? {
        guard let projectID = chat.projectID, let project = resolveProject(projectID) else { return nil }
        let body = project.summary ?? project.details
        guard !body.isEmpty else { return nil }
        let content = "Project: \(project.title)\n\(body)"
        return ContextBlock(
            kind: "project_summary",
            content: content,
            tokenEstimate: TokenEstimator.estimate(content),
            priority: 3,
            sourceID: project.id
        )
    }
}
