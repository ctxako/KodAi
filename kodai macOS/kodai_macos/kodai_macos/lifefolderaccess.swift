//
//  lifefolderaccess.swift
//  kodai_macos
//
//  Sandbox-safe access to the ~/life folder. Inside the sandbox "home" is the
//  app container, so ~/life must be granted once via the open panel; the grant
//  persists as a security-scoped bookmark (read-only scope, matching
//  ENABLE_USER_SELECTED_FILES=readonly) and is re-resolved on each launch.
//

import AppKit
import Foundation

@MainActor
enum LifeFolderAccess {
    private static let bookmarkKey = "life.folder.bookmark"
    private static var activeURL: URL?

    /// The granted ~/life folder, if any. Resolves the stored bookmark once per
    /// launch and keeps the security scope open for the app's lifetime.
    static var lifeDirectory: URL? {
        if let activeURL { return activeURL }

        if let data = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), url.startAccessingSecurityScopedResource() {
                if isStale {
                    saveBookmark(for: url)
                }
                activeURL = url
                return url
            }
        }

        // Non-sandboxed contexts (CLI builds, tests) can read the real home.
        let direct = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("life")
        if FileManager.default.isReadableFile(
            atPath: direct.appendingPathComponent("data/life.db").path
        ) {
            activeURL = direct
            return direct
        }
        return nil
    }

    /// One-time grant via the powerbox open panel.
    static func requestAccess() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Users/\(NSUserName())/life", isDirectory: true)
        panel.message = "Select your ~/life folder so KodAi can read the journal, dashboard and knowledge base."
        panel.prompt = "Use This Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        saveBookmark(for: url)
        _ = url.startAccessingSecurityScopedResource()
        activeURL = url
        return url
    }

    private static func saveBookmark(for url: URL) {
        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }
}
