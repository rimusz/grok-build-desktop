import Foundation

struct SavedSessionRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let workspaceID: UUID
    var grokSessionID: String?
    var title: String?
    /// Per-tab model id; matches grok `session/set_model` for this tab's process.
    var model: String?
    /// Per-tab session-agent selection id (see `GrokAgentProfiles`). `nil` means the tab has no
    /// explicit override and follows the global default (`grokbuild.selectedAgent`).
    var agent: String?
    var lastAccessed: Date

    init(
        id: UUID,
        workspaceID: UUID,
        grokSessionID: String? = nil,
        title: String? = nil,
        model: String? = nil,
        agent: String? = nil,
        lastAccessed: Date
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.grokSessionID = grokSessionID
        self.title = title
        self.model = model
        self.agent = agent
        self.lastAccessed = lastAccessed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workspaceID = try container.decode(UUID.self, forKey: .workspaceID)
        grokSessionID = try container.decodeIfPresent(String.self, forKey: .grokSessionID)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        agent = try container.decodeIfPresent(String.self, forKey: .agent)
        lastAccessed = try container.decode(Date.self, forKey: .lastAccessed)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case workspaceID
        case grokSessionID
        case title
        case model
        case agent
        case lastAccessed
    }
}

enum SessionTabModelPolicy {
    /// Pick the model for a tab: saved tab value, then project default for new tabs, then app default.
    static func resolvedModel(
        tabModel: String?,
        workspaceDefault: String?,
        appDefault: String
    ) -> String {
        for candidate in [tabModel, workspaceDefault, appDefault] {
            if let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !candidate.isEmpty {
                return candidate
            }
        }
        return appDefault
    }
}

struct SessionLayoutSnapshot: Codable {
    var records: [SavedSessionRecord]
    var sessionOrderByWorkspace: [UUID: [UUID]]
    var selectedSessionID: UUID?
    var selectedWorkspaceID: UUID?

    var selectedSessionIDByWorkspace: [UUID: UUID]
    var expandedSessionWorkspaceIDs: Set<UUID>
    var hiddenSessionWorkspaceIDs: Set<UUID>
    /// Session tab IDs shown in the global Pinned section, in display order.
    var pinnedSessionIDs: [UUID]
    /// Sessions parked in the global Settled shelf instead of their project group.
    var settledSessionIDs: Set<UUID>

    init(
        records: [SavedSessionRecord],
        sessionOrderByWorkspace: [UUID: [UUID]],
        selectedSessionID: UUID?,
        selectedWorkspaceID: UUID?,
        selectedSessionIDByWorkspace: [UUID: UUID] = [:],
        expandedSessionWorkspaceIDs: Set<UUID> = [],
        hiddenSessionWorkspaceIDs: Set<UUID> = [],
        pinnedSessionIDs: [UUID] = [],
        settledSessionIDs: Set<UUID> = []
    ) {
        self.records = records
        self.sessionOrderByWorkspace = sessionOrderByWorkspace
        self.selectedSessionID = selectedSessionID
        self.selectedWorkspaceID = selectedWorkspaceID
        self.selectedSessionIDByWorkspace = selectedSessionIDByWorkspace
        self.expandedSessionWorkspaceIDs = expandedSessionWorkspaceIDs
        self.hiddenSessionWorkspaceIDs = hiddenSessionWorkspaceIDs
        self.pinnedSessionIDs = pinnedSessionIDs
        self.settledSessionIDs = settledSessionIDs
    }

    private enum CodingKeys: String, CodingKey {
        case records
        case sessionOrderByWorkspace
        case selectedSessionID
        case selectedWorkspaceID
        case selectedSessionIDByWorkspace
        case expandedSessionWorkspaceIDs
        case hiddenSessionWorkspaceIDs
        case pinnedSessionIDs
        case settledSessionIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = try container.decode([SavedSessionRecord].self, forKey: .records)
        sessionOrderByWorkspace = try container.decode([UUID: [UUID]].self, forKey: .sessionOrderByWorkspace)
        selectedSessionID = try container.decodeIfPresent(UUID.self, forKey: .selectedSessionID)
        selectedWorkspaceID = try container.decodeIfPresent(UUID.self, forKey: .selectedWorkspaceID)
        selectedSessionIDByWorkspace = try container.decodeIfPresent([UUID: UUID].self, forKey: .selectedSessionIDByWorkspace) ?? [:]
        expandedSessionWorkspaceIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .expandedSessionWorkspaceIDs) ?? []
        hiddenSessionWorkspaceIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .hiddenSessionWorkspaceIDs) ?? []
        pinnedSessionIDs = try container.decodeIfPresent([UUID].self, forKey: .pinnedSessionIDs) ?? []
        settledSessionIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .settledSessionIDs) ?? []
    }
}

struct WorkspaceLayoutSnapshot: Codable {
    var pinnedWorkspaceIDs: [UUID]
    var workspaceOrder: [UUID]
    var agentSettingsByWorkspace: [UUID: WorkspaceAgentSettings]

    init(
        pinnedWorkspaceIDs: [UUID],
        workspaceOrder: [UUID],
        agentSettingsByWorkspace: [UUID: WorkspaceAgentSettings] = [:]
    ) {
        self.pinnedWorkspaceIDs = pinnedWorkspaceIDs
        self.workspaceOrder = workspaceOrder
        self.agentSettingsByWorkspace = agentSettingsByWorkspace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pinnedWorkspaceIDs = try container.decode([UUID].self, forKey: .pinnedWorkspaceIDs)
        workspaceOrder = try container.decode([UUID].self, forKey: .workspaceOrder)
        agentSettingsByWorkspace = try container.decodeIfPresent([UUID: WorkspaceAgentSettings].self, forKey: .agentSettingsByWorkspace) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case pinnedWorkspaceIDs
        case workspaceOrder
        case agentSettingsByWorkspace
    }
}

struct WorkspaceAgentSettings: Codable, Hashable {
    var model: String?
    var reasoningEffort: String?
}

enum SessionLayoutStore {
    static let maxSidebarSessions = 10
    static let maxPinnedProjects = 5
    static let maxPinnedSessions = 20
    private static let sessionKey = "GrokBuild.sessionLayout.v2"
    private static let workspaceLayoutKey = "GrokBuild.workspaceLayout.v1"

    static func normalizedSessionShelves(
        pinnedSessionIDs: [UUID],
        settledSessionIDs: Set<UUID>,
        validSessionIDs: Set<UUID>
    ) -> (pinned: [UUID], settled: Set<UUID>) {
        var seenPinnedIDs: Set<UUID> = []
        let pinned = Array(
            pinnedSessionIDs
                .filter { validSessionIDs.contains($0) && seenPinnedIDs.insert($0).inserted }
                .prefix(maxPinnedSessions)
        )
        let settled = settledSessionIDs
            .intersection(validSessionIDs)
            .subtracting(pinned)
        return (pinned, settled)
    }

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

    static func agentSettings(for workspaceID: UUID) -> WorkspaceAgentSettings {
        loadWorkspaceLayout().agentSettingsByWorkspace[workspaceID] ?? WorkspaceAgentSettings()
    }

    static func saveAgentSettings(_ settings: WorkspaceAgentSettings, for workspaceID: UUID) {
        var layout = loadWorkspaceLayout()
        layout.agentSettingsByWorkspace[workspaceID] = settings
        saveWorkspaceLayout(layout)
    }

    static func removeAgentSettings(for workspaceID: UUID) {
        var layout = loadWorkspaceLayout()
        layout.agentSettingsByWorkspace.removeValue(forKey: workspaceID)
        saveWorkspaceLayout(layout)
    }
}
