import SwiftUI

struct ContentView: View {
    private struct LiveSession: Identifiable {
        let id: UUID
        let store: ChatStore
        var workspace: Workspace
        var title: String
    }

    @State private var workspaceStore = WorkspaceStore()
    @State private var placeholderStore = ChatStore()
    @State private var liveSessions: [LiveSession] = []
    @State private var selectedSessionID: UUID?
    @State private var selectedWorkspaceID: Workspace.ID?

    @State private var showPicker = false
    @State private var showSettings = false
    @State private var showSessions = false
    @State private var showPreview = false
    @State private var branchSwitchProject: Workspace?
    @State private var worktreeProject: Workspace?
    @State private var gitError: String?
    @State private var previewMessageID: UUID?
    @State private var previewDiffs: [ChatStore.DetectedDiff] = []

    var body: some View {
        HSplitView {
            SidebarView(
                workspaces: $workspaceStore.workspaces,
                selectedWorkspaceID: $selectedWorkspaceID,
                sessions: sidebarSessions,
                selectedSessionID: selectedSessionID,
                onAddWorkspace: { showPicker = true },
                onSelectWorkspace: { ws in
                    showSettings = false
                    selectProject(ws)
                    workspaceStore.moveToTop(ws)
                },
                onSelectSession: { selectSession($0) },
                onSwitchBranch: { branchSwitchProject = $0 },
                onCreateWorktree: { worktreeProject = $0 },
                onOpenSettings: { showSettings = true },
                isSettingsSelected: showSettings
            )
            .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)

            if showSettings {
                SettingsView(store: activeStore) {
                    showSettings = false
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    ChatView(
                        store: activeStore,
                        isPreviewVisible: $showPreview,
                        hasPreviewContent: !previewDiffs.isEmpty,
                        onNewSession: { startNewSessionForCurrentProject() },
                        onSwitchBranch: { if let project = currentWorkspace { branchSwitchProject = project } }
                    )
                        .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

                    if showPreview {
                        PreviewPane(
                            message: previewMessage,
                            diffs: previewDiffs,
                            workspace: activeStore.currentWorkspace,
                            onApply: { msg in applyDiffs(from: msg) },
                            onApplySingle: { diff in applySingle(diff) }
                        )
                        .frame(minWidth: 320, idealWidth: 380, maxWidth: 520)
                    }
                }
            }
        }
        .onAppear(perform: bootstrap)
        .sheet(isPresented: $showPicker) {
            WorkspacePicker { url in
                addWorkspace(url: url)
            }
        }
        .sheet(isPresented: $showSessions) {
            SessionBrowserView(store: activeStore, workspace: currentWorkspace) {
                showSessions = false
            } onResumeSession: { session in
                if let workspace = currentWorkspace {
                    Task { await createLiveSession(for: workspace, resumeSession: session) }
                }
            }
        }
        .sheet(item: $branchSwitchProject) { project in
            BranchSwitchSheet(project: project) { branch in
                Task { await switchBranch(project: project, branch: branch) }
            }
        }
        .sheet(item: $worktreeProject) { project in
            WorktreeCreateSheet(project: project) { branch, path in
                Task { await createWorktree(project: project, branch: branch, path: path) }
            }
        }
        .alert("Git action failed", isPresented: Binding(
            get: { gitError != nil },
            set: { if !$0 { gitError = nil } }
        )) {
            Button("OK", role: .cancel) { gitError = nil }
        } message: {
            Text(gitError ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .chooseWorkspaceRequested)) { _ in
            showPicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionsRequested)) { _ in
            showSessions = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopGenerationRequested)) { _ in
            activeStore.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusInputRequested)) { _ in
            // handled inside ChatView via focus
        }
        .onChange(of: selectedWorkspaceID) { _, newID in
            handleWorkspaceChange(newID)
        }
        .onChange(of: activeStore.messages) { _, _ in
            autoSelectLatestDiffMessage()
        }
        // Menu bar quick actions
        .onReceive(NotificationCenter.default.publisher(for: .newSessionRequested)) { _ in
            startNewSessionForCurrentProject()
        }
    }

    // MARK: - Subviews

    private var activeSession: LiveSession? {
        guard let selectedSessionID else { return nil }
        return liveSessions.first { $0.id == selectedSessionID }
    }

    private var activeStore: ChatStore {
        activeSession?.store ?? placeholderStore
    }

    private var currentWorkspace: Workspace? {
        activeSession?.workspace ?? selectedWorkspaceID.flatMap { id in
            workspaceStore.workspaces.first(where: { $0.id == id })
        }
    }

    private var previewMessage: Message? {
        guard let id = previewMessageID else { return nil }
        return activeStore.messages.first { $0.id == id }
    }

    private var sidebarSessions: [SidebarSession] {
        liveSessions.map { session in
            SidebarSession(
                id: session.id,
                title: session.title,
                projectName: session.workspace.displayName,
                isRunning: session.store.connectionState == .busy || session.store.connectionState == .starting
            )
        }
    }

    // MARK: - Logic

    private func bootstrap() {
        // Restore or seed projects
        if let first = workspaceStore.workspaces.first {
            selectedWorkspaceID = first.id
            Task { await createLiveSession(for: first) }
        }

    }

    private func addWorkspace(url: URL) {
        let ws = Workspace(name: url.lastPathComponent, path: url)
        workspaceStore.add(ws)
        selectedWorkspaceID = ws.id
        Task {
            await createLiveSession(for: ws)
        }
    }

    private func autoSelectLatestDiffMessage() {
        if let last = activeStore.messages.last(where: { $0.role == .assistant && $0.hasDiff }) {
            if previewMessageID != last.id {
                previewMessageID = last.id
                previewDiffs = activeStore.detectedDiffs(in: last)
                showPreview = true
            }
        }
    }

    private func applyDiffs(from message: Message) {
        guard let ws = activeStore.currentWorkspace else { return }
        _ = activeStore.applyDiffs(from: message, workspace: ws)
    }

    private func applySingle(_ diff: ChatStore.DetectedDiff) {
        guard let ws = activeStore.currentWorkspace else { return }

        // Apply only one diff by temporarily synthesizing a message with just that diff
        let single = Message(role: .assistant, content: "```diff\n\(diff.raw)\n```")
        _ = activeStore.applyDiffs(from: single, workspace: ws)
    }

    private func handleWorkspaceChange(_ newID: Workspace.ID?) {
        if let id = newID,
           let ws = workspaceStore.workspaces.first(where: { $0.id == id }) {
            selectProject(ws)
        }
    }

    private func selectProject(_ workspace: Workspace) {
        selectedWorkspaceID = workspace.id
        if let session = liveSessions.last(where: { $0.workspace.id == workspace.id }) {
            selectSession(session.id)
        } else {
            Task { await createLiveSession(for: workspace) }
        }
    }

    private func selectSession(_ id: UUID) {
        guard let session = liveSessions.first(where: { $0.id == id }) else { return }
        selectedSessionID = id
        selectedWorkspaceID = session.workspace.id
        previewMessageID = nil
        previewDiffs = []
        autoSelectLatestDiffMessage()
    }

    private func startNewSessionForCurrentProject() {
        guard let workspace = currentWorkspace else { return }
        Task { await createLiveSession(for: workspace) }
    }

    @discardableResult
    private func createLiveSession(for workspace: Workspace, resumeSession: GrokSessionInfo? = nil) async -> UUID {
        let id = UUID()
        let store = ChatStore()
        let title = "Session \(liveSessions.filter { $0.workspace.id == workspace.id }.count + 1)"
        liveSessions.append(LiveSession(id: id, store: store, workspace: workspace, title: title))
        selectedSessionID = id
        selectedWorkspaceID = workspace.id
        previewMessageID = nil
        previewDiffs = []
        await store.start(workspace: workspace, resumeSession: resumeSession)
        return id
    }

    private func switchBranch(project: Workspace, branch: String) async {
        do {
            _ = try await runGit(["switch", branch], in: project.path)
            await createLiveSession(for: project)
            branchSwitchProject = nil
        } catch {
            gitError = error.localizedDescription
        }
    }

    private func createWorktree(project: Workspace, branch: String, path: String) async {
        do {
            let pathURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            _ = try await runGit(["worktree", "add", "-b", branch, pathURL.path], in: project.path)
            let workspace = Workspace(name: pathURL.lastPathComponent, path: pathURL)
            workspaceStore.add(workspace)
            await createLiveSession(for: workspace)
            worktreeProject = nil
        } catch {
            gitError = error.localizedDescription
        }
    }

    private func runGit(_ args: [String], in directory: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = directory

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { process in
                let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: out)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "Git",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: err.isEmpty ? out : err]
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private struct BranchSwitchSheet: View {
    let project: Workspace
    var onSwitch: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var branch = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Switch Branch")
                .font(.title2.weight(.semibold))
            Text(project.path.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            TextField("Branch name", text: $branch)
                .textFieldStyle(.roundedBorder)
            Text("This switches the project checkout and starts a fresh session.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Switch") {
                    onSwitch(branch.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct WorktreeCreateSheet: View {
    let project: Workspace
    var onCreate: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var branch = ""
    @State private var path = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Worktree")
                .font(.title2.weight(.semibold))
            Text("Create a new branch in a new worktree and start a fresh session there.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("New branch name", text: $branch)
                .textFieldStyle(.roundedBorder)
            TextField("Worktree path", text: $path)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    onCreate(
                        branch.trimmingCharacters(in: .whitespacesAndNewlines),
                        path.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            if path.isEmpty {
                let sibling = project.path.deletingLastPathComponent()
                path = sibling.appendingPathComponent("\(project.path.lastPathComponent)-worktree").path
            }
        }
    }
}

extension Notification.Name {
    static let chooseWorkspaceRequested = Notification.Name("chooseWorkspaceRequested")
    static let sessionsRequested = Notification.Name("sessionsRequested")
    static let stopGenerationRequested = Notification.Name("stopGenerationRequested")
    static let focusInputRequested = Notification.Name("focusInputRequested")
    static let showMainWindowRequested = Notification.Name("showMainWindowRequested")
    static let newSessionRequested = Notification.Name("newSessionRequested")
    static let grokStatusChanged = Notification.Name("grokStatusChanged")
}
