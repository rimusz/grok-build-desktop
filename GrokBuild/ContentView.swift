import SwiftUI
import AppKit

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
    @State private var gitCheckoutRequest: GitCheckoutRequest?
    @State private var gitError: String?
    @State private var previewMessageID: UUID?
    @State private var previewDiffs: [ChatStore.DetectedDiff] = []
    @State private var projectChangedDiffs: [ChatStore.DetectedDiff] = []
    @State private var didBootstrap = false
    @State private var isRestoringSessions = false
    @State private var restoredSessionCount = 0
    @State private var totalSessionsToRestore = 0
    @State private var restoreStatusText = "Restoring sessions..."
    @State private var sessionListRevision = 0
    @State private var sessionLayout = SessionLayoutStore.loadSessions()

    var body: some View {
        ZStack {
            HSplitView {
            SidebarView(
                workspaces: $workspaceStore.workspaces,
                orderedWorkspaces: workspaceStore.orderedWorkspaces,
                pinnedWorkspaceIDs: workspaceStore.pinnedWorkspaceIDs,
                selectedWorkspaceID: $selectedWorkspaceID,
                sessions: sidebarSessions,
                hiddenSessionCounts: hiddenSessionCounts,
                selectedSessionID: selectedSessionID,
                onAddWorkspace: { showPicker = true },
                onSelectWorkspace: { ws in
                    showSettings = false
                    selectProject(ws)
                },
                onSelectSession: { selectSession($0) },
                onNewSessionForWorkspace: { workspace in
                    Task { await createLiveSession(for: workspace) }
                },
                onRenameSession: { id, name in
                    renameSession(id: id, to: name)
                },
                onCloseSession: { id in
                    closeSession(id: id)
                },
                onMoveWorkspace: { source, destination in
                    workspaceStore.moveWorkspaces(from: source, to: destination)
                },
                onPinWorkspace: { workspaceStore.pin($0) },
                onUnpinWorkspace: { workspaceStore.unpin($0) },
                onMoveSession: { workspaceID, source, destination in
                    moveSessions(for: workspaceID, from: source, to: destination)
                },
                onSwitchBranch: { gitCheckoutRequest = GitCheckoutRequest(project: $0) },
                onCreateWorktree: { gitCheckoutRequest = GitCheckoutRequest(project: $0, focusCreateWorktree: true) },
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
                        reviewFileCount: activeReviewDiffs.count,
                        isReviewVisible: showPreview,
                        onToggleReview: {
                            if !activeReviewDiffs.isEmpty {
                                showPreview.toggle()
                            }
                        },
                        onSelectSession: { selectSession($0) },
                        onBrowseSessions: { showSessions = true },
                        onNewSession: { startNewSessionForCurrentProject() },
                        onOpenProjectIn: { openCurrentProject(in: $0) },
                        onToggleBrowserTools: { toggleBrowserToolsFromChat() },
                        onSelectBrowserRuntime: { selectBrowserRuntimeFromChat($0) },
                        onSwitchBranch: {
                            if let workspace = currentWorkspace {
                                gitCheckoutRequest = GitCheckoutRequest(project: workspace)
                            }
                        }
                    )
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)

                    if showPreview {
                        PreviewPane(
                            message: activeReviewMessage,
                            diffs: activeReviewDiffs,
                            workspace: currentWorkspace,
                            onClose: { showPreview = false },
                            onApply: applyDiffs,
                            onApplySingle: applySingle
                        )
                        .frame(minWidth: 360, idealWidth: 460, maxWidth: 620, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            }
            .disabled(isRestoringSessions)

            if isRestoringSessions {
                sessionRestoreOverlay
            }
        }
        .onAppear(perform: bootstrap)
        .sheet(isPresented: $showPicker) {
            WorkspacePicker { url in
                addWorkspace(url: url)
            }
        }
        .sheet(isPresented: $showSessions) {
            SessionBrowserView(
                workspaces: currentWorkspace.map { [$0] } ?? [],
                highlightedWorkspaceID: selectedWorkspaceID,
                liveSessionsByGrokID: liveSessionsByGrokID,
                selectedGrokSessionID: activeStore.grokSessionId,
                onResume: { showSessions = false },
                onResumeSession: { session, workspace in
                    Task { await createLiveSession(for: workspace, resumeSession: session) }
                },
                onSelectLive: { selectSession($0) }
            )
        }
        .sheet(item: $gitCheckoutRequest) { request in
            GitCheckoutSheet(
                project: request.project,
                focusCreateWorktree: request.focusCreateWorktree,
                onSwitchBranch: { branch in
                    Task { await switchBranch(project: request.project, branch: branch) }
                },
                onOpenWorktree: { worktree in
                    Task { await openWorktree(worktree, from: request.project) }
                },
                onCreateBranch: { branch in
                    Task { await createAndSwitchBranch(project: request.project, branch: branch) }
                },
                onCreateWorktree: { branch, path in
                    Task { await createWorktree(project: request.project, branch: branch, path: path) }
                }
            )
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
        .onChange(of: activeStore.grokSessionId) { _, _ in
            persistSessionLayout()
        }
        .onReceive(NotificationCenter.default.publisher(for: .liveSessionMessagesChanged)) { _ in
            sessionListRevision &+= 1
            persistSessionLayout()
        }
    }

    // MARK: - Subviews

    private var sessionRestoreOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)

            VStack(spacing: 5) {
                Text("Restoring Sessions")
                    .font(.headline)
                Text(restoreStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if totalSessionsToRestore > 0 {
                ProgressView(value: Double(restoredSessionCount), total: Double(totalSessionsToRestore))
                    .frame(width: 220)
                Text("\(restoredSessionCount) of \(totalSessionsToRestore)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
    }

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

    private var activeReviewDiffs: [ChatStore.DetectedDiff] {
        previewDiffs.isEmpty ? projectChangedDiffs : previewDiffs
    }

    private var activeReviewMessage: Message? {
        previewDiffs.isEmpty ? nil : previewMessage
    }

    private func toggleBrowserToolsFromChat() {
        var settings = BrowserSettingsStore.load()
        guard AgentBrowserService.browserToolsConfigurationIssue(settings: settings) == nil else {
            showSettings = true
            return
        }

        settings.enabled.toggle()
        BrowserSettingsStore.save(settings)
        BrowserSettingsStore.saveApplied(settings)

        Task {
            await activeStore.reloadConfiguration()
        }
    }

    private func selectBrowserRuntimeFromChat(_ runtimeMode: BrowserRuntimeMode) {
        var settings = BrowserSettingsStore.load()
        guard AgentBrowserService.browserRuntimeConfigurationIssue(settings: settings, mode: runtimeMode) == nil else {
            return
        }
        guard settings.runtimeMode != runtimeMode else { return }

        settings.runtimeMode = runtimeMode
        BrowserSettingsStore.save(settings)
        BrowserSettingsStore.saveApplied(settings)

        guard settings.enabled else { return }
        Task {
            await activeStore.reloadConfiguration()
        }
    }

    private var previewMessage: Message? {
        guard let id = previewMessageID else { return nil }
        return activeStore.messages.first { $0.id == id }
    }

    private var liveSessionsByGrokID: [String: UUID] {
        Dictionary(
            uniqueKeysWithValues: liveSessions.compactMap { session in
                guard let grokID = session.store.grokSessionId else { return nil }
                return (grokID, session.id)
            }
        )
    }

    private func sessionTitle(for session: LiveSession) -> String {
        let liveKey = session.id.uuidString
        if let custom = SessionNameStore.name(for: liveKey) {
            return custom
        }
        if let grokId = session.store.grokSessionId,
           let custom = SessionNameStore.name(for: grokId) {
            return custom
        }
        if let auto = SessionTitle.auto(from: session.store.messages) {
            return auto
        }
        if let saved = sessionLayout.records.first(where: { $0.id == session.id })?.title,
           !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return saved
        }
        return session.title
    }

    private func renameSession(id: UUID, to name: String) {
        SessionNameStore.setName(name, for: id.uuidString)
        if let grokId = liveSessions.first(where: { $0.id == id })?.store.grokSessionId {
            SessionNameStore.setName(name, for: grokId)
        }
        sessionListRevision &+= 1
        persistSessionLayout()
    }

    private func closeSession(id: UUID) {
        guard let index = liveSessions.firstIndex(where: { $0.id == id }) else { return }
        let closing = liveSessions[index]
        let store = closing.store
        liveSessions.remove(at: index)

        if selectedSessionID == id {
            if let sibling = liveSessions.last(where: { $0.workspace.id == closing.workspace.id }) {
                selectSession(sibling.id)
            } else if let any = liveSessions.last {
                selectSession(any.id)
            } else {
                selectedSessionID = nil
            }
        }
        sessionListRevision &+= 1
        persistSessionLayout()
        Task {
            await store.shutdown()
        }
    }

    private func isSessionEmpty(_ session: LiveSession) -> Bool {
        !session.store.hasUserMessages && session.store.grokSessionId == nil
    }

    private func purgeEmptySessions(keeping id: UUID? = nil) {
        let staleIDs = liveSessions
            .filter { $0.id != id && isSessionEmpty($0) }
            .map(\.id)
        for staleID in staleIDs {
            closeSession(id: staleID)
        }
    }

    private var hiddenSessionCounts: [Workspace.ID: Int] {
        _ = sessionListRevision
        var counts: [Workspace.ID: Int] = [:]
        for workspace in workspaceStore.workspaces {
            let total = liveSessions.filter {
                $0.workspace.id == workspace.id && ($0.id == selectedSessionID || !isSessionEmpty($0))
            }.count
            counts[workspace.id] = max(0, total - SessionLayoutStore.maxSidebarSessions)
        }
        return counts
    }

    private var sidebarSessions: [SidebarSession] {
        _ = sessionListRevision
        var result: [SidebarSession] = []
        for workspace in workspaceStore.workspaces {
            let visibleIDs = visibleSessionIDs(for: workspace.id)
            for session in liveSessions where visibleIDs.contains(session.id) {
                guard session.id == selectedSessionID || !isSessionEmpty(session) else { continue }
                result.append(
                    SidebarSession(
                        id: session.id,
                        workspaceID: session.workspace.id,
                        title: sessionTitle(for: session),
                        isRunning: session.store.connectionState == .busy
                            || session.store.connectionState == .starting
                            || session.store.isStreaming
                    )
                )
            }
        }
        return result
    }

    private func visibleSessionIDs(for workspaceID: Workspace.ID) -> [UUID] {
        let eligible = liveSessions.filter {
            $0.workspace.id == workspaceID && ($0.id == selectedSessionID || !isSessionEmpty($0))
        }
        var order = sessionLayout.sessionOrderByWorkspace[workspaceID] ?? eligible.map(\.id)
        order.removeAll { id in !eligible.contains { $0.id == id } }
        for session in eligible where !order.contains(session.id) {
            order.append(session.id)
        }
        if order.count > SessionLayoutStore.maxSidebarSessions {
            let selected = selectedSessionID
            var trimmed = Array(order.prefix(SessionLayoutStore.maxSidebarSessions))
            if let selected, eligible.contains(where: { $0.id == selected }), !trimmed.contains(selected) {
                trimmed[SessionLayoutStore.maxSidebarSessions - 1] = selected
            }
            order = trimmed
        }
        return order
    }

    private func moveSessions(for workspaceID: UUID, from source: IndexSet, to destination: Int) {
        let order = visibleSessionIDs(for: workspaceID)
        let allForWorkspace = liveSessions.filter { $0.workspace.id == workspaceID }.map(\.id)
        var fullOrder = sessionLayout.sessionOrderByWorkspace[workspaceID] ?? allForWorkspace
        fullOrder.removeAll { id in !allForWorkspace.contains(id) }
        for id in allForWorkspace where !fullOrder.contains(id) {
            fullOrder.append(id)
        }

        let visible = order
        var movedVisible = visible
        movedVisible.move(fromOffsets: source, toOffset: destination)

        var newFull = fullOrder
        let visibleSet = Set(visible)
        var visibleIndex = 0
        for idx in newFull.indices {
            if visibleSet.contains(newFull[idx]) {
                newFull[idx] = movedVisible[visibleIndex]
                visibleIndex += 1
            }
        }

        sessionLayout.sessionOrderByWorkspace[workspaceID] = newFull
        persistSessionLayout()
        sessionListRevision &+= 1
    }

    private func persistSessionLayout() {
        var records: [SavedSessionRecord] = []
        for session in liveSessions {
            guard session.store.hasUserMessages || session.store.grokSessionId != nil else { continue }
            let existing = sessionLayout.records.first { $0.id == session.id }
            records.append(
                SavedSessionRecord(
                    id: session.id,
                    workspaceID: session.workspace.id,
                    grokSessionID: session.store.grokSessionId,
                    title: sessionTitle(for: session),
                    lastAccessed: existing?.lastAccessed ?? Date()
                )
            )
        }

        if let selectedSessionID,
           let idx = records.firstIndex(where: { $0.id == selectedSessionID }) {
            records[idx].lastAccessed = Date()
        }

        var order = sessionLayout.sessionOrderByWorkspace
        var selectedByWorkspace = sessionLayout.selectedSessionIDByWorkspace
        let recordIDs = Set(records.map(\.id))
        for workspace in workspaceStore.workspaces {
            let ids = liveSessions
                .filter { $0.workspace.id == workspace.id && ($0.id == selectedSessionID || !isSessionEmpty($0)) }
                .map(\.id)
            var workspaceOrder = order[workspace.id] ?? ids
            workspaceOrder.removeAll { id in !ids.contains(id) }
            for id in ids where !workspaceOrder.contains(id) {
                workspaceOrder.append(id)
            }
            order[workspace.id] = workspaceOrder
            if let selectedByWorkspaceID = selectedByWorkspace[workspace.id],
               !ids.contains(selectedByWorkspaceID) {
                selectedByWorkspace[workspace.id] = nil
            }
        }

        if let selectedSessionID,
           let selectedSession = liveSessions.first(where: { $0.id == selectedSessionID }),
           recordIDs.contains(selectedSessionID) {
            selectedByWorkspace[selectedSession.workspace.id] = selectedSessionID
        }

        sessionLayout = SessionLayoutSnapshot(
            records: records,
            sessionOrderByWorkspace: order,
            selectedSessionID: selectedSessionID,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedSessionIDByWorkspace: selectedByWorkspace
        )
        SessionLayoutStore.saveSessions(sessionLayout)
    }

    // MARK: - Logic

    private func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        Task { await restorePersistedSessions() }
    }

    private func restorePersistedSessions() async {
        let saved = sessionLayout
        guard !saved.records.isEmpty else {
            if let first = workspaceStore.orderedWorkspaces.first {
                await createLiveSession(for: first)
            }
            return
        }

        let restorableRecords = saved.records.filter { record in
            workspaceStore.workspaces.contains { $0.id == record.workspaceID }
        }
        guard !restorableRecords.isEmpty else { return }

        totalSessionsToRestore = restorableRecords.count
        restoredSessionCount = 0
        restoreStatusText = "Preparing saved sessions..."
        isRestoringSessions = true
        defer {
            isRestoringSessions = false
            restoreStatusText = "Restoring sessions..."
        }

        var titleCacheByWorkspace: [Workspace.ID: [String: String]] = [:]
        let cli = GrokCLIService()
        var shouldStartGrokProcesses = true

        for record in restorableRecords {
            guard let workspace = workspaceStore.workspaces.first(where: { $0.id == record.workspaceID }) else { continue }
            guard liveSessions.first(where: { $0.id == record.id }) == nil else { continue }
            restoreStatusText = "Restoring \(workspace.displayName)"

            let store = ChatStore()
            let title = await restoredTitle(
                for: record,
                workspace: workspace,
                cache: &titleCacheByWorkspace,
                cli: cli
            )
            liveSessions.append(
                LiveSession(id: record.id, store: store, workspace: workspace, title: title)
            )

            if let grokID = record.grokSessionID, shouldStartGrokProcesses {
                let info = GrokSessionInfo(
                    id: grokID,
                    created: "",
                    updated: "",
                    status: "",
                    summary: title == SessionTitle.defaultTitle ? "" : title
                )
                await store.start(workspace: workspace, resumeSession: info)
                persistSessionLayout()
                if store.authRequiredMessage != nil || isAuthenticationFailure(store.connectionState) {
                    shouldStartGrokProcesses = false
                }
            } else {
                store.prepare(workspace: workspace)
            }
            restoredSessionCount += 1
        }

        sessionListRevision &+= 1

        if let selected = saved.selectedSessionID,
           liveSessions.contains(where: { $0.id == selected }) {
            selectSession(selected)
        } else if let wsID = saved.selectedWorkspaceID,
                  let selected = saved.selectedSessionIDByWorkspace[wsID],
                  liveSessions.contains(where: { $0.id == selected }) {
            selectSession(selected)
        } else if let wsID = saved.selectedWorkspaceID,
                  let session = liveSessions.last(where: { $0.workspace.id == wsID }) {
            selectSession(session.id)
        } else if let first = liveSessions.first {
            selectSession(first.id)
        }
    }

    private func isAuthenticationFailure(_ state: GrokProcessState) -> Bool {
        guard case .failed(let message) = state else { return false }
        let lowercased = message.lowercased()
        return lowercased.contains("login") || lowercased.contains("auth")
    }

    private func restoredTitle(
        for record: SavedSessionRecord,
        workspace: Workspace,
        cache: inout [Workspace.ID: [String: String]],
        cli: GrokCLIService
    ) async -> String {
        if let title = record.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }

        guard let grokID = record.grokSessionID else {
            return SessionTitle.defaultTitle
        }

        if cache[workspace.id] == nil {
            let sessions = (try? await cli.listSessions(limit: 50, cwd: workspace.path)) ?? []
            cache[workspace.id] = Dictionary(
                uniqueKeysWithValues: sessions.map { ($0.id, $0.summary) }
            )
        }

        if let summary = cache[workspace.id]?[grokID]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            return summary
        }

        return "Session \(grokID.prefix(8))"
    }

    private func addWorkspace(url: URL) {
        let ws = Workspace(name: url.lastPathComponent, path: url)
        workspaceStore.add(ws)
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

    @MainActor
    private func refreshProjectChangedFiles() async {
        guard let workspace = currentWorkspace else {
            projectChangedDiffs = []
            return
        }

        do {
            let files = try await GitService.changedFiles(in: workspace.path)
            var diffs: [ChatStore.DetectedDiff] = []
            for file in files {
                let diff = try await GitService.diffForChangedFile(file, in: workspace.path)
                diffs.append(ChatStore.DetectedDiff(raw: diff, filePath: file.path))
            }
            guard currentWorkspace?.id == workspace.id else { return }
            projectChangedDiffs = diffs
            if diffs.isEmpty, previewDiffs.isEmpty {
                showPreview = false
            }
        } catch {
            guard currentWorkspace?.id == workspace.id else { return }
            projectChangedDiffs = []
        }
    }

    private func applyDiffs(from message: Message) {
        guard let ws = activeStore.currentWorkspace else { return }
        _ = activeStore.applyDiffs(from: message, workspace: ws)
        Task { await refreshProjectChangedFiles() }
    }

    private func applySingle(_ diff: ChatStore.DetectedDiff) {
        guard let ws = activeStore.currentWorkspace else { return }

        // Apply only one diff by temporarily synthesizing a message with just that diff
        let single = Message(role: .assistant, content: "```diff\n\(diff.raw)\n```")
        _ = activeStore.applyDiffs(from: single, workspace: ws)
        Task { await refreshProjectChangedFiles() }
    }

    private func openCurrentProject(in target: ProjectOpenTarget) {
        guard let workspace = currentWorkspace else { return }
        switch target {
        case .finder:
            NSWorkspace.shared.open(workspace.path)
        case .cursor:
            openProject(
                workspace.path,
                bundleIdentifiers: ["com.todesktop.230313mzl4w4u92", "com.cursor.Cursor"],
                appNames: ["Cursor"]
            )
        case .vsCode:
            openProject(
                workspace.path,
                bundleIdentifiers: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"],
                appNames: ["Visual Studio Code", "Visual Studio Code - Insiders"]
            )
        case .terminal:
            openProject(
                workspace.path,
                bundleIdentifiers: ["com.apple.Terminal"],
                appNames: ["Terminal"]
            )
        case .iTerm:
            openProject(
                workspace.path,
                bundleIdentifiers: ["com.googlecode.iterm2"],
                appNames: ["iTerm", "iTerm2"]
            )
        case .zed:
            openProject(
                workspace.path,
                bundleIdentifiers: ["dev.zed.Zed", "dev.zed.Zed-Preview", "com.zed.Zed"],
                appNames: ["Zed", "Zed Preview"]
            )
        }
    }

    private func openProject(_ url: URL, bundleIdentifiers: [String], appNames: [String]) {
        guard let appURL = installedApp(bundleIdentifiers: bundleIdentifiers, appNames: appNames) else {
            NSWorkspace.shared.open(url)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
    }

    private func installedApp(bundleIdentifiers: [String], appNames: [String]) -> URL? {
        for bundleIdentifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return url
            }
        }

        for appName in appNames {
            for directory in ["/Applications", "\(NSHomeDirectory())/Applications"] {
                let candidate = URL(fileURLWithPath: directory).appendingPathComponent("\(appName).app")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }

    private func handleWorkspaceChange(_ newID: Workspace.ID?) {
        if let id = newID,
           let ws = workspaceStore.workspaces.first(where: { $0.id == id }) {
            showSettings = false
            if activeSession?.workspace.id == id { return }
            selectProject(ws)
        }
    }

    private func selectProject(_ workspace: Workspace) {
        selectedWorkspaceID = workspace.id
        if let remembered = rememberedSessionID(for: workspace.id) {
            selectSession(remembered)
        } else if let session = liveSessions.last(where: { $0.workspace.id == workspace.id }) {
            selectSession(session.id)
        } else {
            Task { await createLiveSession(for: workspace) }
        }
    }

    private func rememberedSessionID(for workspaceID: Workspace.ID) -> UUID? {
        guard let sessionID = sessionLayout.selectedSessionIDByWorkspace[workspaceID],
              liveSessions.contains(where: { $0.id == sessionID }) else {
            return nil
        }
        return sessionID
    }

    private func selectSession(_ id: UUID) {
        purgeEmptySessions(keeping: id)
        guard let session = liveSessions.first(where: { $0.id == id }) else { return }
        selectedSessionID = id
        selectedWorkspaceID = session.workspace.id
        previewMessageID = nil
        previewDiffs = []
        autoSelectLatestDiffMessage()
        Task { await refreshProjectChangedFiles() }
        persistSessionLayout()
    }

    private func startNewSessionForCurrentProject() {
        guard let workspace = currentWorkspace else { return }
        Task { await createLiveSession(for: workspace) }
    }

    @discardableResult
    private func createLiveSession(for workspace: Workspace, resumeSession: GrokSessionInfo? = nil) async -> UUID {
        purgeEmptySessions()
        let id = UUID()
        let store = ChatStore()
        let title = resumeSession.flatMap { session in
            SessionNameStore.name(for: session.id)
                ?? (session.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : session.summary)
        } ?? SessionTitle.defaultTitle
        liveSessions.append(LiveSession(id: id, store: store, workspace: workspace, title: title))
        selectedSessionID = id
        selectedWorkspaceID = workspace.id
        previewMessageID = nil
        previewDiffs = []
        Task { await refreshProjectChangedFiles() }
        sessionListRevision &+= 1
        persistSessionLayout()
        if let resumeSession {
            await store.start(workspace: workspace, resumeSession: resumeSession)
        } else {
            store.prepare(workspace: workspace)
        }
        return id
    }

    private func switchBranch(project: Workspace, branch: String) async {
        do {
            _ = try await GitService.run(["switch", branch], in: project.path)
            await createLiveSession(for: project)
            gitCheckoutRequest = nil
        } catch {
            gitError = error.localizedDescription
        }
    }

    private func createAndSwitchBranch(project: Workspace, branch: String) async {
        do {
            _ = try await GitService.run(["switch", "-c", branch], in: project.path)
            await createLiveSession(for: project)
            gitCheckoutRequest = nil
        } catch {
            gitError = error.localizedDescription
        }
    }

    private func openWorktree(_ worktree: GitWorktreeInfo, from project: Workspace) async {
        let path = worktree.path.standardizedFileURL
        if path.path == project.path.standardizedFileURL.path {
            if let branch = worktree.branch,
               branch != GitService.currentBranch(in: project.path) {
                await switchBranch(project: project, branch: branch)
            } else {
                gitCheckoutRequest = nil
            }
            return
        }

        if let existing = workspaceStore.workspaces.first(where: {
            $0.path.standardizedFileURL.path == path.path
        }) {
            selectProject(existing)
            await createLiveSession(for: existing)
        } else {
            let workspace = Workspace(name: path.lastPathComponent, path: path)
            workspaceStore.add(workspace)
            await createLiveSession(for: workspace)
        }
        gitCheckoutRequest = nil
    }

    private func createWorktree(project: Workspace, branch: String, path: String) async {
        do {
            let pathURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            _ = try await GitService.run(["worktree", "add", "-b", branch, pathURL.path], in: project.path)
            let workspace = Workspace(name: pathURL.lastPathComponent, path: pathURL)
            workspaceStore.add(workspace)
            await createLiveSession(for: workspace)
            gitCheckoutRequest = nil
        } catch {
            gitError = error.localizedDescription
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
    static let liveSessionMessagesChanged = Notification.Name("liveSessionMessagesChanged")
}
