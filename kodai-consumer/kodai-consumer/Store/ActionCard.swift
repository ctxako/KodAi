import Foundation
import SwiftData

@Model
final class ActionCard {
    var id: UUID
    var toolName: String
    var domain: String
    var kind: String
    var summary: String
    var status: String
    var timestamp: Date
    var details: [String: String]
    var sessionID: UUID
    var relatedDate: Date?
    var isArchived: Bool

    init(
        toolName: String,
        domain: String,
        kind: String = "action",
        summary: String,
        status: String,
        details: [String: String] = [:],
        sessionID: UUID,
        relatedDate: Date? = nil
    ) {
        self.id = UUID()
        self.toolName = toolName
        self.domain = domain
        self.kind = kind
        self.summary = summary
        self.status = status
        self.timestamp = Date()
        self.details = details
        self.sessionID = sessionID
        self.relatedDate = relatedDate
        self.isArchived = false
    }
}
