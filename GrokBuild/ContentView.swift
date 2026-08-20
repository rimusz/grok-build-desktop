import SwiftUI
import AppKit

struct ContentView: View {
    fileprivate struct LiveSession: Identifiable {
        let id: UUID
        let store: ChatStore
        var workspace: Workspace
        var title: String
        /// The grok session id to resume, known even before the process is started (lazy
        /// restore). Stays valid across LRU teardown so the session can be re-resumed on reopen.
        var grokSessionID: String?
        /// Roster identity this tab was started from, if any. Independent of `--agent` / role.
        var specialistAgentID: UUID? = nil
    }

    /// Most-recently-used session ids (front = most recent). Drives the LRU cap on live
    /// `grok agent stdio` processes so steady-state memory doesn't scale with session count.
    @State private var recentSessionOrder: [UUID] = []
    /// Maximum number of sessions kept connected (with a live grok process) at once. Others
    /// are torn down and re-resumed on demand when reopened.
    private let maxConnectedSessions = 4

    @State private var workspaceStore = WorkspaceStore()
    @State private var specialistAgentStore = SpecialistAgentStore()
    @State private var placeholderStore = ChatStore()
    @State private var liveSessions: [LiveSession] = []
    @State private var selectedSessionID: UUID?
    @State private var selectedWorkspaceID: Workspace.ID?

    @State private var showPicker = false
    @State private var showSettings = false
    @State private var selectedSettingsTab: SettingsTab = .agents
    @State private var showSessions = false
    @State private var showSessionDashboard = false
    @State private var showParallelSession = false
    @State private var showNewAutomation = false
    @State private var showAgentEditor = false
    @State private var editingSpecialistAgent: SpecialistAgent?
    @State private var specialistAgentPendingDelete: SpecialistAgent?
    @State private var showNeedProjectForAgent = false
    @State private var specialistAgentError: String?
    @State private var dashboardGitByPath: [String: DashboardGitSnapshot] = [:]
    @State private var showDoctor = false
    /// Session tabs with a finished-but-unseen reply (cleared on focus). Drives the sidebar badge.
    @State private var unreadSessionIDs: Set<UUID> = []
    /// Last message count observed per session (secondary unread signal).
    @State private var lastSeenMessageCounts: [UUID: Int] = [:]
    /// Prior `isStreaming` per session — primary unread signal (true → false while unfocused).
    @State private var lastSeenStreaming: [UUID: Bool] = [:]
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
    @State private var showSidebarUpdateButton = false
    @State private var sidebarUpdateAppVersion: String?
    @State private var sidebarUpdateCLIVersion: String?

