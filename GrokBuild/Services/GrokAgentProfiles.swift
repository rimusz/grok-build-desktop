import Foundation

/// Resolves GrokBuild's bundled agent-definition files and maps the app's "session agent"
/// selection to the value passed to `grok --agent <NAME|path>`.
///
/// The app deliberately keeps this thin: grok owns agents/personas. GrokBuild only ships one
/// convenience profile (`grokbuild-web`) and otherwise lets the user pick a discovered grok
/// agent by name (see `GrokCLIService.listAgents`). "Default" means: pass no `--agent` flag and
/// let grok use its standard `grok_build` agent.
enum GrokAgentProfiles {
    /// Sentinel selection id for the bundled web-tuned agent profile.
    static let webProfileID = "grokbuild-web"

    /// Sentinel selection id meaning "use grok's default agent" (no `--agent` flag).
    static let defaultID = ""

    /// Locates the bundled `grokbuild-web.md` agent definition, whether running from the app
    /// bundle (Resources copied at build time) or from a source checkout during development.
    static func webProfileURL() -> URL? {
        if let resource = Bundle.main.url(forResource: "grokbuild-web", withExtension: "md", subdirectory: "Agents") {
            return resource
        }
        if let resource = Bundle.main.url(forResource: "grokbuild-web", withExtension: "md") {
            return resource
        }

        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<4 {
            let candidate = directory
                .appendingPathComponent("Resources")
                .appendingPathComponent("Agents")
                .appendingPathComponent("grokbuild-web.md")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    /// Maps a persisted session-agent selection to the `--agent` argument value grok expects.
    ///
    /// - `""` (default) → `nil` (omit `--agent`).
    /// - `"grokbuild-web"` → absolute path to the bundled profile (falls back to the name if the
    ///   bundled file cannot be located, so grok can still resolve it via discovery).
    /// - any other value → passed through verbatim as an agent name.
    static func launchArgument(for selection: String) -> String? {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == webProfileID {
            return webProfileURL()?.path ?? webProfileID
        }
        return trimmed
    }
}
