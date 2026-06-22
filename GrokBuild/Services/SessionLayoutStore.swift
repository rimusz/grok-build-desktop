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

    var selectedSessionIDByWorkspace: [UUID: UUID]

    init(
        records: [SavedSessionRecord],
        sessionOrderByWorkspace: [UUID: [UUID]],
        selectedSessionID: UUID?,
        selectedWorkspaceID: UUID?,
        selectedSessionIDByWorkspace: [UUID: UUID] = [:]
    ) {
        self.records = records
        self.sessionOrderByWorkspace = sessionOrderByWorkspace
        self.selectedSessionID = selectedSessionID
        self.selectedWorkspaceID = selectedWorkspaceID
        self.selectedSessionIDByWorkspace = selectedSessionIDByWorkspace
    }

    private enum CodingKeys: String, CodingKey {
        case records
        case sessionOrderByWorkspace
        case selectedSessionID
        case selectedWorkspaceID
        case selectedSessionIDByWorkspace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = try container.decode([SavedSessionRecord].self, forKey: .records)
        sessionOrderByWorkspace = try container.decode([UUID: [UUID]].self, forKey: .sessionOrderByWorkspace)
        selectedSessionID = try container.decodeIfPresent(UUID.self, forKey: .selectedSessionID)
        selectedWorkspaceID = try container.decodeIfPresent(UUID.self, forKey: .selectedWorkspaceID)
        selectedSessionIDByWorkspace = try container.decodeIfPresent([UUID: UUID].self, forKey: .selectedSessionIDByWorkspace) ?? [:]
    }
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
