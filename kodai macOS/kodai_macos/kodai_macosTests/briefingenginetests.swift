//
//  briefingenginetests.swift
//  kodai_macosTests
//
//  J1 coverage: BriefingEngine snapshot bucketing, markdown composition,
//  per-(day, kind) idempotency, delivery ledger-logging, and reflection
//  capture. No Foundation Models dependency — the headline composer stays
//  nil (or a stub) in tests.
//

import Foundation
import Testing
import SwiftData
import KodaiCore
@testable import KodAi

@MainActor
struct BriefingEngineTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            KodaiProject.self,
            KodaiTask.self,
            KodaiCommitment.self,
            BriefingRecord.self,
            TurnRecord.self,
            ActivityEvent.self,
            ModelPerformanceMetric.self,
            ToolCall.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    /// A fixed "now" at 09:00 local so day bucketing is deterministic.
    private var now: Date {
        Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0,
            of: Calendar.current.startOfDay(for: .now)
        ) ?? .now
    }

    @Test func snapshotBucketsTasksByDueDate() throws {
        let context = try makeContext()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        let overdue = KodaiTask(title: "Overdue thing", dueDate: calendar.date(byAdding: .day, value: -2, to: startOfToday))
        let dueToday = KodaiTask(title: "Today thing", priority: .high, dueDate: now)
        let upcoming = KodaiTask(title: "Later thing", dueDate: calendar.date(byAdding: .day, value: 3, to: startOfToday))
        let farOut = KodaiTask(title: "Far thing", dueDate: calendar.date(byAdding: .day, value: 30, to: startOfToday))
        let doneToday = KodaiTask(title: "Done thing", isCompleted: true, completedAt: now)
        let noDue = KodaiTask(title: "Someday thing")
        for task in [overdue, dueToday, upcoming, farOut, doneToday, noDue] {
            context.insert(task)
        }
        try context.save()

        let engine = BriefingEngine()
        let snapshot = engine.snapshot(now: now, context: context)

        #expect(snapshot.overdue.map(\.title) == ["Overdue thing"])
        #expect(snapshot.dueToday.map(\.title) == ["Today thing"])
        #expect(snapshot.upcoming.map(\.title) == ["Later thing"])
        #expect(snapshot.completedToday.map(\.title) == ["Done thing"])
    }

    @Test func morningBriefContainsTasksAndCommitments() async throws {
        let context = try makeContext()
        context.insert(KodaiTask(title: "Ship the fix", priority: .high, dueDate: now))
        context.insert(KodaiCommitment(
            text: "Finish design doc",
            sourceKind: .chat,
            sourceQuote: "I'll finish the design doc by Friday",
            dueDate: now
        ))
        try context.save()

        let engine = BriefingEngine()
        let record = await engine.briefing(kind: .morning, now: now, context: context)

        #expect(record.kind == .morning)
        #expect(record.content.contains("# Morning brief"))
        #expect(record.content.contains("Ship the fix"))
        #expect(record.content.contains("Finish design doc"))
        #expect(record.day == Calendar.current.startOfDay(for: now))
    }

    @Test func eveningDebriefSeparatesDoneFromSlipping() async throws {
        let context = try makeContext()
        context.insert(KodaiTask(title: "Landed it", isCompleted: true, completedAt: now))
        context.insert(KodaiTask(title: "Slipped it", dueDate: now))
        try context.save()

        let engine = BriefingEngine()
        let record = await engine.briefing(kind: .evening, now: now, context: context)

        #expect(record.content.contains("# Evening debrief"))
        #expect(record.content.contains("Done today (1)"))
        #expect(record.content.contains("Landed it"))
        #expect(record.content.contains("Due but not done (1)"))
        #expect(record.content.contains("Slipped it"))
        #expect(record.content.contains("Reflection"))
    }

    @Test func briefingIsIdempotentPerDayAndKind() async throws {
        let context = try makeContext()
        let engine = BriefingEngine()

        let first = await engine.briefing(kind: .morning, now: now, context: context)
        let second = await engine.briefing(kind: .morning, now: now, context: context)
        let evening = await engine.briefing(kind: .evening, now: now, context: context)

        #expect(first.id == second.id)
        #expect(evening.id != first.id)
        let stored = try context.fetch(FetchDescriptor<BriefingRecord>())
        #expect(stored.count == 2)
    }

    @Test func headlineComposerInsertsOneLineUnderTitle() async throws {
        let context = try makeContext()
        let engine = BriefingEngine(headlineComposer: { _ in "Steady day ahead." })

        let record = await engine.briefing(kind: .morning, now: now, context: context)
        let lines = record.content.components(separatedBy: "\n")
        #expect(lines.first?.hasPrefix("# Morning brief") == true)
        #expect(record.content.contains("_Steady day ahead._"))
    }

    @Test func markDeliveredIsLedgerLoggedOnce() async throws {
        let context = try makeContext()
        let engine = BriefingEngine()
        let record = await engine.briefing(kind: .morning, now: now, context: context)

        engine.markDelivered(record, at: now, context: context)
        engine.markDelivered(record, at: now.addingTimeInterval(60), context: context)

        #expect(record.deliveredAt == now)
        let events = try context.fetch(FetchDescriptor<ActivityEvent>())
        #expect(events.filter { $0.kind == .briefingDelivered }.count == 1)
    }

    @Test func reflectionIsTrimmedAndStored() async throws {
        let context = try makeContext()
        let engine = BriefingEngine()
        let record = await engine.briefing(kind: .evening, now: now, context: context)

        engine.saveReflection("  moved the plan forward\nslipped on email  ", for: record, context: context)
        #expect(record.reflection == "moved the plan forward\nslipped on email")

        engine.saveReflection("   ", for: record, context: context)
        #expect(record.reflection == "moved the plan forward\nslipped on email")
    }
}
