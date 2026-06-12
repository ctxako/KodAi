//
//  WorkspaceProjectStore.swift
//  kodAI_chatbot_dev
//
//  K2D: SwiftData-backed source of truth for iOS projects/tasks. The API
//  mirrors ProjectTaskStore so ChatViewModel keeps working against the same
//  load/save shape with KodaiProjectValue values.
//
//  On first access it runs ProjectsJSONMigration to import any existing
//  Projects.json into the local workspace store. If the container can't be
//  created or the migration fails, the store falls back to the JSON
//  ProjectTaskStore so the user never loses projects/tasks.
//
//  Chats stay JSON-only: this store never reads or writes KodaiChatSession,
//  KodaiChatMessage, KodaiSummary, or KodaiStream, even though the closed
//  SwiftData relationship graph forces them into the container schema.
//

import Foundation
import KodaiKernel
import KodaiPersistence
import SwiftData

actor WorkspaceProjectStore {
    private let log = AppLog(category: "WorkspaceProjectStore")
    private let jsonFileURL: URL
    private let jsonFallbackStore: ProjectTaskStore
    private let container: ModelContainer?
    private var useJSONFallback = false
    private var migrationAttempted = false

    init() {
        let fileURL = ProjectTaskStore.defaultProjectsFileURL()
        jsonFileURL = fileURL
        jsonFallbackStore = ProjectTaskStore(projectsFileURL: fileURL)
        do {
            container = try WorkspaceModelContainer.makeLocal()
        } catch {
            // Fail safe: without a container the JSON store stays the source
            // of truth, exactly as before K2D.
            container = nil
            useJSONFallback = true
            log.event("workspace container creation failed; using JSON fallback: \(error.localizedDescription)")
        }
    }

    /// Test seam: inject a container (e.g. in-memory) and a JSON location.
    init(container: ModelContainer, jsonFileURL: URL) {
        self.jsonFileURL = jsonFileURL
        self.jsonFallbackStore = ProjectTaskStore(projectsFileURL: jsonFileURL)
        self.container = container
    }

    func loadProjects() async throws -> [KodaiProjectLite] {
        migrateIfNeeded()
        guard let container, !useJSONFallback else {
            return try await jsonFallbackStore.loadProjects()
        }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<KodaiProject>()
        // Newest first, matching the JSON store's insert-at-front ordering.
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        let projects = try context.fetch(descriptor).map(\.valueRepresentation)
        log.event("projects loaded count=\(projects.count)")
        return projects
    }

    func saveProjects(_ projects: [KodaiProjectLite]) async throws {
        migrateIfNeeded()
        guard let container, !useJSONFallback else {
            try await jsonFallbackStore.saveProjects(projects)
            return
        }
        let context = ModelContext(container)
        try reconcile(projects, in: context)
        try context.save()
        log.event("projects saved count=\(projects.count)")
    }

    // MARK: - Migration

    private func migrateIfNeeded() {
        guard !migrationAttempted else { return }
        migrationAttempted = true
        guard let container, !useJSONFallback else { return }

        // Dedicated context: if anything throws, its unsaved changes are
        // discarded with it and Projects.json is left untouched.
        let context = ModelContext(container)
        do {
            switch try ProjectsJSONMigration.run(jsonFileURL: jsonFileURL, context: context) {
            case .noFile:
                log.event("migration skipped: no Projects.json")
            case .migrated(let projectCount, let taskCount, let backupURL):
                log.event("migrated projects=\(projectCount) tasks=\(taskCount) backup=\(backupURL.lastPathComponent)")
            }
        } catch {
            useJSONFallback = true
            log.event("migration failed; using JSON fallback: \(error)")
        }
    }

    // MARK: - SwiftData reconciliation

    /// Full upsert-by-id of the in-memory array onto the store: existing
    /// models are updated via the K2B apply(_:) adapters, new ones inserted,
    /// and models absent from the array deleted. There is no `.unique`
    /// attribute (CloudKit prep), so ids are matched manually.
    private func reconcile(_ values: [KodaiProjectLite], in context: ModelContext) throws {
        let existingProjects = try context.fetch(FetchDescriptor<KodaiProject>())
        var projectsByID = Dictionary(existingProjects.map { ($0.id, $0) }) { first, _ in first }

        for value in values {
            guard let project = projectsByID.removeValue(forKey: value.id) else {
                context.insert(KodaiProject(value: value))
                continue
            }
            project.apply(value)
            var tasksByID = Dictionary(project.tasks.map { ($0.id, $0) }) { first, _ in first }
            for taskValue in value.tasks {
                if let task = tasksByID.removeValue(forKey: taskValue.id) {
                    task.apply(taskValue)
                } else {
                    let task = KodaiTask(value: taskValue)
                    task.project = project
                    context.insert(task)
                }
            }
            for removed in tasksByID.values {
                context.delete(removed)
            }
        }

        // Cascade also removes the project's tasks; sessions are never
        // populated on iOS (chats are JSON-only), so nothing else is touched.
        for removed in projectsByID.values {
            context.delete(removed)
        }
    }
}
