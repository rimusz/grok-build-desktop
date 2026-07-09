import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Where a memory file lives, mirroring grok's `~/.grok/memory/` layout.
enum MemoryScope: String, Sendable, Hashable {
    case global      // ~/.grok/memory/MEMORY.md — cross-project facts
    case workspace   // ~/.grok/memory/<slug-hash>/MEMORY.md — project-specific
    case session     // ~/.grok/memory/<slug-hash>/sessions/*.md — per-session logs
}

/// A single memory Markdown file discovered on disk.
struct MemoryFile: Identifiable, Hashable, Sendable {
    /// Absolute file path — stable and unique, so it doubles as the identity.
    var id: String { url.path }
    let scope: MemoryScope
    /// Display title (file name for sessions, the workspace dir name for workspace files).
    let title: String
    /// The `<slug-hash>` directory name for workspace/session files; nil for global.
    let workspaceLabel: String?
    let url: URL
    let modifiedAt: Date?

    var path: String { url.path }
}

/// Read-only view over grok's cross-session memory on disk plus a small write helper for
/// "Remember" notes. The app stays thin: grok owns indexing, search, and injection — this
/// only enumerates the Markdown files, previews them, appends notes, and (for session logs)
/// deletes them. Enumeration is pure over an injected base URL so it is unit-testable.
enum MemoryStore {
    /// `~/.grok/memory` — the same idiom as `CustomModelStore.configURL`.
    static var baseURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".grok/memory")
    }

    /// The global cross-project memory file (`~/.grok/memory/MEMORY.md`).
    static var globalMemoryURL: URL {
        baseURL.appendingPathComponent("MEMORY.md")
    }

    /// Enumerate all memory files under `base`, grouped global → workspace → sessions.
    /// Workspaces are ordered by directory name; each workspace's `MEMORY.md` precedes its
    /// session logs, which are ordered newest-first.
    static func load(base: URL = baseURL, fileManager: FileManager = .default) -> [MemoryFile] {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: base.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        var files: [MemoryFile] = []

        // Global MEMORY.md
        let global = base.appendingPathComponent("MEMORY.md")
        if fileManager.fileExists(atPath: global.path) {
            files.append(MemoryFile(
                scope: .global,
                title: "Global memory",
                workspaceLabel: nil,
                url: global,
                modifiedAt: modificationDate(of: global, fileManager: fileManager)
            ))
        }

        // Workspace directories: <slug-hash>/MEMORY.md and <slug-hash>/sessions/*.md
        let workspaceDirs = (try? fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let sortedDirs = workspaceDirs
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        for dir in sortedDirs {
            let label = dir.lastPathComponent
            let workspaceFile = dir.appendingPathComponent("MEMORY.md")
            if fileManager.fileExists(atPath: workspaceFile.path) {
                files.append(MemoryFile(
                    scope: .workspace,
                    title: label,
                    workspaceLabel: label,
                    url: workspaceFile,
                    modifiedAt: modificationDate(of: workspaceFile, fileManager: fileManager)
                ))
            }

            let sessionsDir = dir.appendingPathComponent("sessions")
            let sessionFiles = (try? fileManager.contentsOfDirectory(
                at: sessionsDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            let sessions = sessionFiles
                .filter { $0.pathExtension.lowercased() == "md" }
                .map { url in
                    MemoryFile(
                        scope: .session,
                        title: url.deletingPathExtension().lastPathComponent,
                        workspaceLabel: label,
                        url: url,
                        modifiedAt: modificationDate(of: url, fileManager: fileManager)
                    )
                }
                .sorted(by: Self.sessionOrdering)

            files.append(contentsOf: sessions)
        }

        return files
    }

    /// Newest-first ordering for session logs (falls back to name-descending when dates tie).
    static func sessionOrdering(_ a: MemoryFile, _ b: MemoryFile) -> Bool {
        switch (a.modifiedAt, b.modifiedAt) {
        case let (da?, db?) where da != db:
            return da > db
        default:
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedDescending
        }
    }

    static func readContents(_ file: MemoryFile) -> String? {
        try? String(contentsOf: file.url, encoding: .utf8)
    }

    /// Deletes a session log. Global/workspace `MEMORY.md` are protected (matches the TUI).
    static func deleteSessionFile(_ file: MemoryFile, fileManager: FileManager = .default) throws {
        guard file.scope == .session else {
            throw MemoryStoreError.notDeletable
        }
        try fileManager.removeItem(at: file.url)
    }

    /// Appends a note to the global `MEMORY.md` under a `## Notes` heading, creating the file
    /// and directory if needed. grok's file watcher reindexes the change on the next memory
    /// search, so this is the app's supported "Remember" path (the `/remember` slash command is
    /// a TUI-only pager builtin and is not exposed over ACP).
    @discardableResult
    static func appendGlobalNote(
        _ text: String,
        to url: URL = globalMemoryURL,
        fileManager: FileManager = .default,
        date: Date = Date()
    ) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MemoryStoreError.emptyNote }

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let entry = "- \(trimmed)"
        let updated = Self.appendingNote(entry, to: existing)
        try updated.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Pure string builder: appends `entry` under a `## Notes` heading, adding the heading when
    /// missing and keeping existing content intact. Testable without touching disk.
    static func appendingNote(_ entry: String, to existing: String) -> String {
        let heading = "## Notes"
        if existing.range(of: heading) != nil {
            var body = existing
            if !body.hasSuffix("\n") { body += "\n" }
            return body + entry + "\n"
        }
        var body = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { body += "\n\n" }
        return body + heading + "\n\n" + entry + "\n"
    }

    static func revealInFinder(_ file: MemoryFile) {
        #if canImport(AppKit)
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
        #endif
    }

    private static func modificationDate(of url: URL, fileManager: FileManager) -> Date? {
        (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

enum MemoryStoreError: LocalizedError {
    case notDeletable
    case emptyNote

    var errorDescription: String? {
        switch self {
        case .notDeletable:
            return "Only per-session memory logs can be deleted. Edit global or workspace MEMORY.md directly."
        case .emptyNote:
            return "The note is empty."
        }
    }
}
