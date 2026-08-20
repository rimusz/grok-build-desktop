import Foundation

/// Higher-level permission preset for a specialist agent.
///
/// Stored as roster metadata only in Milestone 1. Later launch wiring may map
/// `.readOnly` / `.workspaceWrite` onto `GrokLaunchOptions`; `.inherit` keeps
/// the app-wide Settings → Permissions values.
enum SpecialistAgentPermissionProfile: String, Codable, CaseIterable, Sendable {
    case inherit
    case readOnly
    case workspaceWrite
}

/// Errors from specialist-agent validation or Application Support persistence.
enum SpecialistAgentStoreError: Error, Equatable, LocalizedError {
    case invalidAgent(String)
    case duplicateName(String)
    case duplicateIdentity
    case agentNotFound
    case loadFailed
    case persistFailed

    var errorDescription: String? {
        switch self {
        case .invalidAgent(let message):
            return message
        case .duplicateName(let name):
            return "An agent named \"\(name)\" already exists."
        case .duplicateIdentity:
            return "An agent with this id already exists."
        case .agentNotFound:
            return "Agent not found."
        case .loadFailed:
            return "Could not read specialist agents. The file exists but is not valid JSON."
        case .persistFailed:
            return "Could not save specialist agents."
        }
    }
}

/// A durable named specialist-agent identity.
///
/// GrokBuild owns the roster; the `grok` CLI still owns execution. `roleName`,
/// `defaultModel`, `permissionProfile`, browser/Computer Use flags, and
/// `preferredSkills` are persisted preferences — they are not written to
/// `~/.grok/config.toml` by this store.
struct SpecialistAgent: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var mission: String
    /// SF Symbol name used as the roster glyph.
    var glyph: String
    /// Canonical `#RRGGBB` accent.
    var color: String
    /// Optional CLI-facing role / `--agent` id (`SubagentRole.name`).
    var roleName: String?
    /// Optional model id; `nil` means inherit the session / project default.
    var defaultModel: String?
    var permissionProfile: SpecialistAgentPermissionProfile
    /// Preference only — does not enable Settings → Browser.
    var browserEnabled: Bool
    /// Preference only — does not enable Settings → Computer Use.
    var computerUseEnabled: Bool
    /// Soft skill-name preference; not injected into the CLI by this store.
    var preferredSkills: [String]
    let createdAt: Date
    var updatedAt: Date
    /// Last GrokBuild tab / `SavedSessionRecord.id` launched for this agent.
    var lastSessionID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        mission: String,
        glyph: String = "person.fill",
        color: String = "#5E5CE6",
        roleName: String? = nil,
        defaultModel: String? = nil,
        permissionProfile: SpecialistAgentPermissionProfile = .inherit,
        browserEnabled: Bool = false,
        computerUseEnabled: Bool = false,
        preferredSkills: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastSessionID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.mission = mission
        self.glyph = glyph
        self.color = color
        self.roleName = roleName
        self.defaultModel = defaultModel
        self.permissionProfile = permissionProfile
        self.browserEnabled = browserEnabled
        self.computerUseEnabled = computerUseEnabled
        self.preferredSkills = preferredSkills
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSessionID = lastSessionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        mission = try container.decode(String.self, forKey: .mission)
        glyph = try container.decode(String.self, forKey: .glyph)
        color = try container.decode(String.self, forKey: .color)
        roleName = try container.decodeIfPresent(String.self, forKey: .roleName)
        defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel)
        permissionProfile = try container.decodeIfPresent(
            SpecialistAgentPermissionProfile.self,
            forKey: .permissionProfile
        ) ?? .inherit
        browserEnabled = try container.decodeIfPresent(Bool.self, forKey: .browserEnabled) ?? false
        computerUseEnabled = try container.decodeIfPresent(Bool.self, forKey: .computerUseEnabled) ?? false
        preferredSkills = try container.decodeIfPresent([String].self, forKey: .preferredSkills) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastSessionID = try container.decodeIfPresent(UUID.self, forKey: .lastSessionID)
    }

    /// Trimmed, canonical copy used before validation and persist.
    func normalized() -> SpecialistAgent {
        SpecialistAgent(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            mission: mission.trimmingCharacters(in: .whitespacesAndNewlines),
            glyph: glyph.trimmingCharacters(in: .whitespacesAndNewlines),
            color: Self.canonicalizeColor(color) ?? color.trimmingCharacters(in: .whitespacesAndNewlines),
            roleName: Self.nilIfEmpty(roleName),
            defaultModel: Self.nilIfEmpty(defaultModel),
            permissionProfile: permissionProfile,
            browserEnabled: browserEnabled,
            computerUseEnabled: computerUseEnabled,
            preferredSkills: Self.normalizedSkills(preferredSkills),
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastSessionID: lastSessionID
        )
    }

    /// A validation error message, or nil when the entry is well-formed.
    var validationError: String? {
        let agent = normalized()
        if agent.name.isEmpty { return "Name is required." }
        if agent.mission.isEmpty { return "Mission is required." }
        if agent.glyph.isEmpty { return "Glyph is required." }
        if Self.canonicalizeColor(agent.color) == nil {
            return "Color must be a hex value such as #RRGGBB."
        }
        if let roleName = agent.roleName {
            if roleName.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) == nil {
                return "Role name may only contain letters, numbers, dashes, and underscores."
            }
            if SubagentRole.reservedNames.contains(roleName.lowercased()) {
                return "\"\(roleName)\" is reserved by a built-in subagent."
            }
        }
        return nil
    }

    /// `#RRGGBB` (uppercase) from `#rgb`, `#rrggbb`, or bare hex; nil when invalid.
    static func canonicalizeColor(_ raw: String) -> String? {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.range(of: #"^[0-9A-Fa-f]{3}$|^[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil else {
            return nil
        }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        return "#\(hex.uppercased())"
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedSkills(_ skills: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for skill in skills {
            let trimmed = skill.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}

/// Durable roster of specialist agents in Application Support.
///
/// Persistence is `~/Library/Application Support/GrokBuild/agents.v1.json` (a JSON
/// array). Inject `storageURL` and `now` so tests never touch the live roster.
@Observable
@MainActor
final class SpecialistAgentStore {
    static let maxAgents = 24
    nonisolated static let fileName = "agents.v1.json"

    /// `~/Library/Application Support/GrokBuild/agents.v1.json`
    nonisolated static var defaultStorageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GrokBuild", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private(set) var agents: [SpecialistAgent] = []
    /// Set when the on-disk file exists but cannot be decoded. Init never rewrites it.
    private(set) var loadError: SpecialistAgentStoreError?

    private let storageURL: URL
    private let now: () -> Date

    init(storageURL: URL = defaultStorageURL, now: @escaping () -> Date = Date.init) {
        self.storageURL = storageURL
        self.now = now
        let loaded = Self.load(from: storageURL)
        agents = loaded.agents
        loadError = loaded.error
    }

    func reload() {
        let loaded = Self.load(from: storageURL)
        if let error = loaded.error {
            loadError = error
            return
        }
        loadError = nil
        agents = loaded.agents
    }

    func agent(id: UUID) -> SpecialistAgent? {
        agents.first { $0.id == id }
    }

    @discardableResult
    func create(_ draft: SpecialistAgent) throws -> SpecialistAgent {
        guard agents.count < Self.maxAgents else {
            throw SpecialistAgentStoreError.invalidAgent("The roster can hold at most \(Self.maxAgents) agents.")
        }
        guard !agents.contains(where: { $0.id == draft.id }) else {
            throw SpecialistAgentStoreError.duplicateIdentity
        }
        let timestamp = now()
        let agent = try validated(
            draft.normalized().replacingTimestamps(createdAt: timestamp, updatedAt: timestamp),
            excludingID: nil
        )
        try persistMutating { $0.append(agent) }
        return agent
    }

    @discardableResult
    func update(_ draft: SpecialistAgent) throws -> SpecialistAgent {
        guard let existing = agent(id: draft.id) else {
            throw SpecialistAgentStoreError.agentNotFound
        }
        let agent = try validated(
            draft.normalized().replacingTimestamps(createdAt: existing.createdAt, updatedAt: now()),
            excludingID: existing.id
        )
        try persistMutating { roster in
            guard let index = roster.firstIndex(where: { $0.id == agent.id }) else {
                throw SpecialistAgentStoreError.agentNotFound
            }
            roster[index] = agent
        }
        return agent
    }

    func delete(id: UUID) throws {
        guard agents.contains(where: { $0.id == id }) else {
            throw SpecialistAgentStoreError.agentNotFound
        }
        try persistMutating { $0.removeAll { $0.id == id } }
    }

    // MARK: - Persistence

    nonisolated static func encode(_ agents: [SpecialistAgent]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(agents)
    }

    nonisolated static func decode(_ data: Data) throws -> [SpecialistAgent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SpecialistAgent].self, from: data)
    }

    private static func load(from url: URL) -> (agents: [SpecialistAgent], error: SpecialistAgentStoreError?) {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
        let existsAsFile = values?.isRegularFile == true
        let existsAsDirectory = values?.isDirectory == true
        if !FileManager.default.fileExists(atPath: url.path) {
            return ([], nil)
        }
        if existsAsDirectory || !existsAsFile {
            return ([], .loadFailed)
        }
        do {
            let data = try Data(contentsOf: url)
            return (try decode(data), nil)
        } catch {
            return ([], .loadFailed)
        }
    }

    private func persistMutating(_ mutate: (inout [SpecialistAgent]) throws -> Void) throws {
        let previous = agents
        do {
            var next = agents
            try mutate(&next)
            try persist(next)
            agents = next
        } catch let error as SpecialistAgentStoreError {
            agents = previous
            throw error
        } catch {
            agents = previous
            throw SpecialistAgentStoreError.persistFailed
        }
    }

    private func persist(_ agents: [SpecialistAgent]) throws {
        let data = try Self.encode(agents)
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            throw SpecialistAgentStoreError.persistFailed
        }
    }

    private func validated(_ agent: SpecialistAgent, excludingID: UUID?) throws -> SpecialistAgent {
        if let message = agent.validationError {
            throw SpecialistAgentStoreError.invalidAgent(message)
        }
        if isDuplicateName(agent.name, excludingID: excludingID) {
            throw SpecialistAgentStoreError.duplicateName(agent.name)
        }
        return agent
    }

    private func isDuplicateName(_ name: String, excludingID: UUID?) -> Bool {
        agents.contains { existing in
            if existing.id == excludingID { return false }
            return existing.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }
}

private extension SpecialistAgent {
    func replacingTimestamps(createdAt: Date, updatedAt: Date) -> SpecialistAgent {
        SpecialistAgent(
            id: id,
            name: name,
            mission: mission,
            glyph: glyph,
            color: color,
            roleName: roleName,
            defaultModel: defaultModel,
            permissionProfile: permissionProfile,
            browserEnabled: browserEnabled,
            computerUseEnabled: computerUseEnabled,
            preferredSkills: preferredSkills,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastSessionID: lastSessionID
        )
    }
}
