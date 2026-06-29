import SwiftUI
import AppKit

struct ContentView: View {
    private struct LiveSession: Identifiable {
        let id: UUID
        let store: ChatStore
        var workspace: Workspace
        var title: String
        /// The grok session id to resume, known even before the process is started (lazy
        /// restore). Stays valid across LRU teardown so the session can be re-resumed on reopen.
        var grokSessionID: String?
    }

    /// Most-recently-used session ids (front = most recent). Drives the LRU cap on live
    /// `grok agent stdio` processes so steady-state memory doesn't scale with session count.
    @State private var recentSessionOrder: [UUID] = []
    /// Maximum number of sessions kept connected (with a live grok process) at once. Others
    /// are torn down and re-resumed on demand when reopened.
    private let maxConnectedSessions = 4

    @State private var workspaceStore = WorkspaceStore()
    @State private var placeholderStore = ChatStore()
    @State private var liveSessions: [LiveSession] = []
    @State private var selectedSessionID: UUID?
    @State private var selectedWorkspaceID: Workspace.ID?

    @State private var showPicker = false
    @State private var showSettings = false
    @State private var selectedSettingsTab: SettingsTab = .hooks
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
    @State private var isUpgradeBannerDismissed = false
    @State private var showUpgradeBanner = false
    @State private var bannerAppVersion: String?
    @State private var bannerCLIVersion: String?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
            if showUpgradeBanner {
                UpdatesBanner(
                    appVersion: bannerAppVersion,
                    cliVersion: bannerCLIVersion,
                    onAction: {
                        Task {
                            await UpdateUI.presentUpdatePanel(refresh: false) {
                                refreshUpgradeBannerState()
                            }
                        }
                    },
                    onDismiss: {
                        isUpgradeBannerDismissed = true
                        refreshUpgradeBannerState()
                    }
                )
            }

            HSplitView {
            SidebarView(
                workspaces: $workspaceStore.workspaces,
                orderedWorkspaces: workspaceStore.orderedWorkspaces,
                pinnedWorkspaceIDs: workspaceStore.pinnedWorkspaceIDs,
                selectedWorkspaceID: $selectedWorkspaceID,
                sessions: sidebarSessions,
                hiddenSessionCounts: hiddenSessionCounts,
                selectedSessionID: selectedSessionID,
                expandedSessionWorkspaceIDs: $sessionLayout.expandedSessionWorkspaceIDs,
                hiddenSessionWorkspaceIDs: $sessionLayout.hiddenSessionWorkspaceIDs,
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
                onRemoveWorkspace: { removeWorkspace($0) },
                onMoveSession: { workspaceID, source, destination in
                    moveSessions(for: workspaceID, from: source, to: destination)
                },
                onSwitchBranch: { gitCheckoutRequest = GitCheckoutRequest(project: $0) },
                onCreateWorktree: { gitCheckoutRequest = GitCheckoutRequest(project: $0, focusCreateWorktree: true) },
                onSessionDisclosureChanged: { persistSessionLayout() },
                onOpenSettings: { openSettings(tab: .hooks) },
                isSettingsSelected: showSettings
            )
            .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)

