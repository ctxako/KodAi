//
//  ProjectsJSONMigration.swift
//  kodAI_chatbot_dev
//
//  K2D: one-time import of Projects.json into the local SwiftData workspace
//  store. Preserve-first: the JSON file is only renamed to a timestamped
//  backup after the import has been saved and verified, and it is never
//  deleted. Any failure (decode, import, verify, save) throws before the
//  file is touched, so the JSON path keeps working.
//
//  Workspace data only: this imports projects and tasks. Chat sessions,
//  streams, and prompt settings stay in ChatStore JSON and are never written
//  through this container.
//

import Foundation
import KodaiKernel
import KodaiPersistence
import SwiftData

enum ProjectsJSONMigrationError: Error, CustomStringConvertible {
    case verificationFailed(String)

    var description: String {
        switch self {
        case .verificationFailed(let reason):
            return "verification failed: \(reason)"
        }
    }
}

enum ProjectsJSONMigration {
    enum Outcome: Equatable {
        /// No Projects.json on disk: fresh install or already migrated.
        case noFile
        case migrated(projectCount: Int, taskCount: Int, backupURL: URL)
    }

    static func run(
        jsonFileURL: URL,
        context: ModelContext,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> Outcome {
        guard fileManager.fileExists(atPath: jsonFileURL.path) else {
            return .noFile
        }

        // Decode with the same configuration ProjectTaskStore uses. A failure
        // here throws before any store or file mutation.
        let data = try Data(contentsOf: jsonFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let values = try decoder.decode([KodaiProjectValue].self, from: data)

        try upsert(values, into: context)
        try verify(values, in: context)
        try context.save()

        let backupURL = try moveToBackup(jsonFileURL: jsonFileURL, fileManager: fileManager, now: now)
        let taskCount = values.reduce(0) { $0 + $1.tasks.count }
        return .migrated(projectCount: values.count, taskCount: taskCount, backupURL: backupURL)
    }

    /// Imports by id: existing projects/tasks are updated in place via the
    /// K2B apply(_:) adapters, missing ones are inserted. No `.unique`
    /// attribute exists (CloudKit prep), so identity is checked manually.
    /// Nothing is deleted: migration only adds or updates.
    private static func upsert(_ values: [KodaiProjectValue], into context: ModelContext) throws {
        let existingProjects = try context.fetch(FetchDescriptor<KodaiProject>())
        let projectsByID = Dictionary(existingProjects.map { ($0.id, $0) }) { first, _ in first }

        for value in values {
            guard let project = projectsByID[value.id] else {
                context.insert(KodaiProject(value: value))
                continue
            }
            project.apply(value)
            let tasksByID = Dictionary((project.tasks ?? []).map { ($0.id, $0) }) { first, _ in first }
            for taskValue in value.tasks {
                if let task = tasksByID[taskValue.id] {
                    task.apply(taskValue)
                } else {
                    let task = KodaiTask(value: taskValue)
                    task.project = project
                    context.insert(task)
                }
            }
        }
    }

    private static func verify(_ values: [KodaiProjectValue], in context: ModelContext) throws {
        let projects = try context.fetch(FetchDescriptor<KodaiProject>())
        let projectsByID = Dictionary(projects.map { ($0.id, $0) }) { first, _ in first }

        for value in values {
            guard let project = projectsByID[value.id] else {
                throw ProjectsJSONMigrationError.verificationFailed("missing project \(value.id)")
            }
            guard project.title == value.title else {
                throw ProjectsJSONMigrationError.verificationFailed("title mismatch for project \(value.id)")
            }
            let taskIDs = Set((project.tasks ?? []).map(\.id))
            for taskValue in value.tasks where !taskIDs.contains(taskValue.id) {
                throw ProjectsJSONMigrationError.verificationFailed(
                    "missing task \(taskValue.id) in project \(value.id)"
                )
            }
        }
    }

    /// Renames Projects.json to e.g. Projects.json.migrated-20260612-143000,
    /// suffixing -2, -3, … if that name is somehow taken. Never deletes.
    private static func moveToBackup(
        jsonFileURL: URL,
        fileManager: FileManager,
        now: Date
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now)

        let directory = jsonFileURL.deletingLastPathComponent()
        let baseName = "\(jsonFileURL.lastPathComponent).migrated-\(stamp)"
        var candidate = directory.appendingPathComponent(baseName)
        var attempt = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(attempt)")
            attempt += 1
        }
        try fileManager.moveItem(at: jsonFileURL, to: candidate)
        return candidate
    }
}
