//
//  persistencerecovery.swift
//  kodai_macos
//
//  Boot-time store recovery. Stage-1 staged migration failing with "unknown
//  model version" is EXPECTED on healthy stores: the final container stamps
//  default.store with an unversioned union-schema checksum that the migration
//  plan does not recognize (NSCocoaErrorDomain 134504). Corruption is
//  therefore only declared when the final container itself fails to open.
//  When that happens the broken files are quarantined (never deleted) and the
//  newest quarantined snapshot that still contains chat rows is restored
//  before falling back to empty stores.
//

import Foundation
import SQLite3

enum PersistenceRecovery {

    private static let storeSuffixes = ["", "-wal", "-shm"]
    static let corruptStoresFolderName = "CorruptStores"

    // MARK: - Quarantine

    /// Moves the given store files (plus -wal/-shm sidecars) into a
    /// timestamped CorruptStores folder next to the first store. Returns the
    /// quarantine folder, or nil if nothing was moved.
    @discardableResult
    static func quarantine(storeURLs: [URL]) -> URL? {
        guard let baseDir = storeURLs.first?.deletingLastPathComponent() else { return nil }
        let fm = FileManager.default
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let corruptDir = baseDir
            .appendingPathComponent(corruptStoresFolderName, isDirectory: true)
            .appendingPathComponent(timestamp, isDirectory: true)

        var movedAnything = false
        for storeURL in storeURLs {
            for suffix in storeSuffixes {
                let src = URL(fileURLWithPath: storeURL.path + suffix)
                guard fm.fileExists(atPath: src.path) else { continue }
                if !movedAnything {
                    try? fm.createDirectory(at: corruptDir, withIntermediateDirectories: true)
                }
                let dst = corruptDir.appendingPathComponent(src.lastPathComponent)
                do {
                    try fm.moveItem(at: src, to: dst)
                    movedAnything = true
                    print("[PersistenceCheck] Quarantined \(src.lastPathComponent) → \(corruptStoresFolderName)/\(timestamp)/")
                } catch {
                    print("[PersistenceCheck] Failed to quarantine \(src.lastPathComponent): \(error)")
                }
            }
        }
        return movedAnything ? corruptDir : nil
    }

    // MARK: - Snapshot scan

    /// Newest CorruptStores snapshot whose copy of the given store file still
    /// contains chat sessions. Folder names are ISO-8601 timestamps, so
    /// lexicographic order is chronological.
    static func newestSnapshotWithChats(near storeURL: URL) -> URL? {
        let corruptDir = storeURL.deletingLastPathComponent()
            .appendingPathComponent(corruptStoresFolderName, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: corruptDir, includingPropertiesForKeys: nil
        ) else { return nil }

        let storeName = storeURL.lastPathComponent
        for snapshot in entries.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            let candidate = snapshot.appendingPathComponent(storeName)
            if chatSessionCount(in: candidate) > 0 { return snapshot }
        }
        return nil
    }

    /// Number of rows in the store's chat-session table, or 0 when the file
    /// is missing or unreadable. Read-only SQLite access — never mutates.
    static func chatSessionCount(in storeURL: URL) -> Int {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return 0 }
        var db: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return 0
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db, "SELECT COUNT(*) FROM ZKODAICHATSESSION", -1, &statement, nil
        ) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    // MARK: - Restore

    /// Copies the snapshot's store files back to the live location. Copies
    /// (never moves) so the snapshot stays intact if the restored store fails
    /// again. Only the local store is restored — workspace projects and tasks
    /// re-sync from CloudKit on their own.
    static func restoreSnapshot(_ snapshotDir: URL, to storeURL: URL) -> Bool {
        let fm = FileManager.default
        let storeName = storeURL.lastPathComponent
        guard fm.fileExists(atPath: snapshotDir.appendingPathComponent(storeName).path) else {
            return false
        }

        for suffix in storeSuffixes {
            let src = snapshotDir.appendingPathComponent(storeName + suffix)
            let dst = URL(fileURLWithPath: storeURL.path + suffix)
            try? fm.removeItem(at: dst)
            guard fm.fileExists(atPath: src.path) else { continue }
            do {
                try fm.copyItem(at: src, to: dst)
            } catch {
                print("[PersistenceCheck] Restore failed for \(src.lastPathComponent): \(error)")
                return false
            }
        }
        print("[PersistenceCheck] Restored \(storeName) from \(corruptStoresFolderName)/\(snapshotDir.lastPathComponent)")
        return true
    }
}
