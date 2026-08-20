import SwiftUI
import AppKit

struct SidebarSession: Identifiable, Hashable {
    let id: UUID
    let workspaceID: Workspace.ID
    let title: String
    let isRunning: Bool
    /// Activity/attention status for the sidebar badge. Defaults to `.idle`.
    var status: SessionActivityStatus = .idle
    /// Pinned to the top of its project session list.
    var isPinned: Bool = false
    /// Workspace path is a linked git worktree.
    var isWorktree: Bool = false
    /// Bound session agent / custom role display name (empty to hide).
    var roleName: String = ""
    /// Specialist roster display name when this tab is bound (empty to hide).
    var specialistName: String = ""
    /// SF Symbol for the specialist badge (empty when unbound).
    var specialistGlyph: String = ""
    /// Start of the current turn, used for the visible Working duration.
    var workingSince: Date?
}

enum SidebarPresentation {
    static func matches(_ query: String, values: [String]) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        return values.contains { $0.localizedCaseInsensitiveContains(normalized) }
    }

    static func matchesWorkspace(
        _ query: String,
        workspaceName: String,
        sessions: [SidebarSession]
    ) -> Bool {
        matches(
            query,
            values: [workspaceName] + sessions.flatMap { [$0.title, $0.roleName, $0.specialistName] }
        )
    }

    static func shouldCollapseSessions(isFilterEmpty: Bool, isExpanded: Bool) -> Bool {
        isFilterEmpty && !isExpanded
    }

    static func canSettle(_ status: SessionActivityStatus) -> Bool {
        status != .working && status != .needsInput
    }

    static func statusLabel(
        for status: SessionActivityStatus,
        workingSince: Date?,
        now: Date
    ) -> String? {
        switch status {
        case .idle:
            return nil
        case .working:
            guard let workingSince else { return "Working" }
            return "Working \(durationLabel(from: workingSince, to: now))"
        case .needsInput:
            return "Needs input"
        case .finishedUnread:
            return "Completed"
        case .error:
            return "Error"
        }
    }

    static func durationLabel(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds < 60 { return "\(max(1, seconds))s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}

enum SidebarUpdateButtonAppearance {
    static let background = Color.blue
    static let foreground = Color.white
}

enum SidebarSectionActions {
    static let newAgent = "New Agent"
    static let addProject = "Add Project"
}

struct SidebarView: View {
    @Binding var workspaces: [Workspace]
    var orderedWorkspaces: [Workspace]
    var pinnedWorkspaceIDs: [UUID]
    var pinnedSessionIDs: [UUID] = []
    @Binding var selectedWorkspaceID: Workspace.ID?
    var sessions: [SidebarSession] = []
    var hiddenSessionCounts: [Workspace.ID: Int] = [:]
    var selectedSessionID: UUID?
    @Binding var expandedSessionWorkspaceIDs: Set<Workspace.ID>
    @Binding var hiddenSessionWorkspaceIDs: Set<Workspace.ID>
    @Binding var settledSessionIDs: Set<UUID>

    var onAddWorkspace: () -> Void
    var onSelectWorkspace: (Workspace) -> Void
    var onSelectSession: (UUID) -> Void = { _ in }
    var onNewSessionForWorkspace: (Workspace) -> Void = { _ in }
    var onRenameSession: (UUID, String) -> Void = { _, _ in }
    var onCloseSession: (UUID) -> Void = { _ in }
    var onPinSession: (UUID) -> Void = { _ in }
    var onUnpinSession: (UUID) -> Void = { _ in }
    var onSettleSession: (UUID) -> Void = { _ in }
    var onUnsettleSession: (UUID) -> Void = { _ in }
    var onMarkSessionUnread: (UUID) -> Void = { _ in }
    var onMarkSessionRead: (UUID) -> Void = { _ in }
    var onDuplicateSession: (UUID) -> Void = { _ in }
    var onClearSessionTranscript: (UUID) -> Void = { _ in }
    var onMoveWorkspace: (IndexSet, Int) -> Void = { _, _ in }
    var onPinWorkspace: (Workspace) -> Void = { _ in }
    var onUnpinWorkspace: (Workspace) -> Void = { _ in }
    var onRemoveWorkspace: (Workspace) -> Void = { _ in }
    var onMoveSession: (Workspace.ID, IndexSet, Int) -> Void = { _, _, _ in }
    var onSwitchBranch: (Workspace) -> Void = { _ in }
    var onCreateWorktree: (Workspace) -> Void = { _ in }
    var onSessionDisclosureChanged: () -> Void = {}
    var onOpenSettings: () -> Void
    var isSettingsSelected: Bool = false
    var hasActionableUpdate: Bool = false
    var updateButtonTitle: String = "Update"
    var updateButtonAccessibilityLabel: String = "Updates available"
    var onOpenUpdates: () -> Void = {}
    var specialistAgents: [SpecialistAgent] = []
    var agentWorkingIDs: Set<UUID> = []
    var selectedSpecialistAgentID: UUID?
    var onSelectSpecialistAgent: (SpecialistAgent) -> Void = { _ in }
    var onStartSpecialistAgentSession: (SpecialistAgent) -> Void = { _ in }
    var onNewSpecialistAgent: () -> Void = {}
    var onEditSpecialistAgent: (SpecialistAgent) -> Void = { _ in }
    var onDuplicateSpecialistAgent: (SpecialistAgent) -> Void = { _ in }
    var onDeleteSpecialistAgent: (SpecialistAgent) -> Void = { _ in }
    var onInstallStarterCrew: () -> Void = {}
    var openableLastSessionAgentIDs: Set<UUID> = []
    var onOpenLastSpecialistSession: (SpecialistAgent) -> Void = { _ in }
    var liveBoundAgentIDs: Set<UUID> = []
    var onToggleSpecialistAgentPin: (SpecialistAgent) -> Void = { _ in }

    @AppStorage(GrokSettingsKeys.showAllAgents) private var showAllAgents = false
    @State private var filter = ""
    @State private var renamingSessionID: UUID?
    @State private var renameText = ""
    @State private var settledSessionsExpanded = false

    private let collapsedSessionLimit = 5

    private var filtered: [Workspace] {
        guard !isFilterEmpty else { return orderedWorkspaces }
        return orderedWorkspaces.filter { workspace in
            SidebarPresentation.matchesWorkspace(
                filter,
                workspaceName: workspace.displayName,
                sessions: activeSessions(for: workspace.id)
            )
        }
    }

    private func sessions(for workspaceID: Workspace.ID) -> [SidebarSession] {
        sessions.filter { $0.workspaceID == workspaceID }
    }

    private var isFilterEmpty: Bool {
        filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayedAgents: [SpecialistAgent] {
        SpecialistAgentRoster.displayed(
            agents: specialistAgents,
            showAll: showAllAgents,
            liveBoundIDs: liveBoundAgentIDs,
            query: filter
        )
    }

    private var showsEmptyActiveAgents: Bool {
        isFilterEmpty
            && SpecialistAgentRoster.showsEmptyActiveState(
                agents: specialistAgents,
                showAll: showAllAgents,
                liveBoundIDs: liveBoundAgentIDs
            )
    }

    private func activeSessions(for workspaceID: Workspace.ID) -> [SidebarSession] {
        sessions(for: workspaceID).filter {
            !$0.isPinned && !settledSessionIDs.contains($0.id)
        }
    }

    private func displayedActiveSessions(for workspace: Workspace) -> [SidebarSession] {
        let active = activeSessions(for: workspace.id)
        if isFilterEmpty {
            var limited = Array(active.prefix(SessionLayoutStore.maxSidebarSessions))
            if let selected = active.first(where: { $0.id == selectedSessionID }),
               !limited.contains(where: { $0.id == selected.id }),
               !limited.isEmpty {
                limited[limited.count - 1] = selected
            }
            return limited
        }
        if workspace.displayName.localizedCaseInsensitiveContains(filter) {
            return active
        }
        return active.filter {
            SidebarPresentation.matches(filter, values: [$0.title, $0.roleName, $0.specialistName])
        }
    }

    private var pinnedSessions: [SidebarSession] {
        sessions.filter(\.isPinned).filter { session in
            SidebarPresentation.matches(
                filter,
                values: [session.title, session.roleName, session.specialistName, workspaceName(for: session.workspaceID)]
            )
        }.sorted { left, right in
            let leftIndex = pinnedSessionIDs.firstIndex(of: left.id) ?? .max
            let rightIndex = pinnedSessionIDs.firstIndex(of: right.id) ?? .max
            return leftIndex < rightIndex
        }
    }

    private var settledSessions: [SidebarSession] {
        sessions.filter { settledSessionIDs.contains($0.id) }.filter { session in
            SidebarPresentation.matches(
                filter,
                values: [session.title, session.roleName, session.specialistName, workspaceName(for: session.workspaceID)]
            )
        }
    }

    private func workspaceName(for id: Workspace.ID) -> String {
        orderedWorkspaces.first(where: { $0.id == id })?.displayName ?? "Project"
    }

    private func isSessionsExpanded(for workspaceID: Workspace.ID) -> Bool {
        expandedSessionWorkspaceIDs.contains(workspaceID)
    }

    private func collapsedSessions(from sessions: [SidebarSession]) -> [SidebarSession] {
        Array(sessions.prefix(collapsedSessionLimit))
    }

    private func hiddenCount(for workspaceID: Workspace.ID, loadedSessions: [SidebarSession], isExpanded: Bool) -> Int {
        let hiddenBeyondLoaded = hiddenSessionCounts[workspaceID] ?? 0
        if isExpanded {
            return hiddenBeyondLoaded
        }
        return max(0, loadedSessions.count - collapsedSessionLimit) + hiddenBeyondLoaded
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    if specialistAgents.isEmpty && isFilterEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No agents yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Add sample agents", action: onInstallStarterCrew)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .accessibilityLabel("Add sample agents")
                            Button("New Agent", action: onNewSpecialistAgent)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("New Agent")
                        }
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))
                        .listRowBackground(Color.clear)
                    } else if showsEmptyActiveAgents {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No active agents.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Show all") { showAllAgents = true }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .accessibilityLabel("Show all agents")
                            Button("New Agent", action: onNewSpecialistAgent)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("New Agent")
                        }
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))
                        .listRowBackground(Color.clear)
                    } else {
                        if !specialistAgents.isEmpty {
                            Toggle("Show all agents", isOn: $showAllAgents)
                                .toggleStyle(.checkbox)
                                .controlSize(.small)
                                .font(.caption)
                                .padding(.vertical, 2)
                                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                                .listRowBackground(Color.clear)
                                .accessibilityLabel("Show all agents")
                                .accessibilityValue(showAllAgents ? "On" : "Off")
                        }
                        ForEach(displayedAgents) { agent in
                            specialistAgentRow(agent)
                        }
                    }
                } header: {
                    HStack {
                        Label("Agents", systemImage: "person.2.fill")
                        Spacer()
                        Button(action: onNewSpecialistAgent) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(SidebarSectionActions.newAgent)
                    }
                }

                if !pinnedSessions.isEmpty {
                    Section {
                        ForEach(pinnedSessions) { session in
                            sessionRow(session, showsProject: true)
                        }
                    } header: {
                        Label("Pinned", systemImage: "pin.fill")
                    }
                }

                Section {
                    ForEach(filtered) { ws in
                        let projectSessions = displayedActiveSessions(for: ws)
                        let isSelected = selectedWorkspaceID == ws.id
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                onSelectWorkspace(ws)
                            } label: {
                                WorkspaceRow(
                                    workspace: ws,
                                    isPinned: pinnedWorkspaceIDs.contains(ws.id),
                                    isSelected: isSelected,
                                    isWorktree: GitService.isWorktree(at: ws.path),
                                    hasSessions: !projectSessions.isEmpty,
                                    areSessionsHidden: hiddenSessionWorkspaceIDs.contains(ws.id),
                                    onToggleSessions: {
                                        toggleSessionVisibility(for: ws.id)
                                    }
                                )
                            }
                            .buttonStyle(.plain)

                            if isSelected, let branch = GitService.currentBranch(in: ws.path) {
                                Button {
                                    onSwitchBranch(ws)
                                } label: {
                                    WorkspaceBranchCaption(branch: branch)
                                }
                                .buttonStyle(.plain)
                                // Hug the chip — a full-width row here sits on top of the
                                // session list and steals clicks (opens the git sheet spinner).
                                .fixedSize(horizontal: true, vertical: true)
                                .padding(.leading, 34)
                                .padding(.bottom, 4)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            projectContextMenu(for: ws)
                        }

                        if (isSelected || !projectSessions.isEmpty),
                           (!isFilterEmpty || !hiddenSessionWorkspaceIDs.contains(ws.id)) {
                            let isExpanded = isSessionsExpanded(for: ws.id)
                            let shownSessions = SidebarPresentation.shouldCollapseSessions(
                                isFilterEmpty: isFilterEmpty,
                                isExpanded: isExpanded
                            ) ? collapsedSessions(from: projectSessions) : projectSessions

                            if isExpanded && isFilterEmpty {
                                ForEach(shownSessions) { session in
                                    sessionRow(session)
                                }
                                .onMove { source, destination in
                                    onMoveSession(ws.id, source, destination)
                                }
                            } else {
                                ForEach(shownSessions) { session in
                                    sessionRow(session)
                                }
                            }

                            let hidden = hiddenCount(for: ws.id, loadedSessions: projectSessions, isExpanded: isExpanded)
                            if isFilterEmpty && (hidden > 0 || isExpanded) {
                                HStack(spacing: 6) {
                                    Text(isExpanded ? "Show less" : "Show more")
                                        .font(.caption.weight(.medium))
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .font(.caption2.weight(.semibold))
                                    Spacer()
                                }
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isExpanded {
                                        expandedSessionWorkspaceIDs.remove(ws.id)
                                    } else {
                                        expandedSessionWorkspaceIDs.insert(ws.id)
                                    }
                                    onSessionDisclosureChanged()
                                }
                                .accessibilityAddTraits(.isButton)
                                .listRowInsets(EdgeInsets(top: 2, leading: 34, bottom: 6, trailing: 10))
                                .listRowBackground(Color.clear)

                                if isExpanded, hidden > 0 {
                                    Text("\(hidden) \(SessionsHistoryCopy.sidebarOverflowSuffix)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .listRowInsets(EdgeInsets(top: 0, leading: 34, bottom: 6, trailing: 10))
                                }
                            }
                        }
                    }
                    .onMove { source, destination in
                        guard filter.isEmpty else { return }
                        onMoveWorkspace(source, destination)
                    }

                } header: {
                    HStack {
                        Label("Projects", systemImage: "folder")
                        Spacer()
                        Button(action: onAddWorkspace) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(SidebarSectionActions.addProject)
                    }
                }

                if !settledSessions.isEmpty {
                    Section {
                        if settledSessionsExpanded || !isFilterEmpty {
                            ForEach(settledSessions) { session in
                                sessionRow(session, showsProject: true)
                            }
                            if isFilterEmpty {
                                Button("Hide settled sessions") {
                                    settledSessionsExpanded = false
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        } else {
                            Button("Show \(settledSessions.count) settled \(settledSessions.count == 1 ? "session" : "sessions")") {
                                settledSessionsExpanded = true
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } header: {
                        Label("Settled", systemImage: "checkmark.circle")
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $filter, prompt: "Search agents, projects, and sessions")

            Divider()

            HStack(spacing: 8) {
                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .background(isSettingsSelected ? Color.primary.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if hasActionableUpdate {
                    Button(action: onOpenUpdates) {
                        Text(updateButtonTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SidebarUpdateButtonAppearance.foreground)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                SidebarUpdateButtonAppearance.background,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .accessibilityLabel(updateButtonAccessibilityLabel)
                    .help(updateButtonAccessibilityLabel)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .navigationTitle("GrokBuild")
        .alert("Rename Session", isPresented: renameAlertPresented) {
            TextField("Session name", text: $renameText)
            Button("Cancel", role: .cancel) {
                renamingSessionID = nil
            }
            Button("Save") {
                if let id = renamingSessionID {
                    onRenameSession(id, renameText)
                }
                renamingSessionID = nil
            }
        }
    }

    private var renameAlertPresented: Binding<Bool> {
        Binding(
            get: { renamingSessionID != nil },
            set: { if !$0 { renamingSessionID = nil } }
        )
    }

    private func toggleSessionVisibility(for workspaceID: Workspace.ID) {
        if hiddenSessionWorkspaceIDs.contains(workspaceID) {
            hiddenSessionWorkspaceIDs.remove(workspaceID)
        } else {
            hiddenSessionWorkspaceIDs.insert(workspaceID)
        }
        onSessionDisclosureChanged()
    }

    private func specialistAgentRow(_ agent: SpecialistAgent) -> some View {
        let isWorking = agentWorkingIDs.contains(agent.id)
        return AgentSidebarRow(
            agent: agent,
            isSelected: selectedSpecialistAgentID == agent.id,
            isWorking: isWorking,
            onSelect: { onSelectSpecialistAgent(agent) }
        )
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .listRowBackground(Color.clear)
        .contextMenu {
            Button("Start session") { onStartSpecialistAgentSession(agent) }
            if openableLastSessionAgentIDs.contains(agent.id) {
                Button("Open last session") { onOpenLastSpecialistSession(agent) }
            }
            if agent.isPinned {
                Button("Unpin Agent") { onToggleSpecialistAgentPin(agent) }
            } else {
                Button("Pin Agent") { onToggleSpecialistAgentPin(agent) }
            }
            Button("Edit") { onEditSpecialistAgent(agent) }
            Button("Duplicate") { onDuplicateSpecialistAgent(agent) }
            Divider()
            Button("Delete", role: .destructive) { onDeleteSpecialistAgent(agent) }
        }
        .accessibilityLabel(agentRowAccessibilityLabel(agent, isWorking: isWorking))
        .accessibilityHint(agent.mission)
    }

    private func sessionRow(_ session: SidebarSession, showsProject: Bool = false) -> some View {
        SessionSidebarRow(
            session: session,
            isSelected: selectedSessionID == session.id,
            projectName: showsProject ? workspaceName(for: session.workspaceID) : nil,
            onSelect: { onSelectSession(session.id) }
        )
        .listRowInsets(EdgeInsets(top: 2, leading: showsProject ? 8 : 18, bottom: 2, trailing: 10))
        .listRowBackground(Color.clear)
        .contextMenu {
            Button("Rename…") {
                renamingSessionID = session.id
                renameText = session.title
            }
            if session.isPinned {
                Button("Unpin Session") { onUnpinSession(session.id) }
            } else {
                Button("Pin Session") { onPinSession(session.id) }
            }
            if settledSessionIDs.contains(session.id) {
                Button("Return to Active") { onUnsettleSession(session.id) }
            } else if SidebarPresentation.canSettle(session.status) {
                Button("Settle Session") { onSettleSession(session.id) }
            }
            if session.status == .finishedUnread {
                Button("Mark as Read") { onMarkSessionRead(session.id) }
            } else {
                Button("Mark as Unread") { onMarkSessionUnread(session.id) }
            }
            Button("Duplicate Session") { onDuplicateSession(session.id) }
            Divider()
            Button("Clear Transcript", role: .destructive) {
                onClearSessionTranscript(session.id)
            }
            Button("Close Session", role: .destructive) {
                onCloseSession(session.id)
            }
        }
    }

    @ViewBuilder
    private func projectContextMenu(for ws: Workspace) -> some View {
        Button("New Session") {
            onNewSessionForWorkspace(ws)
        }

        if pinnedWorkspaceIDs.contains(ws.id) {
            Button("Unpin") {
                onUnpinWorkspace(ws)
            }
        } else {
            Button("Pin to Top") {
                onPinWorkspace(ws)
            }
            .disabled(pinnedWorkspaceIDs.count >= SessionLayoutStore.maxPinnedProjects)
        }

        Button("Branches & Worktrees…") {
            onSwitchBranch(ws)
        }

        Button("New Worktree Session…") {
            onCreateWorktree(ws)
        }

        Divider()

        Button("Remove Project", role: .destructive) {
            onRemoveWorkspace(ws)
        }
    }

    private var finderURL: URL {
        URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    }

    @ViewBuilder
    private func openProjectButton(
        title: String,
        appURL: URL,
        projectURL: URL,
        fallbackSystemImage: String,
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            if let action {
                action()
            } else {
                open(projectURL, with: appURL)
            }
        } label: {
            Label {
                Text(title)
            } icon: {
                appIcon(for: appURL, fallbackSystemImage: fallbackSystemImage)
            }
        }
    }

    private func appIcon(for appURL: URL, fallbackSystemImage: String) -> Image {
        if FileManager.default.fileExists(atPath: appURL.path) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 16, height: 16)
            return Image(nsImage: icon)
        }
        return Image(systemName: fallbackSystemImage)
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

    private func open(_ url: URL, with applicationURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration)
    }

    private func agentRowAccessibilityLabel(_ agent: SpecialistAgent, isWorking: Bool) -> String {
        let status = SpecialistAgentRoster.statusLabel(isWorking: isWorking)
        return agent.isPinned ? "\(agent.name), \(status), Pinned" : "\(agent.name), \(status)"
    }
}

private struct AgentSidebarRow: View {
    let agent: SpecialistAgent
    let isSelected: Bool
    let isWorking: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: agent.glyph)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SpecialistAgentRoster.color(from: agent.color))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(SpecialistAgentRoster.color(from: agent.color).opacity(0.16))
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.name)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(SpecialistAgentRoster.statusLabel(isWorking: isWorking))
                        .font(.caption2)
                        .foregroundStyle(isWorking ? Color.blue : Color.secondary.opacity(0.7))
                        .accessibilityHidden(true)
                }
                Spacer()
                if agent.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.primary.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .help(agent.mission)
    }
}

