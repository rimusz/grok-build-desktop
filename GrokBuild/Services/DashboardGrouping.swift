import Foundation

/// Git snapshot used by the session dashboard (filled off the main thread).
struct DashboardGitSnapshot: Equatable, Sendable {
    var isWorktree: Bool
    var branch: String?
    var dirtyCount: Int
}

/// Inputs for dashboard grouping. Kept separate from `ChatStore` so the rules are unit-testable.
struct DashboardGroupingInputs: Equatable, Sendable {
    var isStreaming: Bool = false
    var isStarting: Bool = false
    var isBusy: Bool = false
    var isFailed: Bool = false
    var pendingUserCount: Int = 0
    var hasUnreadCompletion: Bool = false
    var dirtyCount: Int = 0
    var scheduledCount: Int = 0
}

/// Pure mapping from live session signals to a dashboard group.
///
/// Priority (highest first): needs you → failed → working → needs review → scheduled → idle.
/// Needs-you wins so a blocked or unread teammate is never buried under a dirty worktree.
enum DashboardGrouping {
    static func group(_ inputs: DashboardGroupingInputs) -> SessionDashboardEntry.Group {
        if inputs.pendingUserCount > 0 || inputs.hasUnreadCompletion {
            return .needsYou
        }
        if inputs.isFailed {
            return .failed
        }
        if inputs.isStreaming || inputs.isStarting || inputs.isBusy {
            return .working
        }
        if inputs.dirtyCount > 0 {
            return .needsReview
        }
        if inputs.scheduledCount > 0 {
            return .scheduled
        }
        return .idle
    }
}

/// Live roster and history are scoped to the selected project, not every open tab.
enum DashboardScope {
    static func isInCurrentProject(sessionWorkspaceID: UUID, currentWorkspaceID: UUID?) -> Bool {
        guard let currentWorkspaceID else { return false }
        return sessionWorkspaceID == currentWorkspaceID
    }
}

/// Git snapshot paths for the open dashboard — current project only, de-duplicated by path.
enum DashboardGitRefresh {
    static func uniquePaths(
        sessions: [(workspaceID: UUID, path: URL)],
        currentWorkspaceID: UUID?
    ) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for session in sessions {
            guard DashboardScope.isInCurrentProject(
                sessionWorkspaceID: session.workspaceID,
                currentWorkspaceID: currentWorkspaceID
            ) else { continue }
            let url = session.path.standardizedFileURL
            if seen.insert(url.path).inserted {
                result.append(url)
            }
        }
        return result
    }
}

/// LRU eviction for live `grok agent stdio` processes.
///
/// Keeps the selected tab, the MRU window, any mid-turn session, and any session that owns
/// a grok `/loop` schedule so automations do not die when a fifth tab opens.
enum ConnectionCapPolicy {
    /// True when this session's grok process may be shut down to stay under the LRU cap.
    static func shouldEvict(
        sessionID: UUID,
        selectedSessionID: UUID?,
        recentOrder: [UUID],
        maxConnected: Int,
        connectionState: GrokProcessState,
        hasScheduledTasks: Bool
    ) -> Bool {
        if sessionID == selectedSessionID { return false }
        if Set(recentOrder.prefix(maxConnected)).contains(sessionID) { return false }
        if hasScheduledTasks { return false }
        switch connectionState {
        case .idle, .busy:
            return false
        case .starting, .ready, .failed:
            return true
        }
    }
}

/// Naming helpers for a named parallel session (title → worktree branch/path).
enum ParallelSessionNaming {
    static func slug(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        var slug = ""
        slug.reserveCapacity(trimmed.count)
        var lastWasDash = false
        for character in trimmed {
            if character.isLetter || character.isNumber {
                slug.append(character)
                lastWasDash = false
            } else if !lastWasDash {
                slug.append("-")
                lastWasDash = true
            }
        }
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func defaultBranch(fromName name: String) -> String {
        let value = slug(name)
        return value.isEmpty ? "session" : value
    }

    static func defaultWorktreePath(projectPath: URL, name: String) -> String {
        let leaf = slug(name)
        let folder = leaf.isEmpty
            ? "\(projectPath.lastPathComponent)-session"
            : "\(projectPath.lastPathComponent)-\(leaf)"
        return projectPath.deletingLastPathComponent().appendingPathComponent(folder).path
    }

    static func isValidName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isValidWorktree(branch: String, path: String) -> Bool {
        !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isValidAutomation(interval: String, prompt: String) -> Bool {
        !interval.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Display-only title cleanup for the session dashboard (does not rewrite stored titles).
enum DashboardTitle {
    static let untitled = "Untitled session"
    static let maxCharacters = 48

    static func display(_ raw: String) -> String {
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !collapsed.isEmpty else { return untitled }
        if isPromptDump(collapsed) { return untitled }
        if collapsed.count <= maxCharacters { return collapsed }
        let limit = collapsed.index(collapsed.startIndex, offsetBy: maxCharacters)
        if let space = collapsed[..<limit].lastIndex(of: " ") {
            return String(collapsed[..<space]) + "…"
        }
        return String(collapsed[..<limit]) + "…"
    }

    static func compactRole(_ roleName: String) -> String {
        let trimmed = roleName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("Default") { return "Default" }
        return trimmed
    }

    /// Injected Cursor/grok context banners, not a real user prompt. Shared with `SessionTitle.auto`.
    /// Does not treat ordinary text that merely starts with `<` (`<html>`, `<3`) as a dump.
    static func isPromptDump(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasPrefix("<user_info") || lower.hasPrefix("user_info") { return true }
        if lower.contains("os version:") && lower.contains("workspace path") { return true }
        return false
    }
}

extension String {
    /// Nil when empty or whitespace-only; otherwise the trimmed value.
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
