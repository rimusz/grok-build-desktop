import Foundation
import SwiftUI

/// Persists a list of recent workspaces across launches.
@Observable
final class WorkspaceStore {
    var workspaces: [Workspace] = []
    private let storageKey = "GrokDeck.workspaces.v1"

    init() {
        load()
        if workspaces.isEmpty {
            // Seed a reasonable default
            let dev = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Developer", isDirectory: true)
            try? FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
            workspaces = [Workspace(name: "Developer", path: dev)]
        }
    }

    func add(_ ws: Workspace) {
        if !workspaces.contains(where: { $0.path.resolvingSymlinksInPath() == ws.path.resolvingSymlinksInPath() }) {
            workspaces.insert(ws, at: 0)
        } else {
            // Move to top
            workspaces.removeAll { $0.path.resolvingSymlinksInPath() == ws.path.resolvingSymlinksInPath() }
            workspaces.insert(ws, at: 0)
        }
        save()
    }

    func remove(_ ws: Workspace) {
        workspaces.removeAll { $0.id == ws.id }
        save()
    }

    func moveToTop(_ ws: Workspace) {
        if let idx = workspaces.firstIndex(where: { $0.id == ws.id }) {
            let item = workspaces.remove(at: idx)
            workspaces.insert(item, at: 0)
            save()
        }
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([Workspace].self, from: data) {
            workspaces = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(workspaces) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
