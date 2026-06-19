import SwiftUI

struct ContentView: View {
    @State private var workspaceStore = WorkspaceStore()
    @State private var chatStore = ChatStore()
    @State private var selectedWorkspaceID: Workspace.ID?

    @State private var showPicker = false
    @State private var previewMessageID: UUID?
    @State private var previewDiffs: [ChatStore.DetectedDiff] = []

    var body: some View {
        NavigationSplitView {
            SidebarView(
                workspaces: $workspaceStore.workspaces,
                selectedWorkspaceID: $selectedWorkspaceID,
                onAddWorkspace: { showPicker = true },
                onSelectWorkspace: { ws in
                    Task { await chatStore.setWorkspace(ws) }
                    workspaceStore.moveToTop(ws)
                }
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
        } detail: {
            HStack(spacing: 0) {
                ChatView(store: chatStore)
                    .frame(maxWidth: .infinity)

                Divider()

                PreviewPane(
                    message: previewMessage,
                    diffs: previewDiffs,
                    workspace: chatStore.currentWorkspace,
                    onApply: { msg in applyDiffs(from: msg) },
                    onApplySingle: { diff in applySingle(diff) }
                )
                .frame(width: 380)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                workspaceMenu
            }
            // (Agent / Persona picker removed - see Grok Build's AGENTS.md, skills & sub-agents)
            // (Terminate button removed per request - use stop in chat input instead)
        }
        .onAppear(perform: bootstrap)
        .sheet(isPresented: $showPicker) {
            WorkspacePicker { url in
                addWorkspace(url: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chooseWorkspaceRequested)) { _ in
            showPicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopGenerationRequested)) { _ in
            chatStore.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusInputRequested)) { _ in
            // handled inside ChatView via focus
        }
        .onChange(of: selectedWorkspaceID) { _, newID in
            handleWorkspaceChange(newID)
        }
        .onChange(of: chatStore.messages) { _, _ in
            autoSelectLatestDiffMessage()
        }
        // Menu bar quick actions (popover mode)
        .onReceive(NotificationCenter.default.publisher(for: .newSessionRequested)) { _ in
            chatStore.clearMessages()
        }
    }

    // MARK: - Subviews

    private var workspaceMenu: some View {
        Menu {
            ForEach(workspaceStore.workspaces) { ws in
                Button {
                    selectedWorkspaceID = ws.id
                } label: {
                    Label(ws.displayName, systemImage: "folder")
                }
            }
            Divider()
            Button("Choose Folder…", systemImage: "folder.badge.plus") {
                showPicker = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                Text(currentWorkspaceName)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var currentWorkspaceName: String {
        if let id = selectedWorkspaceID,
           let ws = workspaceStore.workspaces.first(where: { $0.id == id }) {
            return ws.displayName
        }
        return "No Workspace"
    }

    private var previewMessage: Message? {
        guard let id = previewMessageID else { return nil }
        return chatStore.messages.first { $0.id == id }
    }

    // MARK: - Logic

    private func bootstrap() {
        // Restore or seed workspaces
        if let first = workspaceStore.workspaces.first {
            selectedWorkspaceID = first.id
            Task { await chatStore.setWorkspace(first) }
        }

    }

    private func addWorkspace(url: URL) {
        let ws = Workspace(name: url.lastPathComponent, path: url)
        workspaceStore.add(ws)
        selectedWorkspaceID = ws.id
        Task {
            await chatStore.setWorkspace(ws)
        }
    }

    private func autoSelectLatestDiffMessage() {
        if let last = chatStore.messages.last(where: { $0.role == .assistant && $0.hasDiff }) {
            if previewMessageID != last.id {
                previewMessageID = last.id
                previewDiffs = chatStore.detectedDiffs(in: last)
            }
        }
    }

    private func applyDiffs(from message: Message) {
        guard let ws = chatStore.currentWorkspace else { return }
        _ = chatStore.applyDiffs(from: message, workspace: ws)
    }

    private func applySingle(_ diff: ChatStore.DetectedDiff) {
        guard let ws = chatStore.currentWorkspace else { return }

        // Apply only one diff by temporarily synthesizing a message with just that diff
        let single = Message(role: .assistant, content: "```diff\n\(diff.raw)\n```")
        _ = chatStore.applyDiffs(from: single, workspace: ws)
    }

    private func handleWorkspaceChange(_ newID: Workspace.ID?) {
        if let id = newID,
           let ws = workspaceStore.workspaces.first(where: { $0.id == id }) {
            Task { await chatStore.setWorkspace(ws) }
        }
    }

    // (handleAgentChange removed)
}

extension Notification.Name {
    static let chooseWorkspaceRequested = Notification.Name("chooseWorkspaceRequested")
    static let stopGenerationRequested = Notification.Name("stopGenerationRequested")
    static let focusInputRequested = Notification.Name("focusInputRequested")
    static let showMainWindowRequested = Notification.Name("showMainWindowRequested")
    static let newSessionRequested = Notification.Name("newSessionRequested")
    static let grokStatusChanged = Notification.Name("grokStatusChanged")
}
