import Foundation

public struct ActiveTasksBlockProvider: ContextBlockProvider, Sendable {
    public init() {}

    public func provide(for chat: KodaiChatSession, query: String) -> ContextBlock? {
        guard let project = chat.project else { return nil }
        let openTasks = project.tasks.filter {
            $0.status == .pending || $0.status == .inProgress
        }
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
