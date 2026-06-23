import SwiftUI
import Foundation  // for FileManager, URL in AGENTS.md check
import AppKit

struct SidebarSession: Identifiable, Hashable {
    let id: UUID
    let workspaceID: Workspace.ID
    let title: String
    let isRunning: Bool
}

struct SidebarView: View {
    @Binding var workspaces: [Workspace]
    var orderedWorkspaces: [Workspace]
    var pinnedWorkspaceIDs: [UUID]
    @Binding var selectedWorkspaceID: Workspace.ID?
    var sessions: [SidebarSession] = []
    var hiddenSessionCounts: [Workspace.ID: Int] = [:]
    var selectedSessionID: UUID?

    var onAddWorkspace: () -> Void
    var onSelectWorkspace: (Workspace) -> Void
    var onSelectSession: (UUID) -> Void = { _ in }
    var onNewSessionForWorkspace: (Workspace) -> Void = { _ in }
    var onRenameSession: (UUID, String) -> Void = { _, _ in }
    var onCloseSession: (UUID) -> Void = { _ in }
    var onMoveWorkspace: (IndexSet, Int) -> Void = { _, _ in }
    var onPinWorkspace: (Workspace) -> Void = { _ in }
    var onUnpinWorkspace: (Workspace) -> Void = { _ in }
    var onRemoveWorkspace: (Workspace) -> Void = { _ in }
    var onMoveSession: (Workspace.ID, IndexSet, Int) -> Void = { _, _, _ in }
    var onSwitchBranch: (Workspace) -> Void = { _ in }
    var onCreateWorktree: (Workspace) -> Void = { _ in }
    var onOpenSettings: () -> Void
    var isSettingsSelected: Bool = false

    @State private var filter = ""
    @State private var renamingSessionID: UUID?
    @State private var renameText = ""
    @State private var expandedSessionWorkspaceIDs: Set<Workspace.ID> = []

    private let collapsedSessionLimit = 5

    private var filtered: [Workspace] {
        let base = filter.isEmpty ? orderedWorkspaces : orderedWorkspaces.filter {
            $0.displayName.localizedCaseInsensitiveContains(filter)
        }
        return base
    }

    private func sessions(for workspaceID: Workspace.ID) -> [SidebarSession] {
        sessions.filter { $0.workspaceID == workspaceID }
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
            HStack(spacing: 8) {
                Button(action: onAddWorkspace) {
                    Label("Add Project", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            List {
                Section {
                    ForEach(filtered) { ws in
                        Button {
                            onSelectWorkspace(ws)
                        } label: {
                            WorkspaceRow(
                                workspace: ws,
                                isPinned: pinnedWorkspaceIDs.contains(ws.id),
                                isSelected: selectedWorkspaceID == ws.id
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            projectContextMenu(for: ws)
                        }

                        let projectSessions = sessions(for: ws.id)
                        if selectedWorkspaceID == ws.id || !projectSessions.isEmpty {
                            let isExpanded = isSessionsExpanded(for: ws.id)
                            let shownSessions = isExpanded ? projectSessions : collapsedSessions(from: projectSessions)

                            if isExpanded {
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
                            if hidden > 0 || isExpanded {
                                HStack(spacing: 6) {
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .font(.caption2.weight(.semibold))
                                    Text(isExpanded ? "Show less" : "Show more")
                                        .font(.caption.weight(.medium))
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
                                }
                                .accessibilityAddTraits(.isButton)
                                .listRowInsets(EdgeInsets(top: 2, leading: 48, bottom: 6, trailing: 10))
                                .listRowBackground(Color.clear)

                                if isExpanded, hidden > 0 {
                                    Text("\(hidden) more in Browse Sessions…")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .listRowInsets(EdgeInsets(top: 0, leading: 48, bottom: 6, trailing: 10))
                                }
                            }
                        }
                    }
                    .onMove { source, destination in
                        guard filter.isEmpty else { return }
                        onMoveWorkspace(source, destination)
                    }

                } header: {
                    Label("Projects", systemImage: "folder")
                }

                if let ws = workspaces.first(where: { $0.id == selectedWorkspaceID }) {
                    let agentsMd = ws.path.appendingPathComponent("AGENTS.md")
                    let claudeMd = ws.path.appendingPathComponent("CLAUDE.md")
                    let file = FileManager.default.fileExists(atPath: agentsMd.path) ? agentsMd
                             : FileManager.default.fileExists(atPath: claudeMd.path) ? claudeMd : nil
                    if let file = file {
                        Section {
                            Button(action: { NSWorkspace.shared.open(file) }) {
                                Label("Open \(file.lastPathComponent)", systemImage: "doc.text")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        } header: {
                            Label("Project Instructions", systemImage: "book")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $filter, prompt: "Filter projects")

            Divider()

            Button(action: onOpenSettings) {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .background(isSettingsSelected ? Color.primary.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
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

    private func sessionRow(_ session: SidebarSession) -> some View {
        SessionSidebarRow(
            session: session,
            isSelected: selectedSessionID == session.id,
            onSelect: { onSelectSession(session.id) }
        )
        .listRowInsets(EdgeInsets(top: 2, leading: 28, bottom: 2, trailing: 10))
        .contextMenu {
            Button("Rename…") {
                renamingSessionID = session.id
                renameText = session.title
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

        Button("New Worktree…") {
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
}

private struct SessionSidebarRow: View {
    let session: SidebarSession
    let isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: session.isRunning ? "circle.fill" : "bubble.left")
                    .font(.system(size: session.isRunning ? 7 : 11))
                    .foregroundStyle(session.isRunning ? .blue : .secondary)
                    .frame(width: 14)
                Text(session.title)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .background(isSelected ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct WorkspaceRow: View {
    let workspace: Workspace
    var isPinned: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isPinned ? "pin.fill" : "folder")
                .foregroundStyle(isPinned ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(workspace.displayName)
                    .font(.body)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Text(workspace.path.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(Color.primary.opacity(0.16))
                    .frame(height: 1)
                    .padding(.leading, 24)
            }
        }
    }
}
