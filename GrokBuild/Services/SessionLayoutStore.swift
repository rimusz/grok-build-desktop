import Foundation

struct SavedSessionRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let workspaceID: UUID
    var grokSessionID: String?
    var title: String?
    var lastAccessed: Date
}

struct SessionLayoutSnapshot: Codable {
    var records: [SavedSessionRecord]
    var sessionOrderByWorkspace: [UUID: [UUID]]
    var selectedSessionID: UUID?
    var selectedWorkspaceID: UUID?
}

struct WorkspaceLayoutSnapshot: Codable {
    var pinnedWorkspaceIDs: [UUID]
    var workspaceOrder: [UUID]
}

enum SessionLayoutStore {
    static let maxSidebarSessions = 10
    static let maxPinnedProjects = 5
    private static let sessionKey = "GrokBuild.sessionLayout.v2"
    private static let workspaceLayoutKey = "GrokBuild.workspaceLayout.v1"

    static func loadSessions() -> SessionLayoutSnapshot {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let decoded = try? JSONDecoder().decode(SessionLayoutSnapshot.self, from: data) else {
            return SessionLayoutSnapshot(records: [], sessionOrderByWorkspace: [:], selectedSessionID: nil, selectedWorkspaceID: nil)
        }
        return decoded
    }

    static func saveSessions(_ snapshot: SessionLayoutSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    static func loadWorkspaceLayout() -> WorkspaceLayoutSnapshot {
        guard let data = UserDefaults.standard.data(forKey: workspaceLayoutKey),
              let decoded = try? JSONDecoder().decode(WorkspaceLayoutSnapshot.self, from: data) else {
            return WorkspaceLayoutSnapshot(pinnedWorkspaceIDs: [], workspaceOrder: [])
        }
        return decoded
    }

    static func saveWorkspaceLayout(_ snapshot: WorkspaceLayoutSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: workspaceLayoutKey)
        }
    }
}
