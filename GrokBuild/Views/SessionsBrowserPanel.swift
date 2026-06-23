import SwiftUI

struct ProjectSessionsGroup: Identifiable {
    let workspace: Workspace
    let sessions: [GrokSessionInfo]

    var id: Workspace.ID { workspace.id }
}

struct SessionsBrowserPanel: View {
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
            Text(workspace.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(highlightedWorkspaceID == workspace.id ? .primary : .secondary)
            Text(workspace.path.path)
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
                Text(displayName(for: session))
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
}