private struct SessionSidebarRow: View {
    let session: SidebarSession
    let isSelected: Bool
    var projectName: String?
    var onSelect: () -> Void
    @AppStorage(GrokSettingsKeys.privacyMode) private var privacyMode = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .opacity(isSelected ? 1 : 0)
                }
                .frame(width: 10)

                if session.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Pinned")
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(PrivacyMode.redactLabel(session.title, placeholder: "Session", enabled: privacyMode))
                            .font(.callout.weight(isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                        if !session.specialistName.isEmpty {
                            HStack(spacing: 3) {
                                if !session.specialistGlyph.isEmpty {
                                    Image(systemName: session.specialistGlyph)
                                        .font(.system(size: 8, weight: .semibold))
                                }
                                Text(session.specialistName)
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .accessibilityLabel("Agent \(session.specialistName)")
                        } else if !session.roleName.isEmpty {
                            Text(session.roleName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .accessibilityLabel("Role \(session.roleName)")
                        }
                    }
                    if let projectName {
                        Text(PrivacyMode.redactLabel(projectName, placeholder: "Project", enabled: privacyMode))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                if session.isWorktree {
                    Text("WT")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                        .accessibilityLabel("Worktree")
                }
                Spacer()
                statusBadge
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.primary.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if session.status == .working {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                statusBadgeLabel(now: context.date)
            }
        } else {
            statusBadgeLabel(now: Date())
        }
    }

    @ViewBuilder
    private func statusBadgeLabel(now: Date) -> some View {
        if let label = SidebarPresentation.statusLabel(
            for: session.status,
            workingSince: session.workingSince,
            now: now
        ) {
            HStack(spacing: 3) {
                Image(systemName: session.status.symbolName)
                    .font(.system(size: 8, weight: .semibold))
                Text(label)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(statusColor)
            .accessibilityLabel(label)
            .help(label)
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .idle: .secondary
        case .working: .blue
        case .needsInput: .orange
        case .finishedUnread: .green
        case .error: .red
        }
    }
}

private struct WorkspaceRow: View {
    let workspace: Workspace
    var isPinned: Bool = false
    var isSelected: Bool = false
    var isWorktree: Bool = false
    var hasSessions: Bool = false
    var areSessionsHidden: Bool = false
    var onToggleSessions: () -> Void = {}
    @AppStorage(GrokSettingsKeys.privacyMode) private var privacyMode = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isPinned ? "pin.fill" : "folder")
                .foregroundStyle(isPinned ? .orange : .secondary)
            HStack(spacing: 6) {
                Text(PrivacyMode.redactLabel(workspace.displayName, placeholder: "Project", enabled: privacyMode))
                    .font(isSelected ? .body.weight(.semibold) : .body)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                if isWorktree {
                    Text("WT")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                        .accessibilityLabel("Worktree")
                }
                if hasSessions {
                    Image(systemName: areSessionsHidden ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 3)
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            TapGesture().onEnded {
                                onToggleSessions()
                            }
                        )
                        .help(areSessionsHidden ? "Show sessions" : "Hide sessions")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            isSelected ? Color.primary.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .help(pathHelp)
        .accessibilityHint(pathHelp)
    }

    private var pathHelp: String {
        PrivacyMode.redactPath(workspace.path.path, enabled: privacyMode)
    }
}

private struct WorkspaceBranchCaption: View {
    let branch: String
    @AppStorage(GrokSettingsKeys.privacyMode) private var privacyMode = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .accessibilityHidden(true)
            Text(privacyMode ? "Branch" : branch)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
        .help("Branches & Worktrees…")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(privacyMode ? "Git branch" : "Git branch \(branch)")
    }
}
