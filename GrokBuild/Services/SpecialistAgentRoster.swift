import Foundation
import SwiftUI

/// Pure helpers for the sidebar specialist-agent roster.
enum SpecialistAgentRoster {
    struct LiveSessionMatch: Equatable, Sendable {
        let sessionID: UUID
        let workspaceID: UUID
        let agent: String?
        let isWorking: Bool
        var specialistAgentID: UUID? = nil
        var lastAccessed: Date = .distantPast
    }

    struct LiveBinding: Equatable, Sendable {
        let sessionID: UUID
        let isWorking: Bool
    }

    struct Identity: Equatable, Sendable {
        let name: String
        let glyph: String
    }

    static let glyphChoices = [
        "person.fill",
        "crown.fill",
        "binoculars",
        "hammer.fill",
        "checkmark.shield.fill",
        "desktopcomputer",
        "magnifyingglass",
        "wrench.and.screwdriver.fill",
        "book.fill",
        "bolt.fill",
        "eye.fill",
        "gearshape.2.fill",
        "paintbrush.fill",
        "terminal.fill"
    ]

    static let colorChoices = [
        "#5E5CE6",
        "#0A84FF",
        "#FF9F0A",
        "#30D158",
        "#FF375F",
        "#BF5AF2",
        "#64D2FF",
        "#FFD60A"
    ]

    static func color(from hex: String) -> Color {
        guard let canonical = SpecialistAgent.canonicalizeColor(hex) else {
            return Color.purple
        }
        var value: UInt64 = 0
        Scanner(string: String(canonical.dropFirst())).scanHexInt64(&value)
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static func sessionTitle(for agent: SpecialistAgent) -> String {
        agent.normalized().name
    }

    static func launchAgentSelection(for agent: SpecialistAgent) -> String? {
        SpecialistAgentRoleSync.roleName(for: agent)
    }

    /// Live session in the current project bound to this agent, if any.
    /// Prefer explicit `specialistAgentID` matches (most recently accessed when several),
    /// then `lastSessionID`, then a role/`--agent` match that is not bound to someone else.
    static func liveBinding(
        for agent: SpecialistAgent,
        sessions: [LiveSessionMatch],
        currentWorkspaceID: UUID?
    ) -> LiveBinding? {
        let matches = boundMatches(
            for: agent,
            sessions: sessions,
            currentWorkspaceID: currentWorkspaceID
        )
        guard let best = mostRecentlyAccessed(matches) else { return nil }
        return LiveBinding(
            sessionID: best.sessionID,
            isWorking: matches.contains(where: \.isWorking)
        )
    }

    /// Any bound session in the current project is streaming or waiting for input.
    static func isWorking(
        for agent: SpecialistAgent,
        sessions: [LiveSessionMatch],
        currentWorkspaceID: UUID?
    ) -> Bool {
        boundMatches(for: agent, sessions: sessions, currentWorkspaceID: currentWorkspaceID)
            .contains(where: \.isWorking)
    }

    /// Last bound session the user can reopen, including other projects.
    static func lastBoundSessionID(
        for agent: SpecialistAgent,
        sessions: [LiveSessionMatch]
    ) -> UUID? {
        if let last = agent.lastSessionID,
           sessions.contains(where: { $0.sessionID == last }) {
            return last
        }
        return mostRecentlyAccessed(sessions.filter { $0.specialistAgentID == agent.id })?.sessionID
    }

    /// Composer pill → specialist binding: map a role/`--agent` id onto a roster agent, or clear.
    static func specialistID(
        matchingAgentSelection selection: String,
        in specialists: [SpecialistAgent]
    ) -> UUID? {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return specialists.first { launchAgentSelection(for: $0) == trimmed }?.id
    }

    static func identity(
        for specialistAgentID: UUID?,
        specialists: [SpecialistAgent]
    ) -> Identity? {
        guard let specialistAgentID,
              let agent = specialists.first(where: { $0.id == specialistAgentID }) else {
            return nil
        }
        return Identity(name: agent.name, glyph: agent.glyph)
    }

    static func clearedSpecialistID(_ current: UUID?, deleted deletedID: UUID) -> UUID? {
        current == deletedID ? nil : current
    }

    static func boundMatches(
        for agent: SpecialistAgent,
        sessions: [LiveSessionMatch],
        currentWorkspaceID: UUID?
    ) -> [LiveSessionMatch] {
        guard let currentWorkspaceID else { return [] }
        let inProject = sessions.filter { $0.workspaceID == currentWorkspaceID }
        let explicit = inProject.filter { $0.specialistAgentID == agent.id }
        if !explicit.isEmpty { return explicit }
        if let last = agent.lastSessionID,
           let match = inProject.first(where: { $0.sessionID == last }),
           match.specialistAgentID == nil || match.specialistAgentID == agent.id {
            return [match]
        }
        if let role = launchAgentSelection(for: agent) {
            return inProject.filter { match in
                match.agent == role
                    && (match.specialistAgentID == nil || match.specialistAgentID == agent.id)
            }
        }
        return []
    }

    private static func mostRecentlyAccessed(_ sessions: [LiveSessionMatch]) -> LiveSessionMatch? {
        sessions.max { lhs, rhs in
            if lhs.lastAccessed != rhs.lastAccessed {
                return lhs.lastAccessed < rhs.lastAccessed
            }
            return false
        }
    }

    static func statusLabel(isWorking: Bool) -> String {
        isWorking ? "Working" : "Idle"
    }

    static func duplicateName(of name: String, existing: [String]) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let copy = base.hasSuffix(" (copy)") ? base : "\(base) (copy)"
        if !existing.contains(where: { $0.caseInsensitiveCompare(copy) == .orderedSame }) {
            return copy
        }
        var index = 2
        while existing.contains(where: {
            $0.caseInsensitiveCompare("\(copy) \(index)") == .orderedSame
        }) {
            index += 1
        }
        return "\(copy) \(index)"
    }

    static func matchesFilter(_ query: String, agent: SpecialistAgent) -> Bool {
        SidebarPresentation.matches(
            query,
            values: [agent.name, agent.mission, agent.roleName ?? ""]
        )
    }

    /// Active = pinned, or a live session in the current project is bound to this agent.
    static func isActive(_ agent: SpecialistAgent, hasLiveSession: Bool) -> Bool {
        agent.isPinned || hasLiveSession
    }

    static func hasLiveSession(
        for agent: SpecialistAgent,
        sessions: [LiveSessionMatch],
        currentWorkspaceID: UUID?
    ) -> Bool {
        liveBinding(for: agent, sessions: sessions, currentWorkspaceID: currentWorkspaceID) != nil
    }

    /// Sidebar roster after the active-only / show-all preference and search query.
    static func displayed(
        agents: [SpecialistAgent],
        showAll: Bool,
        liveBoundIDs: Set<UUID>,
        query: String
    ) -> [SpecialistAgent] {
        let scoped = showAll
            ? agents
            : agents.filter { isActive($0, hasLiveSession: liveBoundIDs.contains($0.id)) }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return scoped }
        return scoped.filter { matchesFilter(trimmed, agent: $0) }
    }

    /// Roster exists, but the Active view has nothing to show.
    static func showsEmptyActiveState(
        agents: [SpecialistAgent],
        showAll: Bool,
        liveBoundIDs: Set<UUID>
    ) -> Bool {
        !agents.isEmpty
            && displayed(agents: agents, showAll: showAll, liveBoundIDs: liveBoundIDs, query: "").isEmpty
    }
}
