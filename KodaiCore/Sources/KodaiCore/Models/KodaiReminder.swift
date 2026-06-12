import Foundation
import SwiftData

@Model
public final class KodaiReminder {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var scheduledAt: Date
    public var fired: Bool
    public var createdAt: Date

    public var task: KodaiTask?

    public init(
        id: UUID = UUID(),
        title: String,
        scheduledAt: Date,
        fired: Bool = false,
        createdAt: Date = .now,
        task: KodaiTask? = nil
    ) {
        self.id = id
        self.title = title
        self.scheduledAt = scheduledAt
        self.fired = fired
        self.createdAt = createdAt
        self.task = task
    }
}
