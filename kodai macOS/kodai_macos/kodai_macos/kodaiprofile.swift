//
//  kodaiprofile.swift
//  kodai_macos
//
//  KODAI.md — the user's standing instructions, loaded from the root of a
//  granted folder (checked in grant order, ~/life last) and injected into
//  every turn's context, exactly like Claude Code loads CLAUDE.md. Cached by
//  modification date so edits take effect on the next turn without a restart.
//  Capped so personalization can't crowd out the 4096-token FM window.
//

import Foundation

@MainActor
enum KodaiProfileLoader {
    static let filename = "KODAI.md"
    private static let maxChars = 2_400

    private static var cachedContent: String?
    private static var cachedPath: String?
    private static var cachedModified: Date?

    /// The user's standing instructions, or nil when no KODAI.md exists yet.
    static func standingInstructions(grants: FolderGrantStore) -> String? {
        var candidates = grants.searchRoots.map { $0.root.appendingPathComponent(filename) }
        if let life = LifeFolderAccess.lifeDirectory {
            let lifeProfile = life.appendingPathComponent(filename)
            if !candidates.contains(where: { $0.path == lifeProfile.path }) {
                candidates.append(lifeProfile)
            }
        }

        for url in candidates {
            guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate else { continue }

            if url.path == cachedPath, modified == cachedModified {
                return cachedContent
            }
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let capped = trimmed.count > maxChars
                ? String(trimmed.prefix(maxChars)) + "\n[KODAI.md truncated]"
                : trimmed
            cachedContent = capped
            cachedPath = url.path
            cachedModified = modified
            return capped
        }
        return nil
    }
}
