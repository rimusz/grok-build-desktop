import Foundation

/// Official xAI marketplace plugin `browser-use` (`grok plugin install browser-use --trust`).
///
/// Distinct from grok's built-in `--agent browser-use` persona. The plugin registers its own
/// MCP (`uvx browser-use@latest --cli-mcp`) with `browser_exec` / `browser_screenshot`. While it
/// is installed and enabled, GrokBuild must not inject `grokbuild-browser`.
enum BrowserUsePlugin {
    static let name = "browser-use"
    static let marketplaceSource = "browser-use"
    static let brewInstallCommand = "brew install uv"
    static let uvInstallURL = URL(string: "https://docs.astral.sh/uv/getting-started/installation/")!

    struct Status: Sendable, Equatable {
        var isInstalled: Bool
        var isEnabled: Bool

        /// grok will load the plugin MCP, so the app must skip `grokbuild-browser`.
        var blocksGrokBuildMCP: Bool { isInstalled && isEnabled }

        static let inactive = Status(isInstalled: false, isEnabled: false)
    }

    /// Isolated GrokBuild `agent-browser` stack vs the marketplace plugin.
    static func shouldUseGrokBuildBrowserStack(
        settings: BrowserSettings,
        plugin: Status
    ) -> Bool {
        guard settings.enabled else { return false }
        if plugin.blocksGrokBuildMCP { return false }
        if settings.backend == .browserUsePlugin { return false }
        return true
    }

    static func status(from plugins: [GrokPluginInfo]) -> Status {
        guard let plugin = plugins.first(where: isBrowserUsePlugin) else {
            return .inactive
        }
        let status = plugin.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if status == "available" || status == "uninstalled" {
            return .inactive
        }
        let disabledByStatus = status == "disabled" || status == "inactive"
        return Status(
            isInstalled: true,
            isEnabled: plugin.isEnabled && !disabledByStatus
        )
    }

    static func loadStatus(using service: GrokCLIService = GrokCLIService()) async -> Status {
        do {
            return status(from: try await service.listPlugins())
        } catch {
            return .inactive
        }
    }

    static func isBrowserUsePlugin(_ plugin: GrokPluginInfo) -> Bool {
        plugin.name.compare(name, options: .caseInsensitive) == .orderedSame
    }

    // MARK: - uv / uvx (plugin MCP command is `uvx`)

    static func uvToolIsAvailable() -> Bool {
        uvxExecutableURL() != nil || uvExecutableURL() != nil
    }

    static func uvxExecutableURL() -> URL? {
        locateExecutable(named: "uvx")
    }

    static func uvExecutableURL() -> URL? {
        locateExecutable(named: "uv")
    }

    static func uvDoctorDetail(
        found: Bool,
        pluginBackendSelected: Bool,
        pluginActive: Bool
    ) -> String {
        if found {
            return "Found — required to run the official browser-use plugin (`uvx`)."
        }
        if pluginBackendSelected || pluginActive {
            return "Not found — install uv so grok can start `uvx browser-use@latest --cli-mcp`."
        }
        return "Not found — needed only for the official browser-use plugin."
    }

    static func uvDoctorStatus(
        found: Bool,
        pluginBackendSelected: Bool,
        pluginActive: Bool
    ) -> DoctorCheck.Status {
        if found { return .ok }
        if pluginBackendSelected || pluginActive { return .warning }
        return .info
    }

    static func browserDoctorDetail(
        enabled: Bool,
        backend: BrowserBackendKind,
        plugin: Status
    ) -> String {
        if plugin.blocksGrokBuildMCP {
            if enabled {
                return "Enabled — official browser-use plugin (logged-in Chrome or Browser Use Cloud). GrokBuild is not injecting grokbuild-browser."
            }
            return "GrokBuild switch is off, but grok still loads the browser-use plugin. Disable it in Settings → Browser to unload browser tools."
        }
        guard enabled else { return "Disabled." }
        if backend == .browserUsePlugin {
            return "Enabled — official browser-use plugin backend. Install and enable the plugin if grok has no browser tools yet."
        }
        return "Enabled — GrokBuild isolated profile (agent-browser)."
    }

    private static func locateExecutable(named name: String) -> URL? {
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.local/bin/\(name)",
            "\(home)/.cargo/bin/\(name)",
            "\(home)/bin/\(name)"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }
}
