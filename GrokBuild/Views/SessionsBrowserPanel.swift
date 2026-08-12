import SwiftUI

struct ProjectSessionsGroup: Identifiable {
    let workspace: Workspace
    let sessions: [GrokSessionInfo]

    var id: Workspace.ID { workspace.id }
}

struct SessionsBrowserPanel: View {
    @AppStorage(GrokSettingsKeys.privacyMode) private var privacyMode = false
    let workspaces: [Workspace]
    var highlightedWorkspaceID: Workspace.ID?
    let liveSessionsByGrokID: [String: UUID]
    let selectedGrokSessionID: String?
    var showsHeader: Bool = true
    var onResumeSession: (GrokSessionInfo, Workspace) -> Void
    var onSelectLive: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    private let service = GrokCLIService()

    @State private var groups: [ProjectSessionsGroup] = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var isMutating = false
    @State private var pendingDeletion: SessionDeletion?
    @State private var showClearEmptyConfirm = false

    /// A session queued for confirmed, permanent deletion (bound to `.alert(item:)`).
    private struct SessionDeletion: Identifiable {
        let session: GrokSessionInfo
        let workspace: Workspace
        var id: String { session.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HStack(alignment: .center, spacing: 12) {
                    WindowTrafficLights(onClose: { dismiss() })
                        .keyboardShortcut(.cancelAction)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sessions")
                            .font(.title2.weight(.semibold))
                        Text(headerSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)
                }
                .padding()

                Divider()
            }

            HStack {
                TextField("Search sessions", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await loadSessions() }
                    }
                    .onChange(of: query) { _, newValue in
                        searchTask?.cancel()
                        searchTask = Task {
                            try? await Task.sleep(for: .milliseconds(250))
                            guard !Task.isCancelled else { return }
                            await loadSessions()
                        }
                    }
                Button("Search") {
                    Task { await loadSessions() }
                }
                Button("Recent") {
                    query = ""
                    Task { await loadSessions() }
                }
                if cleanableCount > 0 {
                    Button(role: .destructive) {
                        showClearEmptyConfirm = true
                    } label: {
                        Label("Clear Empty (\(cleanableCount))", systemImage: "trash")
                    }
                    .help("Delete unnamed sessions with no summary that are not open or active")
                    .disabled(isMutating)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, showsHeader ? 12 : 8)

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        projectHeader(group.workspace)

                        ForEach(group.sessions) { session in
                            sessionRow(session, workspace: group.workspace)
                        }
                    }

