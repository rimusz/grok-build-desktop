import Foundation

/// Feature/capability probing for the installed `grok` CLI.
///
/// Detection here is intentionally best-effort. Some capabilities (notably the native
/// `browser_tab` / `browser_network_details` tools that ship inside grok's default
/// `grok_build` tool set) are also gated per-account by a remote GrowthBook flag
/// (`grok_build_access_gate`), which the app cannot observe from the outside. We therefore
/// gate on the CLI *version* as a floor and treat the account gate as a runtime fallback:
/// if a native browser tool is unavailable at runtime, the user can switch the Browser
/// backend to the bundled `agent-browser` MCP.
enum GrokCapabilities {
    /// Parsed `major.minor.patch` triple from `grok --version` output.
    struct Version: Comparable, Equatable, CustomStringConvertible {
        let major: Int
        let minor: Int
        let patch: Int

        var description: String { "\(major).\(minor).\(patch)" }

        static func < (lhs: Version, rhs: Version) -> Bool {
            (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
    }

    /// Minimum grok version known to expose the native `browser_tab` tool. grok 0.2.93 is the
    /// version this was verified against; earlier builds may also work, so this is a conservative
    /// floor rather than an exact boundary.
    static let minVersionForNativeBrowser = Version(major: 0, minor: 2, patch: 90)

    /// Extracts the first `X.Y.Z` version triple from arbitrary `grok --version` output,
    /// e.g. `grok 0.2.93 (f00f96316d4b) [stable]` → `0.2.93`.
    static func parseVersion(_ output: String) -> Version? {
        guard let match = output.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) else {
            return nil
        }
        let parts = output[match].split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Version(major: parts[0], minor: parts[1], patch: parts[2])
    }

    /// True when the given `grok --version` output reports a build new enough to ship the
    /// native browser tools. Returns false for unparseable output (fail closed → app keeps
    /// using the bundled agent-browser MCP).
    static func supportsNativeBrowserTools(versionOutput: String) -> Bool {
        guard let version = parseVersion(versionOutput) else { return false }
        return version >= minVersionForNativeBrowser
    }

    /// Runs `grok --version` and reports whether native browser tools are likely available.
    /// Errors (CLI missing, non-zero exit) resolve to `false`.
    static func supportsNativeBrowserTools(service: GrokCLIService = GrokCLIService()) async -> Bool {
        guard let output = try? await service.run(["--version"], allowFailure: true).stdout else {
            return false
        }
        return supportsNativeBrowserTools(versionOutput: output)
    }
}
