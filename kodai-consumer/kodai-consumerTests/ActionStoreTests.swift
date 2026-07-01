import Testing
import Foundation
import SwiftData
@testable import kodai_consumer

private func makeStore() throws -> ActionStore {
    let schema = Schema([ActionCard.self, SessionGroup.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: config)
    return ActionStore(context: ModelContext(container))
}

struct ActionStoreTests {

    // MARK: - Session + feed

    @Test func startSessionAndLogActions() throws {
        let store = try makeStore()
        let sid = store.startSession(prompt: "set a reminder")

        store.logAction(
            toolName: "reminders_create",
            domain: "reminders",
            summary: "Call dentist — Friday",
            status: "done",
            sessionID: sid
        )
        store.logAction(
            toolName: "reminders_create",
            domain: "reminders",
            summary: "Buy milk — Saturday",
            status: "done",
            sessionID: sid
        )

        let cards = store.feedCards()
        #expect(cards.count == 2)
        #expect(cards[0].summary == "Call dentist — Friday")
        #expect(cards[1].summary == "Buy milk — Saturday")
    }

    // MARK: - Archive

    @Test func archiveSessionMovesCardsOutOfFeed() throws {
        let store = try makeStore()
        let sid = store.startSession(prompt: "create event")

        store.logAction(
            toolName: "calendar_create_event",
            domain: "calendar",
            summary: "Team sync — Tomorrow, 2:00 PM",
            status: "done",
            sessionID: sid
        )

        store.endSession(id: sid)
        store.archiveSession(id: sid)

        #expect(store.feedCards().isEmpty)

        let archives = store.archiveSessions()
        #expect(archives.count == 1)
        #expect(archives[0].session.prompt == "create event")
        #expect(archives[0].cards.count == 1)
    }

    // MARK: - Prompt and note kinds

    @Test func promptAndNoteHaveCorrectKinds() throws {
        let store = try makeStore()
        let sid = store.startSession(prompt: "hello")

        store.logPrompt(text: "What's on my calendar?", sessionID: sid)
        store.logNote(text: "You have 3 events today.", sessionID: sid)

        let cards = store.feedCards()
        #expect(cards.count == 2)
        #expect(cards[0].kind == "prompt")
        #expect(cards[0].toolName == "user_prompt")
        #expect(cards[0].domain == "system")
        #expect(cards[1].kind == "note")
        #expect(cards[1].toolName == "agent_note")
        #expect(cards[1].domain == "system")
    }

    // MARK: - Upcoming cards

    @Test func upcomingCardsReturnsFutureDatedOnly() throws {
        let store = try makeStore()
        let sid = store.startSession(prompt: "test")
        let future = Date().addingTimeInterval(86400)
        let past = Date().addingTimeInterval(-86400)

        store.logAction(
            toolName: "calendar_create_event",
            domain: "calendar",
            summary: "Future event",
            status: "done",
            sessionID: sid,
            relatedDate: future
        )
        store.logAction(
            toolName: "calendar_create_event",
            domain: "calendar",
            summary: "Past event",
            status: "done",
            sessionID: sid,
            relatedDate: past
        )
        store.logAction(
            toolName: "files_create",
            domain: "files",
            summary: "A file",
            status: "done",
            sessionID: sid,
            relatedDate: future
        )

        let upcoming = store.upcomingCards()
        #expect(upcoming.count == 1)
        #expect(upcoming[0].summary == "Future event")
    }

    // MARK: - Prune

    @Test func pruneOldSessionsRemovesBeyondLimit() throws {
        let store = try makeStore()

        for i in 0..<5 {
            let sid = store.startSession(prompt: "session \(i)")
            store.logAction(
                toolName: "reminders_create",
                domain: "reminders",
                summary: "item \(i)",
                status: "done",
                sessionID: sid
            )
            store.endSession(id: sid)
        }

        store.pruneOldSessions(keepLast: 2)

        let archives = store.archiveSessions()
        #expect(archives.count == 2)
        #expect(store.feedCards().count == 2)
    }

    // MARK: - Domain mapping

    @Test func domainMappingCoversAllTools() {
        #expect(ActionStore.domain(for: "calendar_create_event") == "calendar")
        #expect(ActionStore.domain(for: "calendar_list_events") == "calendar")
        #expect(ActionStore.domain(for: "calendar_delete_event") == "calendar")
        #expect(ActionStore.domain(for: "reminders_create") == "reminders")
        #expect(ActionStore.domain(for: "reminders_list") == "reminders")
        #expect(ActionStore.domain(for: "reminders_complete") == "reminders")
        #expect(ActionStore.domain(for: "contacts_search") == "contacts")
        #expect(ActionStore.domain(for: "contacts_create") == "contacts")
        #expect(ActionStore.domain(for: "files_list") == "files")
        #expect(ActionStore.domain(for: "files_read") == "files")
        #expect(ActionStore.domain(for: "files_create") == "files")
        #expect(ActionStore.domain(for: "files_delete") == "files")
        #expect(ActionStore.domain(for: "clipboard_read") == "clipboard")
        #expect(ActionStore.domain(for: "clipboard_write") == "clipboard")
        #expect(ActionStore.domain(for: "notification_schedule") == "notifications")
        #expect(ActionStore.domain(for: "notification_cancel") == "notifications")
        #expect(ActionStore.domain(for: "web_fetch") == "web")
        #expect(ActionStore.domain(for: "open_url") == "web")
        #expect(ActionStore.domain(for: "respond") == "system")
        #expect(ActionStore.domain(for: "unknown_tool") == "system")
    }

    // MARK: - End session sets endedAt

    @Test func endSessionSetsEndedAt() throws {
        let store = try makeStore()
        let sid = store.startSession(prompt: "test")
        store.endSession(id: sid)

        let archives = store.archiveSessions()
        #expect(archives.count == 1)
        #expect(archives[0].session.endedAt != nil)
    }

    // MARK: - Feed ordering

    @Test func feedCardsReturnInTimestampOrder() throws {
        let store = try makeStore()
        let sid = store.startSession(prompt: "ordering test")

        store.logAction(toolName: "reminders_create", domain: "reminders", summary: "First", status: "done", sessionID: sid)
        store.logAction(toolName: "reminders_create", domain: "reminders", summary: "Second", status: "done", sessionID: sid)
        store.logAction(toolName: "reminders_create", domain: "reminders", summary: "Third", status: "done", sessionID: sid)

        let cards = store.feedCards()
        #expect(cards.count == 3)
        #expect(cards[0].summary == "First")
        #expect(cards[2].summary == "Third")
    }

    // MARK: - Cards persist after save

    @Test func cardsPersistAcrossQueries() throws {
        let store = try makeStore()
        let sid = store.startSession(prompt: "persist test")
        store.logAction(toolName: "clipboard_write", domain: "clipboard", summary: "Copied text", status: "done", sessionID: sid)

        let cards1 = store.feedCards()
        #expect(cards1.count == 1)

        let cards2 = store.feedCards()
        #expect(cards2.count == 1)
        #expect(cards2[0].summary == "Copied text")
    }

    // MARK: - Start session returns UUID

    @Test func startSessionReturnsUUID() throws {
        let store = try makeStore()
        let sid = store.startSession(prompt: "uuid test")
        #expect(sid != UUID())
    }

    // MARK: - Archive session marks cards archived

    @Test func archiveSessionMarksAllCardsArchived() throws {
        let store = try makeStore()
        let sid = store.startSession(prompt: "archive test")

        store.logAction(toolName: "web_fetch", domain: "web", summary: "Fetched page", status: "done", sessionID: sid)
        store.logAction(toolName: "open_url", domain: "web", summary: "Opened URL", status: "done", sessionID: sid)

        store.archiveSession(id: sid)

        let feed = store.feedCards()
        #expect(feed.isEmpty)
    }
}