            if showSettings {
                SettingsView(store: activeStore, selectedTab: $selectedSettingsTab) {
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
                        onToggleComputerUse: { toggleComputerUseFromChat() },
                        onOpenBrowserSettings: { openSettings(tab: .browser) },
                        onOpenComputerUseSettings: { openSettings(tab: .computerUse) },
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
            }

            if isRestoringSessions {
                sessionRestoreOverlay
            }
        }
        .onAppear(perform: bootstrap)
        .onAppear { refreshUpgradeBannerState() }
        .onReceive(NotificationCenter.default.publisher(for: .grokBuildUpdateAvailable)) { _ in
            isUpgradeBannerDismissed = false
            refreshUpgradeBannerState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .grokBuildUpdateStateChanged)) { _ in
            refreshUpgradeBannerState()
        }
        .sheet(isPresented: $showPicker) {
            WorkspacePicker(initialDirectory: currentWorkspace?.path) { url in
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
        .onReceive(NotificationCenter.default.publisher(for: .workspaceAgentSettingsChanged)) { note in
            guard let workspaceID = note.userInfo?["workspaceID"] as? UUID else { return }
            for session in liveSessions where session.workspace.id == workspaceID {
                session.store.syncWorkspaceAgentSettingsFromStorage()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .grokBuildPrepareForShutdown)) { _ in
            Task {
                for session in liveSessions {
                    await session.store.shutdown()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .grokBuildRestartSessionsRequested)) { _ in
            Task {
                for session in liveSessions {
                    await session.store.retryConnection()
                }
                NotificationCenter.default.post(name: .grokStatusChanged, object: nil)
            }
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

    private func openSettings(tab: SettingsTab) {
        selectedSettingsTab = tab
        showSettings = true
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

    private func toggleComputerUseFromChat() {
        let settings = ComputerUseSettingsStore.load()
        Task {
            let result = await ComputerUseService.applyEnabled(!settings.enabled) {
                await activeStore.reloadConfiguration()
            }
            if case .needsSetup = result {
                showSettings = true
            }
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
        // A lazily-restored session has no loaded messages and no *live* process id yet, but it
        // carries the saved grok id — it is NOT empty and must survive purges/persistence.
        !session.store.hasUserMessages
            && session.store.grokSessionId == nil
            && session.grokSessionID == nil
    }

    private func purgeEmptySessions(in workspaceID: Workspace.ID? = nil, keeping id: UUID? = nil) {
        let staleIDs = liveSessions
            .filter { session in
                session.id != id
                    && isSessionEmpty(session)
                    && (workspaceID == nil || session.workspace.id == workspaceID)
            }
            .map(\.id)
        for staleID in staleIDs {
            closeSession(id: staleID)
        }
    }

    private func liveSessions(for workspaceID: Workspace.ID) -> [LiveSession] {
        liveSessions.filter { $0.workspace.id == workspaceID }
    }

    private var hiddenSessionCounts: [Workspace.ID: Int] {
        _ = sessionListRevision
        var counts: [Workspace.ID: Int] = [:]
        for workspace in workspaceStore.workspaces {
            let total = liveSessions(for: workspace.id).count
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
        let eligible = liveSessions(for: workspaceID)
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
            // Prefer the live process id, but fall back to the known/saved id so lazily-restored
            // (not-yet-started) and LRU-evicted sessions are still persisted and resumable.
            let grokSessionID = session.store.grokSessionId ?? session.grokSessionID
            guard session.store.hasUserMessages || grokSessionID != nil else { continue }
            let existing = sessionLayout.records.first { $0.id == session.id }
            records.append(
                SavedSessionRecord(
                    id: session.id,
                    workspaceID: session.workspace.id,
                    grokSessionID: grokSessionID,
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
        let workspaceIDs = Set(workspaceStore.workspaces.map(\.id))
        let expandedSessionWorkspaceIDs = sessionLayout.expandedSessionWorkspaceIDs.intersection(workspaceIDs)
        let hiddenSessionWorkspaceIDs = sessionLayout.hiddenSessionWorkspaceIDs.intersection(workspaceIDs)
        let recordIDs = Set(records.map(\.id))
        for workspace in workspaceStore.workspaces {
            let ids = liveSessions(for: workspace.id).map(\.id)
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
            selectedSessionIDByWorkspace: selectedByWorkspace,
            expandedSessionWorkspaceIDs: expandedSessionWorkspaceIDs,
            hiddenSessionWorkspaceIDs: hiddenSessionWorkspaceIDs
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
            if workspaceStore.workspaces.isEmpty {
                selectedWorkspaceID = nil
                selectedSessionID = nil
                placeholderStore.clearProject()
            } else if let wsID = saved.selectedWorkspaceID,
                      let workspace = workspaceStore.workspaces.first(where: { $0.id == wsID }) {
                selectProject(workspace)
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

        // Lazy restore: only rebuild lightweight session state here (no grok process spawn).
        // The selected session is started below; the rest resume on demand when first opened.
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
            store.prepare(workspace: workspace)
            liveSessions.append(
                LiveSession(
                    id: record.id,
                    store: store,
                    workspace: workspace,
                    title: title,
                    grokSessionID: record.grokSessionID
                )
            )
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

    private func removeWorkspace(_ workspace: Workspace) {
        for sessionID in liveSessions.filter({ $0.workspace.id == workspace.id }).map(\.id) {
            closeSession(id: sessionID)
        }

        if selectedWorkspaceID == workspace.id {
            selectedWorkspaceID = workspaceStore.orderedWorkspaces
                .first(where: { $0.id != workspace.id })?
                .id
        }

        workspaceStore.remove(workspace)
        if workspaceStore.workspaces.isEmpty {
            selectedWorkspaceID = nil
            selectedSessionID = nil
            placeholderStore.clearProject()
        }
        persistSessionLayout()
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
        guard let session = liveSessions.first(where: { $0.id == id }) else { return }
        purgeEmptySessions(in: session.workspace.id, keeping: id)
        session.store.syncWorkspaceAgentSettingsFromStorage()
        selectedSessionID = id
        selectedWorkspaceID = session.workspace.id
        previewMessageID = nil
        previewDiffs = []
        autoSelectLatestDiffMessage()
        noteSessionUsed(id)
        Task {
            await ensureSessionStarted(id)
            await enforceConnectionCap()
            await refreshProjectChangedFiles()
        }
        persistSessionLayout()
    }

    /// Move a session to the front of the most-recently-used order.
    private func noteSessionUsed(_ id: UUID) {
        recentSessionOrder.removeAll { $0 == id }
        recentSessionOrder.insert(id, at: 0)
    }

    /// Lazily start (resume) a session's grok process the first time it's opened. Sessions
    /// restored at launch are only `prepare`d; this brings one online on demand.
    private func ensureSessionStarted(_ id: UUID) async {
        guard let idx = liveSessions.firstIndex(where: { $0.id == id }) else { return }
        let session = liveSessions[idx]
        // Already connected (starting/ready/busy) — nothing to do.
        guard session.store.connectionState == .idle else { return }
        // No saved grok session → leave prepared; sending the first message starts a fresh one.
        guard let grokID = session.grokSessionID else { return }
        let info = GrokSessionInfo(
            id: grokID,
            created: "",
            updated: "",
            status: "",
            summary: session.title == SessionTitle.defaultTitle ? "" : session.title
        )
        await session.store.start(workspace: session.workspace, resumeSession: info)
        persistSessionLayout()
    }

    /// Tear down grok processes for sessions beyond the MRU cap so the resident footprint
    /// stays bounded. The selected/most-recent sessions and any actively-working session are kept.
    private func enforceConnectionCap() async {
        let keep = Set(recentSessionOrder.prefix(maxConnectedSessions))
        for index in liveSessions.indices {
            let session = liveSessions[index]
            if keep.contains(session.id) || session.id == selectedSessionID { continue }
            // Skip sessions with no live process, and never interrupt one mid-turn.
            guard session.store.connectionState != .idle,
                  session.store.connectionState != .busy else { continue }
            // Preserve the grok id so the session can be re-resumed when reopened.
            liveSessions[index].grokSessionID = session.store.grokSessionId ?? session.grokSessionID
            await session.store.shutdown()
        }
    }

    private func startNewSessionForCurrentProject() {
        guard let workspace = currentWorkspace else { return }
        Task { await createLiveSession(for: workspace) }
    }

    @discardableResult
    private func createLiveSession(for workspace: Workspace, resumeSession: GrokSessionInfo? = nil) async -> UUID {
        purgeEmptySessions(in: workspace.id)
        let id = UUID()
        let store = ChatStore()
        let title = resumeSession.flatMap { session in
            SessionNameStore.name(for: session.id)
                ?? (session.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : session.summary)
        } ?? SessionTitle.defaultTitle
        liveSessions.append(
            LiveSession(id: id, store: store, workspace: workspace, title: title, grokSessionID: resumeSession?.id)
        )
        selectedSessionID = id
        selectedWorkspaceID = workspace.id
        previewMessageID = nil
        previewDiffs = []
        noteSessionUsed(id)
        Task { await refreshProjectChangedFiles() }
        sessionListRevision &+= 1
        persistSessionLayout()
        if let resumeSession {
            await store.start(workspace: workspace, resumeSession: resumeSession)
        } else {
            store.prepare(workspace: workspace)
        }
        await enforceConnectionCap()
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

    private func refreshUpgradeBannerState() {
        guard !isUpgradeBannerDismissed else {
            showUpgradeBanner = false
            bannerAppVersion = nil
            bannerCLIVersion = nil
            return
        }

        let appAvailable = UpdateScheduler.hasActionableAppUpdate
        let cliAvailable = UpdateScheduler.hasActionableCLIUpdate

        guard appAvailable || cliAvailable else {
            showUpgradeBanner = false
            bannerAppVersion = nil
            bannerCLIVersion = nil
            return
        }

        bannerAppVersion = appAvailable ? UpdateScheduler.cachedAppRelease?.latestVersion : nil
        bannerCLIVersion = cliAvailable ? UpdateScheduler.cachedCLIStatus?.latestVersion : nil
        showUpgradeBanner = true
    }
}

private struct UpdatesBanner: View {
    let appVersion: String?
    let cliVersion: String?
    let onAction: () -> Void
    let onDismiss: () -> Void

    private var subtitle: String {
        switch (appVersion, cliVersion) {
        case let (app?, nil):
            return "GrokBuild \(app) is ready to download and install."
        case let (nil, cli?):
            return "grok CLI \(cli) is ready to update."
        case let (app?, cli?):
            return "GrokBuild \(app) and grok CLI \(cli) have updates ready."
        default:
            return "Review available updates."
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title3)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Button(action: onAction) {
                    Text("Updates Available")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss until next launch")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
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
    static let workspaceAgentSettingsChanged = Notification.Name("workspaceAgentSettingsChanged")
    static let grokBuildUpdateAvailable = Notification.Name("grokBuildUpdateAvailable")
    static let grokBuildUpdateStateChanged = Notification.Name("grokBuildUpdateStateChanged")
    static let grokBuildUpdaterPhaseChanged = Notification.Name("grokBuildUpdaterPhaseChanged")
    static let grokBuildCLIUpdaterPhaseChanged = Notification.Name("grokBuildCLIUpdaterPhaseChanged")
    static let grokBuildCLIUpdated = Notification.Name("grokBuildCLIUpdated")
    static let grokBuildRestartSessionsRequested = Notification.Name("grokBuildRestartSessionsRequested")
    static let grokBuildPrepareForShutdown = Notification.Name("grokBuildPrepareForShutdown")
}