                    if groups.isEmpty && !isLoading {
                        ContentUnavailableView(
                            "No Sessions",
                            systemImage: "clock.arrow.circlepath",
                            description: Text(emptyDescription)
                        )
                        .padding(.vertical, 24)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding()
            }
        }
        .task { await loadSessions() }
        .alert(item: $pendingDeletion) { deletion in
            Alert(
                title: Text("Delete Session?"),
                message: Text("“\(displayName(for: deletion.session))” will be permanently removed from Grok history. This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    Task { await deleteSession(deletion.session, workspace: deletion.workspace) }
                },
                secondaryButton: .cancel()
            )
        }
        .confirmationDialog(
            "Delete \(cleanableCount) empty \(cleanableCount == 1 ? "session" : "sessions")?",
            isPresented: $showClearEmptyConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete \(cleanableCount) \(cleanableCount == 1 ? "Session" : "Sessions")", role: .destructive) {
                Task { await clearEmptySessions() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unnamed sessions with no summary that are not open or active will be permanently removed from Grok history.")
        }
    }

    /// A session is "empty" (safe to bulk-clear) when it has no custom name, no summary,
    /// and is neither the active session nor open as a live tab.
    private func isCleanable(_ session: GrokSessionInfo) -> Bool {
        Self.isCleanableSession(
            summary: session.summary,
            hasCustomName: SessionNameStore.name(for: session.id) != nil,
            isActive: selectedGrokSessionID == session.id,
            isLive: liveSessionsByGrokID[session.id] != nil
        )
    }

    /// Pure predicate for the bulk "Clear Empty" action. A session is cleanable only when
    /// it carries no user-facing identity (no custom name, no summary) and is not in use.
    static func isCleanableSession(summary: String, hasCustomName: Bool, isActive: Bool, isLive: Bool) -> Bool {
        let hasSummary = !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !hasCustomName && !hasSummary && !isActive && !isLive
    }

    private var cleanableCount: Int {
        groups.reduce(0) { $0 + $1.sessions.filter(isCleanable).count }
    }

    private var emptyDescription: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No recent sessions for this project."
            : "No sessions matched your search."
    }

    private var headerSubtitle: String {
        if let workspace = workspaces.first, workspaces.count == 1 {
            return workspace.path.path
        }
        if workspaces.isEmpty {
            return "Select a project to list matching sessions."
        }
        return "Selected projects"
    }

    private func projectHeader(_ workspace: Workspace) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(PrivacyMode.redactLabel(workspace.displayName, placeholder: "Project", enabled: privacyMode))
                .font(.caption.weight(.semibold))
                .foregroundStyle(highlightedWorkspaceID == workspace.id ? .primary : .secondary)
            Text(PrivacyMode.redactPath(workspace.path.path, enabled: privacyMode))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func sessionRow(_ session: GrokSessionInfo, workspace: Workspace) -> some View {
        let isActive = selectedGrokSessionID == session.id
        let isOpenLive = liveSessionsByGrokID[session.id] != nil

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(PrivacyMode.redactLabel(displayName(for: session), placeholder: "Session", enabled: privacyMode))
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Active session")
                }
                Button("Resume") {
                    if let liveID = liveSessionsByGrokID[session.id] {
                        onSelectLive(liveID)
                    } else {
                        onResumeSession(session, workspace)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isOpenLive && isActive)

                Button(role: .destructive) {
                    pendingDeletion = SessionDeletion(session: session, workspace: workspace)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(isMutating || isOpenLive || isActive)
                .help(isOpenLive ? "Close this session before deleting it" : isActive ? "Switch away from this session before deleting it" : "Delete this session permanently")
            }

            HStack(spacing: 10) {
                Text(session.id)
                    .font(.caption.monospaced())
                Text(session.status)
                    .font(.caption)
                Text("Created \(session.created)")
                    .font(.caption)
                Text("Updated \(session.updated)")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func displayName(for session: GrokSessionInfo) -> String {
        SessionNameStore.name(for: session.id)
            ?? (session.summary.isEmpty ? "(no summary)" : session.summary)
    }

    @MainActor
    private func loadSessions() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var seenSessionIDs = Set<String>()
        var loaded: [ProjectSessionsGroup] = []

        do {
            if workspaces.isEmpty {
                groups = []
                return
            } else {
                for workspace in workspaces {
                    let sessions: [GrokSessionInfo]
                    if trimmedQuery.isEmpty {
                        sessions = try await service.listSessions(limit: 50, cwd: workspace.path)
                    } else {
                        sessions = try await service.searchSessions(query: trimmedQuery, limit: 50, cwd: workspace.path)
                    }
                    let unique = sessions.filter { seenSessionIDs.insert($0.id).inserted }
                    if !unique.isEmpty {
                        loaded.append(ProjectSessionsGroup(workspace: workspace, sessions: unique))
                    }
                }
            }
            groups = loaded
        } catch {
            errorMessage = error.localizedDescription
            groups = []
        }
    }

    @MainActor
    private func deleteSession(_ session: GrokSessionInfo, workspace: Workspace) async {
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }
        do {
            try await service.deleteSession(id: session.id, cwd: workspace.path)
            SessionNameStore.removeName(for: session.id)
            removeFromGroups(session.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func clearEmptySessions() async {
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }

        // Snapshot the targets first so mutations during iteration stay consistent.
        let targets: [(GrokSessionInfo, Workspace)] = groups.flatMap { group in
            group.sessions.filter(isCleanable).map { ($0, group.workspace) }
        }
        for (session, workspace) in targets {
            do {
                try await service.deleteSession(id: session.id, cwd: workspace.path)
                SessionNameStore.removeName(for: session.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        await loadSessions()
    }

    /// Drops a deleted session from the in-memory groups and prunes now-empty groups,
    /// avoiding a full reload for a single deletion.
    private func removeFromGroups(_ sessionID: String) {
        groups = groups.compactMap { group in
            let remaining = group.sessions.filter { $0.id != sessionID }
            return remaining.isEmpty ? nil : ProjectSessionsGroup(workspace: group.workspace, sessions: remaining)
        }
    }
}
