import Foundation
import KodaiKernel
import SwiftData

@Model
public final class KodaiProject {
    // No `.unique` constraint: CloudKit-backed stores reject unique attributes,
    // and the app never relies on upsert-by-id. Identity is preserved by value.
    public var id: UUID = UUID()
    public var title: String = ""
    public var details: String = ""
    public var status: ProjectStatus = ProjectStatus.active
    public var summary: String?
    public var summaryUpdatedAt: Date?
    public var deadline: Date?
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \KodaiTask.project)
    public var tasks: [KodaiTask]?

    public init(
        id: UUID = UUID(),
        title: String = "New project",
        details: String = "",
        status: ProjectStatus = .active,
        summary: String? = nil,
        summaryUpdatedAt: Date? = nil,
        deadline: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        tasks: [KodaiTask] = []
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.status = status
        self.summary = summary
        self.summaryUpdatedAt = summaryUpdatedAt
        self.deadline = deadline
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tasks = tasks
    }
}
