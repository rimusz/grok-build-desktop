import Foundation
import SwiftUI

/// Persists a list of recent projects across launches.
@Observable
@MainActor
final class WorkspaceStore {
    var workspaces: [Workspace] = []
    private(set) var pinnedWorkspaceIDs: [UUID] = []
    private var workspaceOrder: [UUID] = []

    private let storageKey = "GrokBuild.projects.v1"

    init() {
        load()
        let layout = SessionLayoutStore.loadWorkspaceLayout()
        pinnedWorkspaceIDs = layout.pinnedWorkspaceIDs
        workspaceOrder = layout.workspaceOrder
        normalizeLayout()
    }

    var orderedWorkspaces: [Workspace] {
        let pinned = pinnedWorkspaceIDs.compactMap { id in workspaces.first { $0.id == id } }
        let unpinnedIDs = workspaceOrder.filter { !pinnedWorkspaceIDs.contains($0) }
        var unpinned = unpinnedIDs.compactMap { id in workspaces.first { $0.id == id } }
        for ws in workspaces where !pinnedWorkspaceIDs.contains(ws.id) && !unpinnedIDs.contains(ws.id) {
            unpinned.append(ws)
        }
        return pinned + unpinned
    }

    func isPinned(_ workspace: Workspace) -> Bool {
        pinnedWorkspaceIDs.contains(workspace.id)
    }

    func add(_ ws: Workspace) {
        if let existing = workspaces.first(where: {
            $0.path.resolvingSymlinksInPath() == ws.path.resolvingSymlinksInPath()
        }) {
            workspaces.removeAll { $0.id == existing.id }
            workspaces.append(existing)
            if !workspaceOrder.contains(existing.id) {
                workspaceOrder.insert(existing.id, at: 0)
            }
        } else {
            workspaces.insert(ws, at: 0)
            workspaceOrder.removeAll { $0 == ws.id }
            workspaceOrder.insert(ws.id, at: 0)
        }
        normalizeLayout()
        save()
    }

    func remove(_ ws: Workspace) {
        workspaces.removeAll { $0.id == ws.id }
        workspaceOrder.removeAll { $0 == ws.id }
        pinnedWorkspaceIDs.removeAll { $0 == ws.id }
        SessionLayoutStore.removeAgentSettings(for: ws.id)
        normalizeLayout()
        save()
    }

    func moveToTop(_ ws: Workspace) {
        workspaceOrder.removeAll { $0 == ws.id }
        if pinnedWorkspaceIDs.contains(ws.id) {
            pinnedWorkspaceIDs.removeAll { $0 == ws.id }
            pinnedWorkspaceIDs.insert(ws.id, at: 0)
        } else {
            workspaceOrder.insert(ws.id, at: 0)
        }
        saveLayout()
    }

    func pin(_ workspace: Workspace) {
        guard !pinnedWorkspaceIDs.contains(workspace.id) else { return }
        if pinnedWorkspaceIDs.count >= SessionLayoutStore.maxPinnedProjects {
            pinnedWorkspaceIDs.removeLast()
        }
        workspaceOrder.removeAll { $0 == workspace.id }
        pinnedWorkspaceIDs.removeAll { $0 == workspace.id }
        pinnedWorkspaceIDs.insert(workspace.id, at: 0)
        saveLayout()
    }

    func unpin(_ workspace: Workspace) {
        guard pinnedWorkspaceIDs.contains(workspace.id) else { return }
        pinnedWorkspaceIDs.removeAll { $0 == workspace.id }
        workspaceOrder.removeAll { $0 == workspace.id }
        workspaceOrder.insert(workspace.id, at: 0)
        saveLayout()
    }

    func moveWorkspaces(from source: IndexSet, to destination: Int) {
        var ordered = orderedWorkspaces
        ordered.move(fromOffsets: source, toOffset: destination)
        pinnedWorkspaceIDs = ordered.filter { pinnedWorkspaceIDs.contains($0.id) }.map(\.id)
        workspaceOrder = ordered.filter { !pinnedWorkspaceIDs.contains($0.id) }.map(\.id)
        saveLayout()
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([Workspace].self, from: data) {
            let valid = decoded.filter { Self.isExistingDirectory($0.path) }
            workspaces = valid
            if valid.count != decoded.count {
                normalizeLayout()
                save()
            }
        }
    }

    private static func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func save() {
        if let data = try? JSONEncoder().encode(workspaces) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        saveLayout()
    }

    private func saveLayout() {
        SessionLayoutStore.saveWorkspaceLayout(
            WorkspaceLayoutSnapshot(
                pinnedWorkspaceIDs: pinnedWorkspaceIDs,
                workspaceOrder: workspaceOrder
            )
        )
    }

    private func normalizeLayout() {
        workspaceOrder.removeAll { id in !workspaces.contains { $0.id == id } }
        pinnedWorkspaceIDs.removeAll { id in !workspaces.contains { $0.id == id } }
        for ws in workspaces where !workspaceOrder.contains(ws.id) && !pinnedWorkspaceIDs.contains(ws.id) {
            workspaceOrder.append(ws.id)
        }
        if pinnedWorkspaceIDs.count > SessionLayoutStore.maxPinnedProjects {
            pinnedWorkspaceIDs = Array(pinnedWorkspaceIDs.prefix(SessionLayoutStore.maxPinnedProjects))
        }
    }
}
