import SwiftUI
import Foundation  // for FileManager, URL in AGENTS.md check

struct SidebarView: View {
    @Binding var workspaces: [Workspace]
    @Binding var selectedWorkspaceID: Workspace.ID?

    var onAddWorkspace: () -> Void
    var onSelectWorkspace: (Workspace) -> Void
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
            List(selection: $selectedWorkspaceID) {
                Section {
                    ForEach(filtered) { ws in
                        WorkspaceRow(workspace: ws)
                            .tag(ws.id)
                            .contextMenu {
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([ws.path])
                                }
                                Button("Remove", role: .destructive) {
                                    workspaces.removeAll { $0.id == ws.id }
                                }
                            }
                    }

                    Button(action: onAddWorkspace) {
                        Label("Add Project…", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
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


