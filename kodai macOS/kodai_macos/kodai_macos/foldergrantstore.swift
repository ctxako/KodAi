//
//  foldergrantstore.swift
//  kodai_macos
//
//  Multi-folder generalization of LifeFolderAccess: the user grants folders
//  once via the powerbox open panel and each grant persists as a
//  security-scoped bookmark. File tools resolve every path against these
//  grants — a path outside every granted folder is an honest tool failure,
//  never a silent read. Writes additionally require the grant's allowWrites
//  flag (and are still confirm-gated per call).
//

import AppKit
import Foundation
import Observation

struct FolderGrant: Identifiable, Codable, Equatable {
    let id: UUID
    var bookmark: Data
    var allowWrites: Bool
    /// Display path captured at grant time ("~/life"), for Settings and errors.
    var displayPath: String
}

@MainActor
@Observable
final class FolderGrantStore {
    private static let storageKey = "filetools.folder.grants"

    private(set) var grants: [FolderGrant] = []
    /// Resolved, security-scope-open roots by grant ID. Kept open for the
    /// app's lifetime, matching LifeFolderAccess behavior.
    @ObservationIgnored private var resolvedRoots: [UUID: URL] = [:]

    init() {
        load()
    }

    // MARK: - Grant management

    /// One-time grant via the powerbox open panel.
    @discardableResult
    func requestGrant(allowWrites: Bool) -> FolderGrant? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = allowWrites
            ? "Select a folder KodAi may read and (with your approval per file) write."
            : "Select a folder KodAi may read."
        panel.prompt = "Grant Access"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return addGrant(for: url, allowWrites: allowWrites)
    }

    @discardableResult
    func addGrant(for url: URL, allowWrites: Bool) -> FolderGrant? {
        var options: URL.BookmarkCreationOptions = [.withSecurityScope]
        if !allowWrites { options.insert(.securityScopeAllowOnlyReadAccess) }
        guard let bookmark = try? url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return nil }

        // Re-granting the same folder replaces the old grant.
        if let existing = grants.first(where: { rootURL(for: $0)?.path == url.path }) {
            removeGrant(existing)
        }

        let grant = FolderGrant(
            id: UUID(),
            bookmark: bookmark,
            allowWrites: allowWrites,
            displayPath: Self.abbreviatedPath(url.path)
        )
        grants.append(grant)
        _ = url.startAccessingSecurityScopedResource()
        resolvedRoots[grant.id] = url
        save()
        return grant
    }

    func removeGrant(_ grant: FolderGrant) {
        if let url = resolvedRoots.removeValue(forKey: grant.id) {
            url.stopAccessingSecurityScopedResource()
        }
        grants.removeAll { $0.id == grant.id }
        save()
    }

    /// Flipping writes re-creates the bookmark with the matching scope; needs
    /// the root to still resolve (it does while the grant is live).
    func setAllowWrites(_ allowWrites: Bool, for grant: FolderGrant) {
        guard grant.allowWrites != allowWrites,
              let url = rootURL(for: grant),
              let index = grants.firstIndex(where: { $0.id == grant.id }) else { return }

        var options: URL.BookmarkCreationOptions = [.withSecurityScope]
        if !allowWrites { options.insert(.securityScopeAllowOnlyReadAccess) }
        guard let bookmark = try? url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        grants[index].allowWrites = allowWrites
        grants[index].bookmark = bookmark
        save()
    }

    // MARK: - Resolution

    struct ResolvedPath {
        let url: URL
        let root: URL
        let writable: Bool
        /// Path relative to the grant root, for compact display.
        var relativeDescription: String {
            let rootPath = root.path
            let path = url.path
            guard path.hasPrefix(rootPath) else { return path }
            let rel = String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return rel.isEmpty ? root.lastPathComponent : "\(root.lastPathComponent)/\(rel)"
        }
    }

    /// Maps a model-provided path ("~/life/notes.md", absolute, or relative to
    /// a granted root's name) to a granted location, or nil if outside every
    /// grant. ~/life falls back to the existing LifeFolderAccess grant
    /// (read-only) so the Life HQ grant keeps working without a second prompt.
    func resolve(_ rawPath: String) -> ResolvedPath? {
        let expanded = Self.expandingTilde(rawPath)
        let candidate = URL(fileURLWithPath: expanded).standardizedFileURL

        for grant in grants {
            guard let root = rootURL(for: grant) else { continue }
            if let contained = Self.contained(candidate, in: root) {
                return ResolvedPath(url: contained, root: root, writable: grant.allowWrites)
            }
            // "life/notes.md" style — relative to a grant root's folder name.
            if !rawPath.hasPrefix("/") && !rawPath.hasPrefix("~") {
                let joined = root.deletingLastPathComponent()
                    .appendingPathComponent(expanded).standardizedFileURL
                if let contained = Self.contained(joined, in: root) {
                    return ResolvedPath(url: contained, root: root, writable: grant.allowWrites)
                }
            }
        }

        if let life = LifeFolderAccess.lifeDirectory {
            if let contained = Self.contained(candidate, in: life) {
                return ResolvedPath(url: contained, root: life, writable: false)
            }
            if !rawPath.hasPrefix("/") && !rawPath.hasPrefix("~") {
                let joined = life.deletingLastPathComponent()
                    .appendingPathComponent(expanded).standardizedFileURL
                if let contained = Self.contained(joined, in: life) {
                    return ResolvedPath(url: contained, root: life, writable: false)
                }
            }
        }
        return nil
    }

    /// All searchable roots (grants + the implicit ~/life grant), deduplicated.
    var searchRoots: [ResolvedPath] {
        var roots: [ResolvedPath] = grants.compactMap { grant in
            rootURL(for: grant).map {
                ResolvedPath(url: $0, root: $0, writable: grant.allowWrites)
            }
        }
        if let life = LifeFolderAccess.lifeDirectory,
           !roots.contains(where: { $0.root.path == life.path }) {
            roots.append(ResolvedPath(url: life, root: life, writable: false))
        }
        return roots
    }

    /// One-line summary for tool error messages: "~/life, ~/kodai".
    var grantedFoldersDescription: String {
        var names = grants.map(\.displayPath)
        if LifeFolderAccess.lifeDirectory != nil, !names.contains("~/life") {
            names.append("~/life (read-only)")
        }
        return names.isEmpty ? "none granted yet" : names.joined(separator: ", ")
    }

    // MARK: - Helpers

    private func rootURL(for grant: FolderGrant) -> URL? {
        if let url = resolvedRoots[grant.id] { return url }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: grant.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.startAccessingSecurityScopedResource() else { return nil }
        resolvedRoots[grant.id] = url
        return url
    }

    /// Symlink-resolved containment check; nil if the candidate escapes root.
    private static func contained(_ candidate: URL, in root: URL) -> URL? {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        // The candidate may not exist yet (write_file) — resolve the deepest
        // existing ancestor's symlinks and re-append the remainder.
        let resolved = candidate.resolvingSymlinksInPath()
        let path = resolved.path
        guard path == rootPath || path.hasPrefix(rootPath + "/") else { return nil }
        return resolved
    }

    private static func expandingTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        // Inside the sandbox, NSHomeDirectory is the container — expand to the
        // real home like LifeFolderAccess does.
        let home = "/Users/\(NSUserName())"
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    private static func abbreviatedPath(_ path: String) -> String {
        let home = "/Users/\(NSUserName())"
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([FolderGrant].self, from: data) else { return }
        grants = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(grants) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
