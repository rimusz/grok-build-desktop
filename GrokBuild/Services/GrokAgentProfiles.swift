import Foundation

/// Maps the app's "session agent" selection to the value passed to `grok --agent <NAME>`.
///
/// The app deliberately keeps this thin: grok owns agents/personas. GrokBuild only lets the user
/// pick a discovered grok agent by name (see `GrokCLIService.listAgents`). "Default" means: pass
/// no `--agent` flag and let grok use its standard `grok_build` agent.
enum GrokAgentProfiles {
    /// Sentinel selection id meaning "use grok's default agent" (no `--agent` flag).
    static let defaultID = ""

    /// A selectable session-agent option surfaced in the UI (Settings picker + composer pill).
    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String
    }

    /// Curated, always-available options. Only the `grok-build` default is built in; discovered
    /// subagents are appended by callers from `GrokCLIService.listAgents`.
    static let builtInOptions: [Option] = [
        Option(id: defaultID, title: "Default (grok build)", subtitle: "grok's standard agent")
    ]

    /// Human-readable label for a persisted selection id, preferring built-in titles and falling
    /// back to the raw agent name (used for discovered agents).
    static func displayName(for selection: String) -> String {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        if let option = builtInOptions.first(where: { $0.id == trimmed }) {
            return option.title
        }
        return trimmed.isEmpty ? "Default (grok build)" : trimmed
    }

    /// Maps a persisted session-agent selection to the `--agent` argument value grok expects.
    ///
    /// - `""` (default) → `nil` (omit `--agent`).
    /// - any other value → passed through verbatim as an agent name.
    static func launchArgument(for selection: String) -> String? {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
