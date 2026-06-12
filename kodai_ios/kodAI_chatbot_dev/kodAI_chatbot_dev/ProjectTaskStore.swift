//
//  ProjectTaskStore.swift
//  kodAI_chatbot_dev
//
//  JSON persistence for the lightweight project/task layer. Mirrors the
//  ChatStore pattern; kept separate so chat storage stays untouched.
//

import Foundation
import KodaiKernel

actor ProjectTaskStore {
    private let projectsFileURL: URL
    private let log = AppLog(category: "ProjectTaskStore")

    init(fileManager: FileManager = .default) {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "kodAI_chatbot_dev"
        let directoryURL = supportDirectory.appendingPathComponent(bundleIdentifier, isDirectory: true)
        projectsFileURL = directoryURL.appendingPathComponent("Projects.json")
    }

    func loadProjects() async throws -> [KodaiProjectLite] {
        guard FileManager.default.fileExists(atPath: projectsFileURL.path) else {
            log.event("projects loaded count=0")
            return []
        }

        do {
            let data = try Data(contentsOf: projectsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let projects = try decoder.decode([KodaiProjectLite].self, from: data)
            log.event("projects loaded count=\(projects.count)")
            return projects
        } catch {
            log.event("failed to decode projects: \(error.localizedDescription)")
            return []
        }
    }

    func saveProjects(_ projects: [KodaiProjectLite]) async throws {
        let directoryURL = projectsFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(projects)
        try data.write(to: projectsFileURL, options: [.atomic])
        log.event("projects saved count=\(projects.count)")
    }
}
