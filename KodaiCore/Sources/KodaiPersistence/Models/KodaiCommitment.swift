import Foundation
import KodaiKernel
import SwiftData

/// A tracked promise the user made ("finish the design doc by Friday").
/// Provenance is loose by design — a commitment carries the original quote
/// plus IDs/paths into its source, so every nudge can show a receipt without
/// a hard relationship to chat or journal storage.
@Model
public final class KodaiCommitment {
    public var id: UUID
    public var text: String
    public var sourceKind: CommitmentSource
    /// The user's original words, verbatim — shown with every nudge.
    public var sourceQuote: String
    public var sourceSessionID: UUID?
    public var sourceMessageID: UUID?
    /// Path relative to the ~/life root when the source is a journal entry.
    public var sourceJournalPath: String?
    public var dueDate: Date?
    public var status: CommitmentStatus
    public var resolvedAt: Date?
    public var slipCount: Int
    public var lastNudgedAt: Date?
    /// Workspace KodaiTask this commitment was converted into, if any.
    public var taskID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        sourceKind: CommitmentSource = .manual,
        sourceQuote: String = "",
        sourceSessionID: UUID? = nil,
        sourceMessageID: UUID? = nil,
        sourceJournalPath: String? = nil,
        dueDate: Date? = nil,
        status: CommitmentStatus = .open,
        resolvedAt: Date? = nil,
        slipCount: Int = 0,
        lastNudgedAt: Date? = nil,
        taskID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.text = text
        self.sourceKind = sourceKind
        self.sourceQuote = sourceQuote
        self.sourceSessionID = sourceSessionID
        self.sourceMessageID = sourceMessageID
        self.sourceJournalPath = sourceJournalPath
        self.dueDate = dueDate
        self.status = status
        self.resolvedAt = resolvedAt
        self.slipCount = slipCount
        self.lastNudgedAt = lastNudgedAt
        self.taskID = taskID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