    private var gitErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { gitError != nil },
            set: { isPresented in
                if !isPresented { gitError = nil }
            }
        )
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
            if showUpgradeBanner {
                UpdatesBanner(
                    appVersion: bannerAppVersion,
                    cliVersion: bannerCLIVersion,
                    onAction: { openUpdatesPanel() },
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
                pinnedSessionIDs: sessionLayout.pinnedSessionIDs,
                selectedWorkspaceID: $selectedWorkspaceID,
                sessions: sidebarSessions,
                hiddenSessionCounts: hiddenSessionCounts,
                selectedSessionID: selectedSessionID,
                expandedSessionWorkspaceIDs: $sessionLayout.expandedSessionWorkspaceIDs,
                hiddenSessionWorkspaceIDs: $sessionLayout.hiddenSessionWorkspaceIDs,
                settledSessionIDs: $sessionLayout.settledSessionIDs,
                onAddWorkspace: { showPicker = true },
                onSelectWorkspace: { ws in
                    if showSettings,
                       !SettingsPaneNavigation.shouldLeaveSettings(
                           incomingWorkspaceID: ws.id,
                           activeWorkspaceID: selectedWorkspaceID
                       ) {
                        return
                    }
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
                onPinSession: { pinSession($0) },
                onUnpinSession: { unpinSession($0) },
                onSettleSession: { settleSession($0) },
                onUnsettleSession: { unsettleSession($0) },
                onMarkSessionUnread: { unreadSessionIDs.insert($0) },
                onMarkSessionRead: { unreadSessionIDs.remove($0) },
                onDuplicateSession: { id in
                    Task { await duplicateSession(id) }
                },
                onClearSessionTranscript: { clearSessionTranscript(id: $0) },
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
                onOpenSettings: { openSettings(tab: .agents) },
                isSettingsSelected: showSettings,
                hasActionableUpdate: showSidebarUpdateButton,
                updateButtonTitle: SidebarUpdateButtonCopy.title(
                    appVersion: sidebarUpdateAppVersion,
                    cliVersion: sidebarUpdateCLIVersion
                ),
                updateButtonAccessibilityLabel: SidebarUpdateButtonCopy.accessibilityLabel(
                    appVersion: sidebarUpdateAppVersion,
                    cliVersion: sidebarUpdateCLIVersion
                ),
                onOpenUpdates: { openUpdatesPanel() },
                specialistAgents: specialistAgentStore.agents,
                agentWorkingIDs: workingSpecialistAgentIDs,
                selectedSpecialistAgentID: selectedSpecialistAgentID,
                onSelectSpecialistAgent: { agent in
                    showSettings = false
                    activateSpecialistAgent(agent)
                },
                onStartSpecialistAgentSession: { agent in
                    showSettings = false
                    activateSpecialistAgent(agent, forceNew: true)
                },
                onNewSpecialistAgent: { openAgentEditor(nil) },
                onEditSpecialistAgent: { openAgentEditor($0) },
                onDuplicateSpecialistAgent: { duplicateSpecialistAgent($0) },
                onDeleteSpecialistAgent: { specialistAgentPendingDelete = $0 },
                onInstallStarterCrew: { installStarterCrew() },
                openableLastSessionAgentIDs: openableLastSessionAgentIDs,
                onOpenLastSpecialistSession: { agent in
                    showSettings = false
                    openLastSpecialistSession(agent)
                }
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
                        boundSpecialist: activeBoundSpecialist,
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
                        onAddProject: { showPicker = true },
                        onOpenProjectIn: { openCurrentProject(in: $0) },
                        onOpenAgentSettings: { openSettings(tab: .agents) },
                        onOpenWorkflowSettings: { openSettings(tab: .workflows) },
                        onForkSession: { Task { await forkCurrentSession() } },
                        onOpenDashboard: { showSessionDashboard = true }
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
        .sheet(isPresented: $showSessionDashboard) {
            SessionDashboardPanel(
                entries: dashboardEntries,
                projectName: currentWorkspace?.displayName,
                projectPath: currentWorkspace?.path.path,
                onSelect: { sessionID in
                    selectSession(sessionID)
                },
                onOpenPreview: { sessionID in
                    selectSession(sessionID)
                    showPreview = true
                },
                onNewParallelSession: {
                    guard currentWorkspace != nil else { return }
                    showParallelSession = true
                },
                onNewAutomation: {
                    guard currentWorkspace != nil else { return }
                    showNewAutomation = true
                }
            )
            .task {
                await refreshDashboardGit()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    await refreshDashboardGit()
                }
            }
            .sheet(isPresented: $showParallelSession) {
                if let workspace = currentWorkspace {
                    ParallelSessionSheet(
                        project: workspace,
                        isGitRepository: GitService.isRepository(workspace.path)
                    ) { spec in
                        Task { await createNamedSession(spec, in: workspace) }
                    }
                }
            }
            .sheet(isPresented: $showNewAutomation) {
                if let workspace = currentWorkspace {
                    AutomationSheet(
                        project: workspace,
                        isGitRepository: GitService.isRepository(workspace.path)
                    ) { spec in
                        Task { await createAutomation(spec, in: workspace) }
                    }
                }
            }
        }
        .sheet(isPresented: $showDoctor) {
            DoctorSheet()
        }
        .sheet(isPresented: $showAgentEditor) {
            AgentEditorSheet(
                agent: editingSpecialistAgent,
                existingNames: specialistAgentStore.agents.map(\.name),
                customRoleNames: SubagentRoleStore.load().map(\.name)
            ) { draft in
                saveSpecialistAgent(draft)
            }
        }
        .alert("Choose a project", isPresented: $showNeedProjectForAgent) {
            if workspaceStore.workspaces.isEmpty {
                Button("Add Project…") { showPicker = true }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                workspaceStore.workspaces.isEmpty
                    ? "Agents start a session in the current project. Add a project first."
                    : "Select a project in the sidebar, then start the Agent."
            )
        }
        .alert(
            "Delete \(specialistAgentPendingDelete?.name ?? "agent")?",
            isPresented: Binding(
                get: { specialistAgentPendingDelete != nil },
                set: { if !$0 { specialistAgentPendingDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let agent = specialistAgentPendingDelete {
                    deleteSpecialistAgent(agent)
                }
                specialistAgentPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                specialistAgentPendingDelete = nil
            }
        } message: {
            Text("This removes the agent from the roster. Linked grok roles and existing sessions stay.")
        }
        .alert(
            "Could not update agents",
            isPresented: Binding(
                get: { specialistAgentError != nil },
                set: { if !$0 { specialistAgentError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { specialistAgentError = nil }
        } message: {
            Text(specialistAgentError ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDoctorRequested)) { _ in
            showDoctor = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .liveSessionMessagesChanged)) { _ in
            // Mark background sessions that finished a turn (or grew while idle) as unread.
            for session in liveSessions {
                let count = session.store.messages.count
                let previousCount = lastSeenMessageCounts[session.id] ?? 0
                let wasStreaming = lastSeenStreaming[session.id] ?? false
                let isStreaming = session.store.isStreaming
                if session.id == selectedSessionID {
                    unreadSessionIDs.remove(session.id)
                } else if BackgroundSessionUnread.shouldMark(
                    wasStreaming: wasStreaming,
                    isStreaming: isStreaming,
                    messageCountGrew: count > previousCount
                ) {
                    unreadSessionIDs.insert(session.id)
                }
                lastSeenMessageCounts[session.id] = count
                lastSeenStreaming[session.id] = isStreaming
            }
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
        .alert("Git action failed", isPresented: gitErrorAlertPresented) {
            Button("OK", role: .cancel) { gitError = nil }
        } message: {
            if let gitError {
                Text(gitError)
            }
        }
        .modifier(ContentViewNotificationHandlers(
            activeStore: activeStore,
            liveSessions: liveSessions,
            sessionListRevision: $sessionListRevision,
            selectedWorkspaceID: $selectedWorkspaceID,
            showPicker: $showPicker,
            showSessions: $showSessions,
            onWorkspaceChange: handleWorkspaceChange,
            onAutoSelectLatestDiff: autoSelectLatestDiffMessage,
            onNewSession: startNewSessionForCurrentProject,
            onPersistSessionLayout: { persistSessionLayout(saveMessages: $0) },
            onLiveSessionAgentChanged: applySpecialistBinding(from:),
            openSettings: openSettings
        ))
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
        selectedSettingsTab = SettingsPaneNavigation.openSettings(
            tab: tab,
            showSessions: &showSessions,
            showSessionDashboard: &showSessionDashboard
        )
        showSettings = true
    }

    private var dashboardEntries: [SessionDashboardEntry] {
        _ = sessionListRevision
        let workspaceID = currentWorkspace?.id
        return liveSessions.compactMap { session in
            guard DashboardScope.isInCurrentProject(
                sessionWorkspaceID: session.workspace.id,
                currentWorkspaceID: workspaceID
            ) else { return nil }
            let store = session.store
            let pending = store.pendingPermissions.count
                + store.pendingQuestions.count
                + (store.pendingExitPlan == nil ? 0 : 1)
            let path = session.workspace.path.standardizedFileURL.path
            let git = dashboardGitByPath[path]
            let isFailed: Bool = {
                if case .failed = store.connectionState { return true }
                return false
            }()
            let group = DashboardGrouping.group(DashboardGroupingInputs(
                isStreaming: store.isStreaming,
                isStarting: store.connectionState == .starting,
                isBusy: store.connectionState == .busy,
                isFailed: isFailed,
                pendingUserCount: pending,
                hasUnreadCompletion: session.id != selectedSessionID
                    && unreadSessionIDs.contains(session.id),
                dirtyCount: git?.dirtyCount ?? 0,
                scheduledCount: store.scheduledTasks.count
            ))
            let specialist = SpecialistAgentRoster.identity(
                for: session.specialistAgentID,
                specialists: specialistAgentStore.agents
            )
            return SessionDashboardEntry(
                id: session.id,
                title: sessionTitle(for: session),
                workspaceName: session.workspace.displayName,
                roleName: store.effectiveAgentDisplayName,
                specialistName: specialist?.name ?? "",
                specialistGlyph: specialist?.glyph ?? "",
                group: group,
                modelName: store.modelDisplayName(store.currentModel),
                pendingCount: pending,
                scheduledCount: store.scheduledTasks.count,
                isWorktree: git?.isWorktree ?? GitService.isWorktree(at: session.workspace.path),
                branch: git?.branch ?? GitService.currentBranch(in: session.workspace.path),
                dirtyCount: git?.dirtyCount ?? 0
            )
        }
    }

    private func forkCurrentSession() async {
        guard let source = activeSession,
              let grokID = source.store.grokSessionId ?? source.grokSessionID else { return }
        purgeEmptySessions(in: source.workspace.id)
        let id = UUID()
        let store = ChatStore()
        let title = "Fork of \(sessionTitle(for: source))"
        liveSessions.append(
            LiveSession(
                id: id,
                store: store,
                workspace: source.workspace,
                title: title,
                grokSessionID: nil,
                specialistAgentID: source.specialistAgentID
            )
        )
        selectedSessionID = id
        selectedWorkspaceID = source.workspace.id
        noteSessionUsed(id)
        sessionListRevision &+= 1
        persistSessionLayout()
        store.bindTabSession(
            id,
            savedModel: source.store.currentModel,
            savedAgent: source.store.persistedAgentSelection
        )
        await store.startForked(workspace: source.workspace, fromSessionID: grokID)
        await enforceConnectionCap()
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
            return DashboardTitle.display(saved)
        }
        return DashboardTitle.display(session.title)
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
        sessionLayout.pinnedSessionIDs.removeAll { $0 == id }
        sessionLayout.settledSessionIDs.remove(id)

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
        SessionMessageStore.remove(for: id)
        Task {
            await store.shutdown()
        }
    }

    private func sessionHasPersistedContent(_ sessionID: UUID) -> Bool {
        SessionRestorePolicy.sessionHasPersistedContent(sessionID)
    }

    private func sessionHasContent(_ session: LiveSession) -> Bool {
        SessionRestorePolicy.sessionHasContent(
            hasUserMessages: session.store.hasUserMessages,
            liveGrokSessionID: session.store.grokSessionId,
            savedGrokSessionID: session.grokSessionID,
            sessionID: session.id
        )
    }

    private func isSessionEmpty(_ session: LiveSession) -> Bool {
        !sessionHasContent(session)
    }

    private func preferredSessionID(for workspace: Workspace, saved: SessionLayoutSnapshot? = nil) -> UUID? {
        let snapshot = saved ?? sessionLayout
        let idsInWorkspace = liveSessions(for: workspace.id).map(\.id)
        return SessionRestorePolicy.preferredSessionID(
            for: workspace.id,
            saved: snapshot,
            liveSessionIDsInWorkspace: idsInWorkspace,
            currentSelectedSessionID: selectedSessionID,
            currentSelectedWorkspaceID: selectedWorkspaceID,
            recentSessionOrder: recentSessionOrder,
            hasContent: { id in
                if let session = liveSessions.first(where: { $0.id == id }) {
                    return sessionHasContent(session)
                }
                return sessionHasPersistedContent(id)
            }
        )
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
            let total = liveSessions(for: workspace.id).filter {
                !sessionLayout.pinnedSessionIDs.contains($0.id)
                    && !sessionLayout.settledSessionIDs.contains($0.id)
            }.count
            counts[workspace.id] = max(0, total - SessionLayoutStore.maxSidebarSessions)
        }
        return counts
    }

    private var sidebarSessions: [SidebarSession] {
        _ = sessionListRevision
        var result: [SidebarSession] = []
        for workspace in workspaceStore.workspaces {
            let workspaceSessions = liveSessions(for: workspace.id)
            var orderedIDs = sessionLayout.sessionOrderByWorkspace[workspace.id] ?? workspaceSessions.map(\.id)
            orderedIDs.removeAll { id in !workspaceSessions.contains { $0.id == id } }
            for session in workspaceSessions where !orderedIDs.contains(session.id) {
                orderedIDs.append(session.id)
            }
            for id in orderedIDs {
                guard let session = workspaceSessions.first(where: { $0.id == id }) else { continue }
                let specialist = SpecialistAgentRoster.identity(
                    for: session.specialistAgentID,
                    specialists: specialistAgentStore.agents
                )
                result.append(
                    SidebarSession(
                        id: session.id,
                        workspaceID: session.workspace.id,
                        title: sessionTitle(for: session),
                        isRunning: session.store.connectionState == .busy
                            || session.store.connectionState == .starting
                            || session.store.isStreaming,
                        status: session.store.activityStatus(
                            hasUnreadCompletion: session.id != selectedSessionID
                                && unreadSessionIDs.contains(session.id)
                        ),
                        isPinned: sessionLayout.pinnedSessionIDs.contains(session.id),
                        isWorktree: GitService.isWorktree(at: session.workspace.path),
                        roleName: session.store.hasExplicitAgent
                            || !session.store.effectiveAgentSelection.isEmpty
                            ? session.store.effectiveAgentDisplayName
                            : "",
                        specialistName: specialist?.name ?? "",
                        specialistGlyph: specialist?.glyph ?? "",
                        workingSince: session.store.turnStartedAt
                    )
                )
            }
        }
        return result
    }

    private var rosterSessionMatches: [SpecialistAgentRoster.LiveSessionMatch] {
        liveSessions.map { session in
            let status = session.store.activityStatus(hasUnreadCompletion: false)
            return SpecialistAgentRoster.LiveSessionMatch(
                sessionID: session.id,
                workspaceID: session.workspace.id,
                agent: session.store.persistedAgentSelection ?? session.store.effectiveAgentSelection.nilIfEmpty,
                isWorking: status == .working || status == .needsInput,
                specialistAgentID: session.specialistAgentID,
                lastAccessed: sessionLayout.records.first { $0.id == session.id }?.lastAccessed
                    ?? .distantPast
            )
        }
    }

    private var workingSpecialistAgentIDs: Set<UUID> {
        Set(specialistAgentStore.agents.compactMap { agent in
            SpecialistAgentRoster.isWorking(
                for: agent,
                sessions: rosterSessionMatches,
                currentWorkspaceID: selectedWorkspaceID
            ) ? agent.id : nil
        })
    }

    private var openableLastSessionAgentIDs: Set<UUID> {
        Set(specialistAgentStore.agents.compactMap { agent in
            SpecialistAgentRoster.lastBoundSessionID(for: agent, sessions: rosterSessionMatches) == nil
                ? nil
                : agent.id
        })
    }

    private var activeBoundSpecialist: SpecialistAgent? {
        guard let id = activeSession?.specialistAgentID else { return nil }
        return specialistAgentStore.agent(id: id)
    }

    private var selectedSpecialistAgentID: UUID? {
        specialistAgentStore.agents.first { agent in
            SpecialistAgentRoster.liveBinding(
                for: agent,
                sessions: rosterSessionMatches,
                currentWorkspaceID: selectedWorkspaceID
            )?.sessionID == selectedSessionID
        }?.id
    }

    private func openAgentEditor(_ agent: SpecialistAgent?) {
        editingSpecialistAgent = agent
        showAgentEditor = true
    }

    private func saveSpecialistAgent(_ draft: SpecialistAgent) {
        do {
            if specialistAgentStore.agent(id: draft.id) == nil {
                _ = try specialistAgentStore.create(draft)
            } else {
                _ = try specialistAgentStore.update(draft)
            }
            try specialistAgentStore.syncLinkedRoles()
        } catch {
            specialistAgentError = error.localizedDescription
        }
    }

    private func duplicateSpecialistAgent(_ agent: SpecialistAgent) {
        let copyName = SpecialistAgentRoster.duplicateName(
            of: agent.name,
            existing: specialistAgentStore.agents.map(\.name)
        )
        let suggestedRole = SubagentRole.suggestedName(from: copyName)
        let copy = SpecialistAgent(
            name: copyName,
            mission: agent.mission,
            glyph: agent.glyph,
            color: agent.color,
            roleName: suggestedRole.isEmpty ? nil : suggestedRole,
            defaultModel: agent.defaultModel,
            permissionProfile: agent.permissionProfile,
            browserEnabled: agent.browserEnabled,
            computerUseEnabled: agent.computerUseEnabled,
            preferredSkills: agent.preferredSkills
        )
        saveSpecialistAgent(copy)
    }

    private func deleteSpecialistAgent(_ agent: SpecialistAgent) {
        do {
            try specialistAgentStore.delete(id: agent.id)
            clearSpecialistBinding(agent.id)
        } catch {
            specialistAgentError = error.localizedDescription
        }
    }

    private func clearSpecialistBinding(_ agentID: UUID) {
        var changed = false
        for index in liveSessions.indices {
            let cleared = SpecialistAgentRoster.clearedSpecialistID(
                liveSessions[index].specialistAgentID,
                deleted: agentID
            )
            if liveSessions[index].specialistAgentID != cleared {
                liveSessions[index].specialistAgentID = cleared
                changed = true
            }
        }
        if changed {
            persistSessionLayout()
            sessionListRevision &+= 1
        }
    }

    private func applySpecialistBinding(from store: ChatStore) {
        guard let index = liveSessions.firstIndex(where: { $0.store === store }) else { return }
        let selection = store.persistedAgentSelection ?? store.effectiveAgentSelection
        let resolved = SpecialistAgentRoster.specialistID(
            matchingAgentSelection: selection,
            in: specialistAgentStore.agents
        )
        guard liveSessions[index].specialistAgentID != resolved else { return }
        liveSessions[index].specialistAgentID = resolved
        sessionListRevision &+= 1
    }

    private func rememberLastSession(_ agent: SpecialistAgent, sessionID: UUID) {
        guard agent.lastSessionID != sessionID else { return }
        var updated = agent
        updated.lastSessionID = sessionID
        do {
            _ = try specialistAgentStore.update(updated)
        } catch {
            specialistAgentError = error.localizedDescription
        }
    }

    private func installStarterCrew() {
        do {
            try specialistAgentStore.installStarterCrew()
        } catch {
            specialistAgentError = error.localizedDescription
        }
    }

    private func activateSpecialistAgent(_ agent: SpecialistAgent, forceNew: Bool = false) {
        guard let workspace = currentWorkspace else {
            showNeedProjectForAgent = true
            return
        }
        if !forceNew,
           let binding = SpecialistAgentRoster.liveBinding(
               for: agent,
               sessions: rosterSessionMatches,
               currentWorkspaceID: workspace.id
           ) {
            selectSession(binding.sessionID)
            rememberLastSession(agent, sessionID: binding.sessionID)
            return
        }
        Task {
            let role = SpecialistAgentRoster.launchAgentSelection(for: agent)
            let id = await createLiveSession(
                for: workspace,
                title: SpecialistAgentRoster.sessionTitle(for: agent),
                agent: role,
                specialistAgentID: agent.id
            )
            rememberLastSession(agent, sessionID: id)
        }
    }

    private func openLastSpecialistSession(_ agent: SpecialistAgent) {
        guard let sessionID = SpecialistAgentRoster.lastBoundSessionID(
            for: agent,
            sessions: rosterSessionMatches
        ) else { return }
        selectSession(sessionID)
        rememberLastSession(agent, sessionID: sessionID)
    }

    private func visibleSessionIDs(for workspaceID: Workspace.ID) -> [UUID] {
        let eligible = liveSessions(for: workspaceID).filter {
            !sessionLayout.pinnedSessionIDs.contains($0.id)
                && !sessionLayout.settledSessionIDs.contains($0.id)
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

    private func persistSessionLayout(saveMessages: Bool = true) {
        if saveMessages {
            for session in liveSessions {
                SessionMessageStore.save(session.store.messages, for: session.id)
            }
        }
        var records: [SavedSessionRecord] = []
        for session in liveSessions {
            // Prefer the live process id, but fall back to the known/saved id so lazily-restored
            // (not-yet-started) and LRU-evicted sessions are still persisted and resumable.
            let grokSessionID = session.store.grokSessionId ?? session.grokSessionID
            guard sessionHasContent(session) else { continue }
            let existing = sessionLayout.records.first { $0.id == session.id }
            records.append(
                SavedSessionRecord(
                    id: session.id,
                    workspaceID: session.workspace.id,
                    grokSessionID: grokSessionID,
                    title: sessionTitle(for: session),
                    model: session.store.currentModel,
                    agent: session.store.persistedAgentSelection,
                    specialistAgentID: session.specialistAgentID,
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

        let sessionShelves = SessionLayoutStore.normalizedSessionShelves(
            pinnedSessionIDs: sessionLayout.pinnedSessionIDs,
            settledSessionIDs: sessionLayout.settledSessionIDs,
            validSessionIDs: recordIDs
        )
        sessionLayout = SessionLayoutSnapshot(
            records: records,
            sessionOrderByWorkspace: order,
            selectedSessionID: selectedSessionID,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedSessionIDByWorkspace: selectedByWorkspace,
            expandedSessionWorkspaceIDs: expandedSessionWorkspaceIDs,
            hiddenSessionWorkspaceIDs: hiddenSessionWorkspaceIDs,
            pinnedSessionIDs: sessionShelves.pinned,
            settledSessionIDs: sessionShelves.settled
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
            store.prepare(workspace: workspace, savedGrokSessionID: record.grokSessionID)
            let legacyModel = record.model ?? SessionLayoutStore.agentSettings(for: workspace.id).model
            store.bindTabSession(record.id, savedModel: legacyModel, savedAgent: record.agent)
            store.restorePersistedMessages(
                for: record.id,
                grokSessionID: record.grokSessionID,
                workspace: workspace
            )
            let boundID = record.specialistAgentID.flatMap { specialistAgentStore.agent(id: $0)?.id }
            liveSessions.append(
                LiveSession(
                    id: record.id,
                    store: store,
                    workspace: workspace,
                    title: title,
                    grokSessionID: record.grokSessionID,
                    specialistAgentID: boundID
                )
            )
            restoredSessionCount += 1
        }

        sessionListRevision &+= 1
        recentSessionOrder = SessionRestorePolicy.recentSessionOrder(from: restorableRecords)

        let hasContent: (UUID) -> Bool = { id in
            if let session = liveSessions.first(where: { $0.id == id }) {
                return sessionHasContent(session)
            }
            return sessionHasPersistedContent(id)
        }

        let hasTranscript: (UUID) -> Bool = { id in
            if let session = liveSessions.first(where: { $0.id == id }) {
                return SessionRestorePolicy.sessionHasRestorableTranscript(
                    hasUserMessages: session.store.hasUserMessages,
                    sessionID: id
                )
            }
            return sessionHasPersistedContent(id)
        }

        let workspaceID = saved.selectedWorkspaceID
            ?? restorableRecords.max(by: { $0.lastAccessed < $1.lastAccessed })?.workspaceID
            ?? liveSessions.first?.workspace.id

        if let workspaceID,
           let selected = SessionRestorePolicy.restoreSelectedSessionID(
               saved: saved,
               workspaceID: workspaceID,
               liveSessionIDsInWorkspace: liveSessions
                   .filter { $0.workspace.id == workspaceID }
                   .map(\.id),
               hasTranscript: hasTranscript,
               hasContent: hasContent,
               preferredSessionID: { wsID in
                   guard let workspace = workspaceStore.workspaces.first(where: { $0.id == wsID }) else {
                       return nil
                   }
                   return preferredSessionID(for: workspace, saved: saved)
               }
           ) {
            selectSession(selected)
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
        guard SettingsPaneNavigation.shouldLeaveSettings(
            incomingWorkspaceID: newID,
            activeWorkspaceID: activeSession?.workspace.id ?? selectedWorkspaceID
        ) else { return }
        if let id = newID,
           let ws = workspaceStore.workspaces.first(where: { $0.id == id }) {
            showSettings = false
            selectProject(ws)
        }
    }

    private func selectProject(_ workspace: Workspace) {
        selectedWorkspaceID = workspace.id
        if let active = activeSession, active.workspace.id == workspace.id {
            return
        }
        if let preferred = preferredSessionID(for: workspace) {
            selectSession(preferred)
        } else {
            Task { await createLiveSession(for: workspace) }
        }
    }

    private func selectSession(_ id: UUID) {
        guard let session = liveSessions.first(where: { $0.id == id }) else { return }
        // Focusing a session clears its unread badge.
        unreadSessionIDs.remove(id)
        lastSeenMessageCounts[id] = session.store.messages.count
        if session.store.messages.isEmpty {
            session.store.restorePersistedMessages(
                for: id,
                grokSessionID: session.grokSessionID,
                workspace: session.workspace
            )
        } else {
            session.store.mergePersistedMessages(SessionMessageStore.messages(for: id))
            session.store.reconcileTranscriptFromGrokIfNeeded()
            if !session.store.isStreaming {
                session.store.attachActivityFromGrokIfNeeded()
            }
        }
        purgeEmptySessions(in: session.workspace.id, keeping: id)
        let savedRecord = sessionLayout.records.first(where: { $0.id == id })
        let savedModel = savedRecord?.model
            ?? SessionLayoutStore.agentSettings(for: session.workspace.id).model
        session.store.bindTabSession(id, savedModel: savedModel, savedAgent: savedRecord?.agent)
        session.store.syncWorkspaceReasoningEffortFromStorage()
        session.store.syncTabModelToLiveProcessIfNeeded()
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
        await session.store.start(
            workspace: session.workspace,
            resumeSession: info,
            preserveMessages: true
        )
        if let idx = liveSessions.firstIndex(where: { $0.id == id }) {
            liveSessions[idx].grokSessionID = session.store.grokSessionId ?? liveSessions[idx].grokSessionID
        }
        persistSessionLayout()
    }

    /// Tear down grok processes for sessions beyond the MRU cap so the resident footprint
    /// stays bounded. The selected/most-recent sessions, mid-turn sessions, and sessions
    /// that own a `/loop` schedule are kept.
    private func enforceConnectionCap() async {
        for index in liveSessions.indices {
            let session = liveSessions[index]
            let evict = ConnectionCapPolicy.shouldEvict(
                sessionID: session.id,
                selectedSessionID: selectedSessionID,
                recentOrder: recentSessionOrder,
                maxConnected: maxConnectedSessions,
                connectionState: session.store.connectionState,
                hasScheduledTasks: !session.store.scheduledTasks.isEmpty
            )
            guard evict else { continue }
            // Preserve the grok id so the session can be re-resumed when reopened.
            liveSessions[index].grokSessionID = session.store.grokSessionId ?? session.grokSessionID
            await session.store.shutdown()
        }
    }

    private func startNewSessionForCurrentProject() {
        guard let workspace = currentWorkspace else { return }
        Task { await createLiveSession(for: workspace) }
    }

    private func pinSession(_ id: UUID) {
        var pinned = sessionLayout.pinnedSessionIDs
        guard !pinned.contains(id) else { return }
        if pinned.count >= SessionLayoutStore.maxPinnedSessions {
            pinned.removeFirst()
        }
        pinned.append(id)
        sessionLayout.pinnedSessionIDs = pinned
        sessionLayout.settledSessionIDs.remove(id)
        persistSessionLayout(saveMessages: false)
        sessionListRevision &+= 1
    }

    private func unpinSession(_ id: UUID) {
        sessionLayout.pinnedSessionIDs.removeAll { $0 == id }
        persistSessionLayout(saveMessages: false)
        sessionListRevision &+= 1
    }

    private func settleSession(_ id: UUID) {
        guard let session = liveSessions.first(where: { $0.id == id }),
              SidebarPresentation.canSettle(
                session.store.activityStatus(
                    hasUnreadCompletion: id != selectedSessionID && unreadSessionIDs.contains(id)
                )
              ) else { return }
        sessionLayout.pinnedSessionIDs.removeAll { $0 == id }
        sessionLayout.settledSessionIDs.insert(id)
        persistSessionLayout(saveMessages: false)
        sessionListRevision &+= 1
    }

    private func unsettleSession(_ id: UUID) {
        guard sessionLayout.settledSessionIDs.remove(id) != nil else { return }
        persistSessionLayout(saveMessages: false)
        sessionListRevision &+= 1
    }

    private func clearSessionTranscript(id: UUID) {
        guard let session = liveSessions.first(where: { $0.id == id }) else { return }
        session.store.clearTranscript()
        SessionMessageStore.save(session.store.messages, for: id)
        sessionListRevision &+= 1
    }

    private func duplicateSession(_ id: UUID) async {
        guard let session = liveSessions.first(where: { $0.id == id }) else { return }
        let title = sessionTitle(for: session)
        let copyTitle: String = {
            let base = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if base.isEmpty { return "Session copy" }
            return base.hasSuffix(" (copy)") ? base : "\(base) (copy)"
        }()
        _ = await createLiveSession(
            for: session.workspace,
            title: copyTitle,
            agent: session.store.persistedAgentSelection,
            specialistAgentID: session.specialistAgentID
        )
    }

    @discardableResult
    private func createLiveSession(
        for workspace: Workspace,
        resumeSession: GrokSessionInfo? = nil,
        title: String? = nil,
        agent: String? = nil,
        specialistAgentID: UUID? = nil
    ) async -> UUID {
        purgeEmptySessions(in: workspace.id)
        let id = UUID()
        let store = ChatStore()
        let resolvedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? resumeSession.flatMap { session in
                SessionNameStore.name(for: session.id)
                    ?? (session.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : session.summary)
            }
            ?? SessionTitle.defaultTitle
        liveSessions.append(
            LiveSession(
                id: id,
                store: store,
                workspace: workspace,
                title: resolvedTitle,
                grokSessionID: resumeSession?.id,
                specialistAgentID: specialistAgentID
            )
        )
        selectedSessionID = id
        selectedWorkspaceID = workspace.id
        previewMessageID = nil
        previewDiffs = []
        noteSessionUsed(id)
        Task { await refreshProjectChangedFiles() }
        sessionListRevision &+= 1
        persistSessionLayout()
        if let title, ParallelSessionNaming.isValidName(title) {
            SessionNameStore.setName(title, for: id.uuidString)
        }
        if let resumeSession {
            store.prepare(workspace: workspace, savedGrokSessionID: resumeSession.id)
            store.bindTabSession(id, savedModel: nil, savedAgent: agent)
            await store.start(workspace: workspace, resumeSession: resumeSession)
        } else {
            store.prepare(workspace: workspace)
            store.bindTabSession(
                id,
                savedModel: SessionLayoutStore.agentSettings(for: workspace.id).model,
                savedAgent: agent
            )
        }
        await enforceConnectionCap()
        return id
    }

    @discardableResult
    private func createNamedSession(_ spec: ParallelSessionSpec, in project: Workspace) async -> UUID? {
        let workspace: Workspace
        if spec.useWorktree {
            guard let created = await addWorktreeWorkspace(
                project: project,
                branch: spec.worktreeBranch,
                path: spec.worktreePath
            ) else { return nil }
            workspace = created
        } else {
            workspace = project
        }
        let agent = spec.agent.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let specialistID = agent.flatMap {
            SpecialistAgentRoster.specialistID(
                matchingAgentSelection: $0,
                in: specialistAgentStore.agents
            )
        }
        let id = await createLiveSession(
            for: workspace,
            title: spec.name,
            agent: agent,
            specialistAgentID: specialistID
        )
        await refreshDashboardGit()
        return id
    }

    private func createAutomation(_ spec: AutomationSpec, in project: Workspace) async {
        guard let id = await createNamedSession(spec.session, in: project),
              let session = liveSessions.first(where: { $0.id == id }) else { return }
        _ = await session.store.createScheduledTask(interval: spec.interval, prompt: spec.prompt)
        sessionListRevision &+= 1
        await enforceConnectionCap()
        await refreshDashboardGit()
    }

    private func refreshDashboardGit() async {
        let paths = DashboardGitRefresh.uniquePaths(
            sessions: liveSessions.map { ($0.workspace.id, $0.workspace.path) },
            currentWorkspaceID: currentWorkspace?.id
        )
        var snapshots: [String: DashboardGitSnapshot] = [:]
        for url in paths {
            snapshots[url.path] = await GitService.dashboardSnapshot(at: url)
        }
        dashboardGitByPath = snapshots
        sessionListRevision &+= 1
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
        guard let workspace = await addWorktreeWorkspace(project: project, branch: branch, path: path) else {
            return
        }
        await createLiveSession(for: workspace)
        gitCheckoutRequest = nil
    }

    @discardableResult
    private func addWorktreeWorkspace(project: Workspace, branch: String, path: String) async -> Workspace? {
        do {
            let pathURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            _ = try await GitService.run(["worktree", "add", "-b", branch, pathURL.path], in: project.path)
            if let existing = workspaceStore.workspaces.first(where: {
                $0.path.standardizedFileURL.path == pathURL.standardizedFileURL.path
            }) {
                return existing
            }
            let workspace = Workspace(name: pathURL.lastPathComponent, path: pathURL)
            workspaceStore.add(workspace)
            return workspace
        } catch {
            gitError = error.localizedDescription
            return nil
        }
    }

    private func openUpdatesPanel() {
        Task {
            await UpdateUI.presentUpdatePanel(refresh: false) {
                refreshUpgradeBannerState()
            }
        }
    }

    private func refreshUpgradeBannerState() {
        let appAvailable = UpdateScheduler.hasActionableAppUpdate
        let cliAvailable = UpdateScheduler.hasActionableCLIUpdate
        sidebarUpdateAppVersion = appAvailable ? UpdateScheduler.cachedAppRelease?.latestVersion : nil
        sidebarUpdateCLIVersion = cliAvailable ? UpdateScheduler.cachedCLIStatus?.latestVersion : nil
        showSidebarUpdateButton = appAvailable || cliAvailable

        guard !isUpgradeBannerDismissed else {
            showUpgradeBanner = false
            bannerAppVersion = nil
            bannerCLIVersion = nil
            return
        }

        guard appAvailable || cliAvailable else {
            showUpgradeBanner = false
            bannerAppVersion = nil
            bannerCLIVersion = nil
            return
        }

        bannerAppVersion = sidebarUpdateAppVersion
        bannerCLIVersion = sidebarUpdateCLIVersion
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
    static let liveSessionModelChanged = Notification.Name("liveSessionModelChanged")
    static let liveSessionAgentChanged = Notification.Name("liveSessionAgentChanged")
    static let workspaceAgentSettingsChanged = Notification.Name("workspaceAgentSettingsChanged")
    static let subagentRolesChanged = Notification.Name("subagentRolesChanged")
    static let specialistAgentsChanged = Notification.Name("specialistAgentsChanged")
    static let grokBuildUpdateAvailable = Notification.Name("grokBuildUpdateAvailable")
    static let grokBuildUpdateStateChanged = Notification.Name("grokBuildUpdateStateChanged")
    static let grokBuildUpdaterPhaseChanged = Notification.Name("grokBuildUpdaterPhaseChanged")
    static let grokBuildCLIUpdaterPhaseChanged = Notification.Name("grokBuildCLIUpdaterPhaseChanged")
    static let grokBuildCLIUpdated = Notification.Name("grokBuildCLIUpdated")
    static let grokBuildRestartSessionsRequested = Notification.Name("grokBuildRestartSessionsRequested")
    static let grokBuildPrepareForShutdown = Notification.Name("grokBuildPrepareForShutdown")
    static let retryConnectionRequested = Notification.Name("retryConnectionRequested")
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
    static let workflowsConfigChanged = Notification.Name("workflowsConfigChanged")
    static let openDoctorRequested = Notification.Name("openDoctorRequested")
}

private struct ContentViewNotificationHandlers: ViewModifier {
    let activeStore: ChatStore
    let liveSessions: [ContentView.LiveSession]
    @Binding var sessionListRevision: Int
    @Binding var selectedWorkspaceID: Workspace.ID?
    @Binding var showPicker: Bool
    @Binding var showSessions: Bool
    let onWorkspaceChange: (Workspace.ID?) -> Void
    let onAutoSelectLatestDiff: () -> Void
    let onNewSession: () -> Void
    let onPersistSessionLayout: (Bool) -> Void
    let onLiveSessionAgentChanged: (ChatStore) -> Void
    let openSettings: (SettingsTab) -> Void

    func body(content: Content) -> some View {
        content
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
            .onChange(of: selectedWorkspaceID) { oldID, newID in
                guard oldID != newID else { return }
                onWorkspaceChange(newID)
            }
            .onChange(of: activeStore.messages) { _, _ in
                onAutoSelectLatestDiff()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newSessionRequested)) { _ in
                onNewSession()
            }
            .modifier(StatusMenuNotificationHandlers(
                activeStore: activeStore,
                openSettings: openSettings
            ))
            .onChange(of: activeStore.grokSessionId) { _, _ in
                onPersistSessionLayout(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .liveSessionMessagesChanged)) { note in
                handleLiveSessionMessagesChanged(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .workspaceAgentSettingsChanged)) { note in
                handleWorkspaceAgentSettingsChanged(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .liveSessionModelChanged)) { _ in
                onPersistSessionLayout(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .liveSessionAgentChanged)) { note in
                if let store = note.object as? ChatStore {
                    onLiveSessionAgentChanged(store)
                }
                onPersistSessionLayout(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .grokBuildPrepareForShutdown)) { _ in
                handlePrepareForShutdown()
            }
            .onReceive(NotificationCenter.default.publisher(for: .grokBuildRestartSessionsRequested)) { _ in
                handleRestartSessionsRequested()
            }
    }

    private func handleLiveSessionMessagesChanged(_ note: Notification) {
        sessionListRevision &+= 1
        if let store = note.object as? ChatStore,
           let session = liveSessions.first(where: { $0.store === store }) {
            SessionMessageStore.save(store.messages, for: session.id)
        }
        onPersistSessionLayout(false)
    }

    private func handleWorkspaceAgentSettingsChanged(_ note: Notification) {
        guard let workspaceID = note.userInfo?["workspaceID"] as? UUID else { return }
        for session in liveSessions where session.workspace.id == workspaceID {
            session.store.syncWorkspaceReasoningEffortFromStorage()
        }
    }

    private func handlePrepareForShutdown() {
        onPersistSessionLayout(true)
        Task {
            for session in liveSessions {
                await session.store.shutdown()
            }
        }
    }

    private func handleRestartSessionsRequested() {
        Task {
            for session in liveSessions {
                await session.store.retryConnection()
            }
            NotificationCenter.default.post(name: .grokStatusChanged, object: nil)
        }
    }
}

private struct StatusMenuNotificationHandlers: ViewModifier {
    let activeStore: ChatStore
    let openSettings: (SettingsTab) -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .retryConnectionRequested)) { _ in
                Task { await activeStore.retryConnection() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
                let tab: SettingsTab = UpdateScheduler.hasAnyActionableUpdate ? .app : .agents
                openSettings(tab)
            }
    }
}
