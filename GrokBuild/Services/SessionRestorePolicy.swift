import Foundation

/// Pure session-selection rules for launch restore and workspace switching.
enum SessionRestorePolicy {
    static func sessionHasPersistedContent(_ sessionID: UUID) -> Bool {
        SessionMessageStore.hasRestorableTranscript(for: sessionID)
    }

    /// Local transcript the UI can show after restart (in-memory or on disk).
    static func sessionHasRestorableTranscript(hasUserMessages: Bool, sessionID: UUID) -> Bool {
        hasUserMessages || SessionMessageStore.hasRestorableTranscript(for: sessionID)
    }

    static func sessionHasContent(
        hasUserMessages: Bool,
        liveGrokSessionID: String?,
        savedGrokSessionID: String?,
        sessionID: UUID
    ) -> Bool {
        hasUserMessages
            || liveGrokSessionID != nil
            || savedGrokSessionID != nil
            || sessionHasPersistedContent(sessionID)
    }

    /// MRU order rebuilt from saved records (most recently accessed first).
    static func recentSessionOrder(from records: [SavedSessionRecord]) -> [UUID] {
        records.sorted { $0.lastAccessed > $1.lastAccessed }.map(\.id)
    }

    /// Pick the best session tab for a workspace using saved layout and live state.
    static func preferredSessionID(
        for workspaceID: UUID,
        saved: SessionLayoutSnapshot,
        liveSessionIDsInWorkspace: [UUID],
        currentSelectedSessionID: UUID?,
        currentSelectedWorkspaceID: UUID?,
        recentSessionOrder: [UUID],
        hasContent: (UUID) -> Bool
    ) -> UUID? {
        guard !liveSessionIDsInWorkspace.isEmpty else { return nil }
        let inWorkspace = Set(liveSessionIDsInWorkspace)

        if let currentSelectedSessionID,
           currentSelectedWorkspaceID == workspaceID,
           inWorkspace.contains(currentSelectedSessionID) {
            return currentSelectedSessionID
        }

        if let savedID = saved.selectedSessionID, inWorkspace.contains(savedID) {
            return savedID
        }

        if let remembered = saved.selectedSessionIDByWorkspace[workspaceID],
           inWorkspace.contains(remembered) {
            return remembered
        }

        for id in recentSessionOrder where inWorkspace.contains(id) {
            return id
        }

        let recordsInWorkspace = saved.records
            .filter { $0.workspaceID == workspaceID && inWorkspace.contains($0.id) }
            .sorted { $0.lastAccessed > $1.lastAccessed }
        if let mostRecent = recordsInWorkspace.first?.id {
            return mostRecent
        }

        if let withContent = liveSessionIDsInWorkspace.first(where: { hasContent($0) }) {
            return withContent
        }

        return liveSessionIDsInWorkspace.last
    }

    /// Session to select after launch restore.
    static func restoreSelectedSessionID(
        saved: SessionLayoutSnapshot,
        workspaceID: UUID,
        liveSessionIDsInWorkspace: [UUID],
        hasTranscript: (UUID) -> Bool,
        hasContent: (UUID) -> Bool,
        preferredSessionID: (UUID) -> UUID?
    ) -> UUID? {
        let liveIDs = Set(liveSessionIDsInWorkspace)
        guard !liveIDs.isEmpty else { return nil }

        if let savedID = saved.selectedSessionID,
           liveIDs.contains(savedID),
           hasTranscript(savedID) {
            return savedID
        }

        let mru = recentSessionOrder(from: saved.records).filter { liveIDs.contains($0) }
        let transcriptCandidates = mru.filter { hasTranscript($0) }
        if let best = transcriptCandidates.max(by: {
            SessionMessageStore.messageCount(for: $0) < SessionMessageStore.messageCount(for: $1)
        }) {
            return best
        }

        if let savedID = saved.selectedSessionID,
           liveIDs.contains(savedID),
           hasContent(savedID) {
            return savedID
        }

        if let preferred = preferredSessionID(workspaceID), liveIDs.contains(preferred) {
            return preferred
        }

        if let withTranscript = liveSessionIDsInWorkspace.first(where: { hasTranscript($0) }) {
            return withTranscript
        }

        return liveSessionIDsInWorkspace.first
    }
}
