import SwiftUI
import Foundation  // for FileManager, URL in AGENTS.md check
import AppKit

struct SidebarSession: Identifiable, Hashable {
    let id: UUID
    let title: String
    let projectName: String
    let isRunning: Bool
}

struct SidebarView: View {
    @Binding var workspaces: [Workspace]
    @Binding var selectedWorkspaceID: Workspace.ID?
    var sessions: [SidebarSession] = []
    var selectedSessionID: UUID?

    var onAddWorkspace: () -> Void
    var onSelectWorkspace: (Workspace) -> Void
    var onSelectSession: (UUID) -> Void = { _ in }
    var onSwitchBranch: (Workspace) -> Void = { _ in }
    var onCreateWorktree: (Workspace) -> Void = { _ in }
    var onOpenSettings: () -> Void
    var isSettingsSelected: Bool = false

    @State private var filter = ""

    private var filtered: [Workspace] {
        filter.isEmpty ? workspaces : workspaces.filter {
            $0.displayName.localizedCaseInsensitiveContains(filter)
        }
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

            List(selection: $selectedWorkspaceID) {
                Section {
                    ForEach(filtered) { ws in
                        WorkspaceRow(workspace: ws)
                            .tag(ws.id)
                            .contextMenu {
                                Menu("Open in") {
                                    Button("Finder") {
                                        NSWorkspace.shared.open(ws.path)
                                    }

                                    if let app = installedApp(named: "VS Code", bundleIdentifiers: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]) {
                                        Button("VS Code") {
                                            open(ws.path, with: app)
                                        }
                                    }

                                    if let app = installedApp(named: "Cursor", bundleIdentifiers: ["com.todesktop.230313mzl4w4u92", "com.cursor.Cursor"]) {
                                        Button("Cursor") {
                                            open(ws.path, with: app)
                                        }
                                    }

                                    Button("Terminal") {
                                        if let app = installedApp(named: "Terminal", bundleIdentifiers: ["com.apple.Terminal"]) {
                                            open(ws.path, with: app)
                                        }
                                    }

                                    if let app = installedApp(named: "iTerm", bundleIdentifiers: ["com.googlecode.iterm2"]) {
                                        Button("iTerm") {
                                            open(ws.path, with: app)
                                        }
                                    }
                                }

                                Divider()

                                Button("Switch Branch…") {
                                    onSwitchBranch(ws)
                                }

                                Button("New Worktree…") {
                                    onCreateWorktree(ws)
                                }

                                Divider()

                                Button("Remove", role: .destructive) {
                                    workspaces.removeAll { $0.id == ws.id }
                                }
                            }
                    }

                } header: {
                    Label("Projects", systemImage: "folder")
                }

                // Grok Build native: project AGENTS.md (and CLAUDE.md etc.) are auto-loaded by the CLI.
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

                if !sessions.isEmpty {
                    Section {
                        ForEach(sessions) { session in
                            Button {
                                onSelectSession(session.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: session.isRunning ? "circle.fill" : "circle")
                                        .font(.system(size: 7))
                                        .foregroundStyle(session.isRunning ? .blue : .secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(session.title)
                                        Text(session.projectName)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedSessionID == session.id {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Label("Live Sessions", systemImage: "bubble.left.and.bubble.right")
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
    }

    private func installedApp(named _: String, bundleIdentifiers: [String]) -> URL? {
        bundleIdentifiers.lazy.compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }.first
    }

    private func open(_ url: URL, with applicationURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration)
    }
}

private struct WorkspaceRow: View {
    let workspace: Workspace

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(workspace.displayName)
                    .font(.body)
                Text(workspace.path.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }
}


