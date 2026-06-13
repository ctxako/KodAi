import Foundation
import KodaiKernel
import SwiftData

@Model
public final class MemoryEntry {
    public var id: UUID
    public var content: String
    public var type: MemoryType
    public var status: MemoryStatus
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date
    // Loose references to the turn and superseding entry
    public var turnId: UUID?
    public var supersededById: UUID?

    public var project: KodaiProject?
    public var session: KodaiChatSession?

    public init(
        id: UUID = UUID(),
        content: String,
        type: MemoryType,
        status: MemoryStatus = .active,
        tags: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        turnId: UUID? = nil,
        supersededById: UUID? = nil,
        project: KodaiProject? = nil,
        session: KodaiChatSession? = nil
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.status = status
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.turnId = turnId
        self.supersededById = supersededById
        self.project = project
        self.session = session
    }
}
