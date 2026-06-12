import Foundation
import KodaiKernel

// Adapters between KodaiKernel workspace value types (the canonical
// cross-platform vocabulary) and KodaiPersistence SwiftData models.
//
// Canonical priority vocabulary is the kernel's low/normal/high.
// The persistence enum keeps "medium" as its stored raw value so existing
// macOS SwiftData stores keep decoding; the mapping medium↔normal is
// explicit here and covered by tests.

// MARK: - Priority mapping

extension TaskPriority {
    public init(_ value: KodaiTaskPriority) {
        switch value {
        case .low: self = .low
        case .normal: self = .medium
        case .high: self = .high
        }
    }

    public var kernelValue: KodaiTaskPriority {
        switch self {
        case .low: return .low
        case .medium: return .normal
        case .high: return .high
        }
    }
}

extension KodaiTaskPriority {
    public init(_ model: TaskPriority) {
        self = model.kernelValue
    }
}

// MARK: - Task

extension KodaiTask {
    /// Snapshot of this model as a portable kernel value.
    /// Empty `notes` maps to a nil `details`.
    public var valueRepresentation: KodaiTaskValue {
        KodaiTaskValue(
            id: id,
            title: title,
            details: notes.isEmpty ? nil : notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            dueDate: dueDate,
            priority: priority.kernelValue,
            isCompleted: isCompleted,
            completedAt: completedAt
        )
    }

    public convenience init(value: KodaiTaskValue, project: KodaiProject? = nil) {
        self.init(
            id: value.id,
            title: value.title,
            notes: value.details ?? "",
            priority: TaskPriority(value.priority),
            isCompleted: value.isCompleted,
            completedAt: value.completedAt,
            dueDate: value.dueDate,
            createdAt: value.createdAt,
            updatedAt: value.updatedAt,
            project: project
        )
    }

    /// Applies the mutable fields of a kernel value onto this model.
    /// Identity and `createdAt` are intentionally not changed.
    public func apply(_ value: KodaiTaskValue) {
        title = value.title
        notes = value.details ?? ""
        priority = TaskPriority(value.priority)
        isCompleted = value.isCompleted
        completedAt = value.completedAt
        dueDate = value.dueDate
        updatedAt = value.updatedAt
    }
}

// MARK: - Project

extension KodaiProject {
    /// Snapshot of this model as a portable kernel value.
    /// Tasks are ordered deterministically (priority, then createdAt) because
    /// the SwiftData relationship is unordered. Chat sessions are deliberately
    /// excluded: chats are local-only and stay out of the workspace sync path.
    public var valueRepresentation: KodaiProjectValue {
        KodaiProjectValue(
            id: id,
            title: title,
            details: details.isEmpty ? nil : details,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deadline: deadline,
            tasks: tasks
                .sorted {
                    if $0.priority.sortOrder != $1.priority.sortOrder {
                        return $0.priority.sortOrder < $1.priority.sortOrder
                    }
                    return $0.createdAt < $1.createdAt
                }
                .map(\.valueRepresentation)
        )
    }

    public convenience init(value: KodaiProjectValue) {
        self.init(
            id: value.id,
            title: value.title,
            details: value.details ?? "",
            deadline: value.deadline,
            createdAt: value.createdAt,
            updatedAt: value.updatedAt
        )
        tasks = value.tasks.map { KodaiTask(value: $0) }
    }
}
