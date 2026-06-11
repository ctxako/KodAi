import Foundation
import SwiftData

@Model
public final class KodaiTask {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var notes: String
    public var status: TaskStatus
    public var priority: TaskPriority
    public var dueDate: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public var project: KodaiProject?

    @Relationship(deleteRule: .cascade, inverse: \KodaiReminder.task)
    public var reminders: [KodaiReminder]

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        status: TaskStatus = .pending,
        priority: TaskPriority = .medium,
        dueDate: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        project: KodaiProject? = nil,
        reminders: [KodaiReminder] = []
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.project = project
        self.reminders = reminders
    }
}
