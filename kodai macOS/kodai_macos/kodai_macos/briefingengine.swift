//
//  briefingengine.swift
//  kodai_macos
//
//  J1 (jarvis-plan): composes the morning brief and evening debrief.
//  Composition is deterministic markdown built from SwiftData (tasks,
//  commitments) plus the read-only ~/life echo; an optional headline
//  composer (Foundation Models in the app, nil in tests) adds one short
//  opening line. Records persist as BriefingRecord and every delivery is
//  ledger-logged, so the rhythm itself stays auditable.
//

import Foundation
import KodaiCore
import SwiftData

// MARK: - Snapshot

/// Everything a briefing is composed from, gathered in one pass.
struct BriefingSnapshot {
    var dueToday: [KodaiTask] = []
    var overdue: [KodaiTask] = []
    var upcoming: [KodaiTask] = []
    var completedToday: [KodaiTask] = []
    var openCommitments: [KodaiCommitment] = []
    var journalEcho: LifeJournalReader.Echo?
}

// MARK: - Engine

@MainActor
@Observable
final class BriefingEngine {

    /// Composes one short opening sentence from the deterministic body.
    /// Injected so tests never depend on Foundation Models.
    typealias HeadlineComposer = (String) async -> String?

    private let headlineComposer: HeadlineComposer?
    private let ledgerRecorder: LedgerRecorder
    private let calendar: Calendar

    init(
        ledgerRecorder: LedgerRecorder? = nil,
        calendar: Calendar = .current,
        headlineComposer: HeadlineComposer? = nil
    ) {
        self.ledgerRecorder = ledgerRecorder ?? LedgerRecorder()
        self.calendar = calendar
        self.headlineComposer = headlineComposer
    }

    // MARK: Snapshot gathering

    func snapshot(now: Date = .now, context: ModelContext) -> BriefingSnapshot {
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let upcomingHorizon = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? now

        var snapshot = BriefingSnapshot()

        let tasks = (try? context.fetch(FetchDescriptor<KodaiTask>())) ?? []
        for task in tasks {
            if task.isCompleted {
                if let completedAt = task.completedAt,
                   completedAt >= startOfToday, completedAt < endOfToday {
                    snapshot.completedToday.append(task)
                }
                continue
            }
            guard let dueDate = task.dueDate else { continue }
            if dueDate < startOfToday {
                snapshot.overdue.append(task)
            } else if dueDate < endOfToday {
                snapshot.dueToday.append(task)
            } else if dueDate < upcomingHorizon {
                snapshot.upcoming.append(task)
            }
        }
        snapshot.overdue.sort { ($0.dueDate ?? now) < ($1.dueDate ?? now) }
        snapshot.dueToday.sort { $0.priority.sortOrder < $1.priority.sortOrder }
        snapshot.upcoming.sort { ($0.dueDate ?? now) < ($1.dueDate ?? now) }

        let commitments = (try? context.fetch(FetchDescriptor<KodaiCommitment>())) ?? []
        snapshot.openCommitments = commitments
            .filter { $0.status == .open }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now) {
            snapshot.journalEcho = LifeJournalReader.echo(for: yesterday, calendar: calendar)
        }

