//
//  lifejournalreader.swift
//  kodai_macos
//
//  Read-only lookups against ~/life/data/life.db for the daily rhythm:
//  a day's debrief note and shipped items become the "yesterday in ~/life"
//  echo inside the morning brief. Same read-only discipline as kb_search —
//  the app never writes to life.db.
//

import Foundation
import SQLite3

enum LifeJournalReader {

    struct Echo: Equatable {
        var debriefNote: String?
        var ships: [String]

        var isEmpty: Bool { debriefNote == nil && ships.isEmpty }
    }

    /// The debrief note and shipped items recorded in ~/life for `date`,
    /// or nil when the folder grant or database is unavailable.
    static func echo(for date: Date, calendar: Calendar = .current) -> Echo? {
        guard let lifeDirectory = LifeFolderAccess.lifeDirectory else { return nil }
        let databaseURL = lifeDirectory.appendingPathComponent("data/life.db")
        guard FileManager.default.isReadableFile(atPath: databaseURL.path) else { return nil }

        let dayKey = dayString(for: date, calendar: calendar)

        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        var echo = Echo(debriefNote: nil, ships: [])

        if let note = firstTextColumn(
            db: db,
            sql: "SELECT note FROM debriefs WHERE date = ?",
            parameter: dayKey
        ), !note.isEmpty {
            echo.debriefNote = note
        }

        echo.ships = allTextColumn(
            db: db,
            sql: "SELECT what FROM ships WHERE date = ? ORDER BY ts",
            parameter: dayKey
        )

        return echo
    }

    static func dayString(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    // MARK: - SQLite helpers

    private static func firstTextColumn(db: OpaquePointer?, sql: String, parameter: String) -> String? {
        allTextColumn(db: db, sql: sql, parameter: parameter).first
    }

    private static func allTextColumn(db: OpaquePointer?, sql: String, parameter: String) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, parameter, -1, transient) == SQLITE_OK else { return [] }

        var results: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
               !text.isEmpty {
                results.append(text)
            }
        }
        return results
    }
}
