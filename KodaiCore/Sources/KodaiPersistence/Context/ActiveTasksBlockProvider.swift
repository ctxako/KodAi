import Foundation
import KodaiKernel

public struct ActiveTasksBlockProvider: ContextBlockProvider {
    // Chat sessions reference projects by scalar projectID (no SwiftData
    // relationship across the chat/workspace boundary), so the caller supplies
    // the lookup — typically a fetch against the workspace store.
    private let resolveProject: (UUID) -> KodaiProject?

    public init(resolveProject: @escaping (UUID) -> KodaiProject? = { _ in nil }) {
        self.resolveProject = resolveProject
    }

    public func provide(for chat: KodaiChatSession, query: String) -> ContextBlock? {
        guard let projectID = chat.projectID, let project = resolveProject(projectID) else { return nil }
        let openTasks = project.tasks.filter { !$0.isCompleted }
        guard !openTasks.isEmpty else { return nil }

        let lines = openTasks
            .sorted { $0.priority.sortOrder < $1.priority.sortOrder }
            .prefix(5)
            .map { "• [\($0.priority.rawValue)] \($0.title)" }
            .joined(separator: "\n")
        let content = "Open tasks (\(openTasks.count)):\n\(lines)"
        return ContextBlock(
            kind: "active_tasks",
            content: content,
            tokenEstimate: TokenEstimator.estimate(content),
            priority: 4,
            sourceID: project.id
        )
    }
}
