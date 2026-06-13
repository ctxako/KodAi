import Foundation
import SwiftData

public extension ModelContext {
    func kodaiProject(id: UUID?) throws -> KodaiProject? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<KodaiProject>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    func kodaiChatSessions(projectID: UUID) throws -> [KodaiChatSession] {
        let descriptor = FetchDescriptor<KodaiChatSession>(
            predicate: #Predicate { $0.projectID == projectID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try fetch(descriptor)
    }

    func kodaiSummaries(projectID: UUID) throws -> [KodaiSummary] {
        let descriptor = FetchDescriptor<KodaiSummary>(
            predicate: #Predicate { $0.projectID == projectID }
        )
        return try fetch(descriptor)
    }
}
