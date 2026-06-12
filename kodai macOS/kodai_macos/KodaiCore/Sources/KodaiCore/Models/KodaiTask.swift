import Foundation
import SwiftData

@Model
public final class KodaiTask {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var notes: String
    public var priority: TaskPriority
    public var isCompleted: Bool
    public var completedAt: Date?
    public var dueDate: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var project: KodaiProject?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        priority: TaskPriority = .medium,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        dueDate: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        project: KodaiProject? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.priority = priority
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.project = project
    }
}