        return snapshot
    }

    // MARK: Composition

    /// Returns today's briefing of `kind`, composing (and persisting) it if
    /// it doesn't exist yet. Idempotent per (day, kind).
    @discardableResult
    func briefing(
        kind: BriefingKind,
        now: Date = .now,
        context: ModelContext
    ) async -> BriefingRecord {
        let day = calendar.startOfDay(for: now)
        if let existing = existingBriefing(kind: kind, day: day, context: context) {
            return existing
        }

        let snapshot = snapshot(now: now, context: context)
        var content = switch kind {
        case .morning: morningMarkdown(from: snapshot, now: now)
        case .evening: eveningMarkdown(from: snapshot, now: now)
        }

        if let headlineComposer,
           let headline = await headlineComposer(content),
           !headline.isEmpty {
            let lines = content.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            if lines.count == 2 {
                content = "\(lines[0])\n\n_\(headline.trimmingCharacters(in: .whitespacesAndNewlines))_\n\(lines[1])"
            }
        }

        // Another turn of the run loop may have composed the same briefing
        // while the headline composer was awaited — keep it idempotent.
        if let existing = existingBriefing(kind: kind, day: day, context: context) {
            return existing
        }

        let record = BriefingRecord(kind: kind, day: day, content: content)
        context.insert(record)
        try? context.save()
        return record
    }

    func markDelivered(_ record: BriefingRecord, at date: Date = .now, context: ModelContext) {
        guard record.deliveredAt == nil else { return }
        record.deliveredAt = date
        try? context.save()
        ledgerRecorder.recordActivity(
            kind: .briefingDelivered,
            summary: "\(record.kind.rawValue) briefing delivered",
            context: context
        )
    }

    func markOpened(_ record: BriefingRecord, at date: Date = .now, context: ModelContext) {
        guard record.openedAt == nil else { return }
        record.openedAt = date
        try? context.save()
    }

    /// Stores the evening reflection on the record. (Journal append into
    /// ~/life arrives with the read-write folder grant — the current
    /// LifeFolderAccess scope is read-only.)
    func saveReflection(_ text: String, for record: BriefingRecord, context: ModelContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        record.reflection = trimmed
        try? context.save()
    }

    private func existingBriefing(
        kind: BriefingKind,
        day: Date,
        context: ModelContext
    ) -> BriefingRecord? {
        let records = (try? context.fetch(FetchDescriptor<BriefingRecord>())) ?? []
        return records.first { $0.kind == kind && $0.day == day }
    }

    // MARK: Markdown

    private func morningMarkdown(from snapshot: BriefingSnapshot, now: Date) -> String {
        var sections: [String] = ["# Morning brief — \(longDate(now))"]

        if snapshot.dueToday.isEmpty && snapshot.overdue.isEmpty {
            sections.append("## Today\nNo tasks due today.")
        } else {
            if !snapshot.overdue.isEmpty {
                sections.append("## Overdue\n" + snapshot.overdue.map(taskLine).joined(separator: "\n"))
            }
            if !snapshot.dueToday.isEmpty {
                sections.append("## Due today\n" + snapshot.dueToday.map(taskLine).joined(separator: "\n"))
            }
        }

        if !snapshot.upcoming.isEmpty {
            sections.append("## Coming up\n" + snapshot.upcoming.prefix(5).map(taskLine).joined(separator: "\n"))
        }

        if !snapshot.openCommitments.isEmpty {
            sections.append("## Commitments\n" + snapshot.openCommitments.map(commitmentLine).joined(separator: "\n"))
        }

        if let echo = snapshot.journalEcho, !echo.isEmpty {
            var lines: [String] = []
            if !echo.ships.isEmpty {
                lines.append("Shipped: " + echo.ships.joined(separator: "; "))
            }
            if let note = echo.debriefNote {
                lines.append("Debrief: \(note)")
            }
            sections.append("## Yesterday in ~/life\n" + lines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    private func eveningMarkdown(from snapshot: BriefingSnapshot, now: Date) -> String {
        var sections: [String] = ["# Evening debrief — \(longDate(now))"]

        if snapshot.completedToday.isEmpty {
            sections.append("## Done today\nNothing marked done today.")
        } else {
            sections.append(
                "## Done today (\(snapshot.completedToday.count))\n"
                + snapshot.completedToday.map { "- \($0.title)" }.joined(separator: "\n")
            )
        }

        let slippingToday = snapshot.dueToday + snapshot.overdue
        if !slippingToday.isEmpty {
            sections.append(
                "## Due but not done (\(slippingToday.count))\n"
                + slippingToday.map(taskLine).joined(separator: "\n")
            )
        }

        if !snapshot.openCommitments.isEmpty {
            sections.append("## Open commitments\n" + snapshot.openCommitments.map(commitmentLine).joined(separator: "\n"))
        }

        sections.append("## Reflection\nTwo lines: what moved, what didn't?")

        return sections.joined(separator: "\n\n")
    }

    private func taskLine(_ task: KodaiTask) -> String {
        var line = "- \(task.title)"
        var tags: [String] = []
        if task.priority == .high { tags.append("high") }
        if let dueDate = task.dueDate { tags.append("due \(shortDate(dueDate))") }
        if !tags.isEmpty { line += " (\(tags.joined(separator: ", ")))" }
        return line
    }

    private func commitmentLine(_ commitment: KodaiCommitment) -> String {
        var line = "- \(commitment.text)"
        if let dueDate = commitment.dueDate { line += " — due \(shortDate(dueDate))" }
        return line
    }

    private func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Foundation Models headline

import FoundationModels

extension BriefingEngine {
    /// The app's default headline composer: one grounded sentence from the
    /// on-device model. Falls back to nil (no headline) on any failure.
    static func foundationModelsHeadlineComposer() -> HeadlineComposer {
        { briefingBody in
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let session = LanguageModelSession(
                instructions: """
                You open the user's daily briefing. Given the briefing body, write ONE short \
                sentence (max 18 words) that sets the tone for the day. Be concrete and \
                grounded in the content — never invent tasks or numbers. No emoji.
                """
            )
            do {
                var result = ""
                for try await partial in session.streamResponse(to: briefingBody) {
                    result = partial.content
                }
                let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            } catch {
                return nil
            }
        }
    }
}
