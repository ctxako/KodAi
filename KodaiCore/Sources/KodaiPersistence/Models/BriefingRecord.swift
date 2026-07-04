import Foundation
import KodaiKernel
import SwiftData

/// One delivered daily briefing (morning brief or evening debrief), stored
/// as a snapshot so past briefs remain readable even after the underlying
/// tasks/commitments change.
@Model
public final class BriefingRecord {
    public var id: UUID
    public var kind: BriefingKind
    /// Start-of-day of the day this briefing covers.
    public var day: Date
    /// Markdown snapshot of the briefing content as composed.
    public var content: String
    public var deliveredAt: Date?
    public var openedAt: Date?
    /// Evening debrief reflection, as also appended to the ~/life journal.
    public var reflection: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: BriefingKind,
        day: Date,
        content: String = "",
        deliveredAt: Date? = nil,
        openedAt: Date? = nil,
        reflection: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.day = day
        self.content = content
        self.deliveredAt = deliveredAt
        self.openedAt = openedAt
        self.reflection = reflection
        self.createdAt = createdAt
    }
}
