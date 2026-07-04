//
//  accountabilitytests.swift
//  kodai_macosTests
//
//  J0 coverage: accountability models (KodaiCommitment, BriefingRecord),
//  the V5 local schema, and the quiet-hours window math.
//

import Foundation
import Testing
import SwiftData
import KodaiCore
@testable import KodAi

struct AccountabilityModelTests {

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: KodaiLocalStoreSchemaV5.self)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test func schemaV5IncludesAccountabilityEntities() {
        let entityNames = Set(Schema(versionedSchema: KodaiLocalStoreSchemaV5.self).entitiesByName.keys)
        #expect(entityNames.contains("KodaiCommitment"))
        #expect(entityNames.contains("BriefingRecord"))
        // V5 must not reintroduce workspace models into the local store.
        #expect(!entityNames.contains("KodaiProject"))
        #expect(!entityNames.contains("KodaiTask"))
    }

    @Test func commitmentDefaultsAndRoundTrip() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let sessionID = UUID()
        let commitment = KodaiCommitment(
            text: "Finish the design doc",
            sourceKind: .chat,
            sourceQuote: "I'll finish the design doc by Friday",
            sourceSessionID: sessionID,
            dueDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        context.insert(commitment)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<KodaiCommitment>())
        #expect(fetched.count == 1)
        let stored = try #require(fetched.first)
        #expect(stored.status == .open)
        #expect(stored.slipCount == 0)
        #expect(stored.lastNudgedAt == nil)
        #expect(stored.resolvedAt == nil)
        #expect(stored.sourceKind == .chat)
        #expect(stored.sourceQuote == "I'll finish the design doc by Friday")
        #expect(stored.sourceSessionID == sessionID)
    }

    @Test func briefingRecordRoundTrip() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let day = Calendar.current.startOfDay(for: .now)
        let briefing = BriefingRecord(kind: .morning, day: day, content: "## Today\n- one thing")
        context.insert(briefing)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<BriefingRecord>())
        #expect(fetched.count == 1)
        let stored = try #require(fetched.first)
        #expect(stored.kind == .morning)
        #expect(stored.day == day)
        #expect(stored.deliveredAt == nil)
        #expect(stored.openedAt == nil)
        #expect(stored.reflection == nil)
    }

    @Test @MainActor func ledgerAcceptsAccountabilityActivityKinds() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let recorder = LedgerRecorder()

        let nudge = recorder.recordActivity(
            kind: .nudgeSent,
            summary: "Nudged: design doc due today",
            context: context
        )
        #expect(nudge.kind == .nudgeSent)

        let brief = recorder.recordActivity(
            kind: .briefingDelivered,
            summary: "Morning brief delivered",
            context: context
        )
        #expect(brief.kind == .briefingDelivered)

        let events = try context.fetch(FetchDescriptor<ActivityEvent>())
        #expect(events.count == 2)
    }
}

struct QuietHoursTests {

    @Test func windowWrappingMidnight() {
        let start = 22 * 60  // 22:00
        let end = 8 * 60     // 08:00
        #expect(AccountabilitySettings.isQuietTime(minutes: 23 * 60, quietStart: start, quietEnd: end))
        #expect(AccountabilitySettings.isQuietTime(minutes: 3 * 60, quietStart: start, quietEnd: end))
        #expect(AccountabilitySettings.isQuietTime(minutes: 22 * 60, quietStart: start, quietEnd: end))
        #expect(!AccountabilitySettings.isQuietTime(minutes: 8 * 60, quietStart: start, quietEnd: end))
        #expect(!AccountabilitySettings.isQuietTime(minutes: 12 * 60, quietStart: start, quietEnd: end))
    }

    @Test func windowWithinSameDay() {
        let start = 13 * 60  // 13:00
        let end = 15 * 60    // 15:00
        #expect(AccountabilitySettings.isQuietTime(minutes: 14 * 60, quietStart: start, quietEnd: end))
        #expect(!AccountabilitySettings.isQuietTime(minutes: 15 * 60, quietStart: start, quietEnd: end))
        #expect(!AccountabilitySettings.isQuietTime(minutes: 12 * 60, quietStart: start, quietEnd: end))
    }

    @Test func degenerateEqualBoundsMeansNoQuietHours() {
        #expect(!AccountabilitySettings.isQuietTime(minutes: 0, quietStart: 480, quietEnd: 480))
        #expect(!AccountabilitySettings.isQuietTime(minutes: 480, quietStart: 480, quietEnd: 480))
    }
}
