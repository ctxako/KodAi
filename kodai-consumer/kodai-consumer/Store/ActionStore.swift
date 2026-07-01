import Foundation
import SwiftData
import Observation

@Observable
final class ActionStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Session lifecycle

    func startSession(prompt: String) -> UUID {
        let session = SessionGroup(prompt: prompt)
        context.insert(session)
        try? context.save()
        return session.id
    }

    func endSession(id: UUID) {
        var descriptor = FetchDescriptor<SessionGroup>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let session = try? context.fetch(descriptor).first else { return }
        session.endedAt = Date()
        try? context.save()
    }

    // MARK: - Card creation

    func logPrompt(text: String, sessionID: UUID) {
        let card = ActionCard(
            toolName: "user_prompt",
            domain: "system",
            kind: "prompt",
            summary: text,
            status: "done",
            sessionID: sessionID
        )
        context.insert(card)
        try? context.save()
    }

    func logAction(
        toolName: String,
        domain: String,
        summary: String,
        status: String,
        details: [String: String] = [:],
        sessionID: UUID,
        relatedDate: Date? = nil
    ) {
        let card = ActionCard(
            toolName: toolName,
            domain: domain,
            kind: "action",
            summary: summary,
            status: status,
            details: details,
            sessionID: sessionID,
            relatedDate: relatedDate
        )
        context.insert(card)
        try? context.save()
    }

    func logNote(text: String, sessionID: UUID) {
        let card = ActionCard(
            toolName: "agent_note",
            domain: "system",
            kind: "note",
            summary: text,
            status: "done",
            sessionID: sessionID
        )
        context.insert(card)
        try? context.save()
    }

    // MARK: - Queries

    func feedCards() -> [ActionCard] {
        let descriptor = FetchDescriptor<ActionCard>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func upcomingCards() -> [ActionCard] {
        let now = Date()
        let descriptor = FetchDescriptor<ActionCard>(
            predicate: #Predicate {
                $0.kind == "action"
                && $0.relatedDate != nil
                && $0.relatedDate! > now
                && ($0.domain == "calendar" || $0.domain == "reminders")
            },
            sortBy: [SortDescriptor(\.relatedDate, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func archiveSessions() -> [(session: SessionGroup, cards: [ActionCard])] {
        let sessionDescriptor = FetchDescriptor<SessionGroup>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        guard let sessions = try? context.fetch(sessionDescriptor) else { return [] }
        return sessions.map { session in
            let sid = session.id
            let cardDescriptor = FetchDescriptor<ActionCard>(
                predicate: #Predicate { $0.sessionID == sid },
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
            let cards = (try? context.fetch(cardDescriptor)) ?? []
            return (session: session, cards: cards)
        }
    }

    func archiveSession(id: UUID) {
        let cardDescriptor = FetchDescriptor<ActionCard>(
            predicate: #Predicate { $0.sessionID == id }
        )
        if let cards = try? context.fetch(cardDescriptor) {
            for card in cards { card.isArchived = true }
        }
        var sessionDescriptor = FetchDescriptor<SessionGroup>(
            predicate: #Predicate { $0.id == id }
        )
        sessionDescriptor.fetchLimit = 1
        if let session = try? context.fetch(sessionDescriptor).first, session.endedAt == nil {
            session.endedAt = Date()
        }
        try? context.save()
    }

    // MARK: - Maintenance

    func pruneOldSessions(keepLast: Int = 200) {
        let sessionDescriptor = FetchDescriptor<SessionGroup>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        guard let all = try? context.fetch(sessionDescriptor), all.count > keepLast else { return }
        let toRemove = all.dropFirst(keepLast)
        for session in toRemove {
            let sid = session.id
            let cardDescriptor = FetchDescriptor<ActionCard>(
                predicate: #Predicate { $0.sessionID == sid }
            )
            if let cards = try? context.fetch(cardDescriptor) {
                for card in cards { context.delete(card) }
            }
            context.delete(session)
        }
        try? context.save()
    }

    // MARK: - Domain mapping

    static func domain(for toolName: String) -> String {
        switch toolName {
        case "calendar_create_event", "calendar_list_events", "calendar_delete_event":
            return "calendar"
        case "reminders_create", "reminders_list", "reminders_complete":
            return "reminders"
        case "contacts_search", "contacts_create":
            return "contacts"
        case "files_list", "files_read", "files_create", "files_create_folder", "files_delete":
            return "files"
        case "clipboard_read", "clipboard_write":
            return "clipboard"
        case "notification_schedule", "notification_cancel":
            return "notifications"
        case "web_fetch", "open_url":
            return "web"
        case "respond", "user_prompt", "agent_note":
            return "system"
        default:
            return "system"
        }
    }
}
