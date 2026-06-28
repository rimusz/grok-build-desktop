import Foundation

struct ComputerUseCursorInstallStatus: Sendable, Equatable {
    var isInstalled: Bool
    var helperInstalled: Bool
    var agentDesktopInstalled: Bool
    var mcpEntryConfigured: Bool
    var installRoot: String
    var mcpConfigPath: String
    var helperPath: String?
    var agentDesktopPath: String?
    var diagnostic: String

    static let unavailable = ComputerUseCursorInstallStatus(
        isInstalled: false,
        helperInstalled: false,
        agentDesktopInstalled: false,
        mcpEntryConfigured: false,
        installRoot: ComputerUseCursorInstaller.defaultInstallRoot.path,
        mcpConfigPath: ComputerUseCursorInstaller.defaultCursorMCPConfigURL.path,
        helperPath: nil,
        agentDesktopPath: nil,
        diagnostic: "Cursor integration has not been installed."
    )
}

enum ComputerUseCursorInstaller {
    static let mcpServerName = "grokbuild-computer-use"
    static let helperFileName = "GrokBuildComputerUseMCP"
    static let agentDesktopFileName = "agent-desktop"

    static var defaultInstallRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grokbuild")
            .appendingPathComponent("computer-use")
    }

    static var defaultCursorMCPConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor")
            .appendingPathComponent("mcp.json")
    }

    static func resolvedInstallRoot(override: URL? = nil) -> URL {
        override ?? defaultInstallRoot
    }

    static func resolvedCursorMCPConfigURL(override: URL? = nil) -> URL {
        override ?? defaultCursorMCPConfigURL
    }

    static func installedHelperURL(in installRoot: URL? = nil) -> URL {
        resolvedInstallRoot(override: installRoot).appendingPathComponent(helperFileName)
    }

    static func installedAgentDesktopURL(in installRoot: URL? = nil) -> URL {
        resolvedInstallRoot(override: installRoot).appendingPathComponent(agentDesktopFileName)
    }

    static func status(
        installRoot: URL? = nil,
        cursorMCPConfigURL: URL? = nil
    ) -> ComputerUseCursorInstallStatus {
        let root = resolvedInstallRoot(override: installRoot)
        let mcpURL = resolvedCursorMCPConfigURL(override: cursorMCPConfigURL)
        let helper = installedHelperURL(in: root)
        let agentDesktop = installedAgentDesktopURL(in: root)
        let helperInstalled = FileManager.default.isExecutableFile(atPath: helper.path)
        let agentDesktopInstalled = FileManager.default.isExecutableFile(atPath: agentDesktop.path)
        let mcpEntryConfigured = mcpEntry(in: mcpURL) != nil
        let isInstalled = helperInstalled && agentDesktopInstalled && mcpEntryConfigured

        var diagnostic = "Install root: \(root.path)"
        diagnostic += "\nCursor MCP config: \(mcpURL.path)"
        diagnostic += "\nHelper installed: \(helperInstalled ? "yes" : "no")"
        diagnostic += "\nagent-desktop installed: \(agentDesktopInstalled ? "yes" : "no")"
        diagnostic += "\nMCP entry configured: \(mcpEntryConfigured ? "yes" : "no")"

        return ComputerUseCursorInstallStatus(
            isInstalled: isInstalled,
            helperInstalled: helperInstalled,
            agentDesktopInstalled: agentDesktopInstalled,
            mcpEntryConfigured: mcpEntryConfigured,
            installRoot: root.path,
            mcpConfigPath: mcpURL.path,
            helperPath: helperInstalled ? helper.path : nil,
            agentDesktopPath: agentDesktopInstalled ? agentDesktop.path : nil,
            diagnostic: diagnostic
        )
    }

    static func updateConfiguration(
        settings: ComputerUseSettings,
        installRoot: URL? = nil,
        cursorMCPConfigURL: URL? = nil
    ) throws -> String {
        let status = status(installRoot: installRoot, cursorMCPConfigURL: cursorMCPConfigURL)
        guard status.isInstalled,
              let helperPath = status.helperPath,
              let agentDesktopPath = status.agentDesktopPath else {
            throw installError("Computer Use is not installed for Cursor.")
        }

        let entry = cursorMCPEntry(
            settings: settings,
            helperPath: helperPath,
            agentDesktopPath: agentDesktopPath
        )
        let mcpURL = resolvedCursorMCPConfigURL(override: cursorMCPConfigURL)
        try mergeCursorMCPConfig(entry: entry, at: mcpURL)

        return "Updated Cursor MCP configuration at \(mcpURL.path). Reload MCP servers in Cursor to apply the change."
    }

    static func install(
        settings: ComputerUseSettings = ComputerUseSettingsStore.load(),
        installRoot: URL? = nil,
        cursorMCPConfigURL: URL? = nil,
        helperOverride: URL? = nil,
        agentDesktopOverride: URL? = nil
    ) throws -> String {
        guard let sourceHelper = helperOverride ?? ComputerUseService.helperURL() else {
            throw installError("GrokBuildComputerUseMCP helper is missing from this app build.")
        }
        guard let sourceAgentDesktop = agentDesktopOverride ?? ComputerUseService.executableURL(settings: settings) else {
            throw installError("agent-desktop is not available in this app build.")
        }

        let root = resolvedInstallRoot(override: installRoot)
        let mcpURL = resolvedCursorMCPConfigURL(override: cursorMCPConfigURL)
        let destinationHelper = installedHelperURL(in: root)
        let destinationAgentDesktop = installedAgentDesktopURL(in: root)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try copyExecutable(from: sourceHelper, to: destinationHelper)
        try copyExecutable(from: sourceAgentDesktop, to: destinationAgentDesktop)

        let entry = cursorMCPEntry(
            settings: settings,
            helperPath: destinationHelper.path,
            agentDesktopPath: destinationAgentDesktop.path
        )
        try mergeCursorMCPConfig(entry: entry, at: mcpURL)

        var lines = [
            "Installed Computer Use for Cursor.",
            "Helper: \(destinationHelper.path)",
            "agent-desktop: \(destinationAgentDesktop.path)",
            "Updated global MCP config: \(mcpURL.path)",
            "",
            "Reload MCP servers in Cursor (Settings → MCP & Integrations) so `computer_*` tools appear in Agent mode."
        ]

        if settings.includeScreenshots {
            lines.append("Screen Recording permission is required for screenshot tools.")
        }
        lines.append("Grant Accessibility for the installed helper and agent-desktop if macOS prompts you.")

        return lines.joined(separator: "\n")
    }

    static func uninstall(
        installRoot: URL? = nil,
        cursorMCPConfigURL: URL? = nil,
        removeFiles: Bool = true
    ) throws -> String {
        let root = resolvedInstallRoot(override: installRoot)
        let mcpURL = resolvedCursorMCPConfigURL(override: cursorMCPConfigURL)
        var lines: [String] = []

        if FileManager.default.fileExists(atPath: mcpURL.path) {
            try removeCursorMCPEntry(at: mcpURL)
            lines.append("Removed `\(mcpServerName)` from \(mcpURL.path).")
        } else {
            lines.append("Cursor MCP config was not found at \(mcpURL.path).")
        }

        if removeFiles, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
            lines.append("Removed install files from \(root.path).")
        }

        lines.append("Reload MCP servers in Cursor to apply the change.")
        return lines.joined(separator: "\n")
    }

    static func cursorMCPEntry(
        settings: ComputerUseSettings,
        helperPath: String,
        agentDesktopPath: String
    ) -> [String: Any] {
        let env: [String: String] = [
            "AGENT_DESKTOP_PATH": agentDesktopPath,
            "GROKBUILD_COMPUTER_USE_POLICY": settings.permissionPolicy.rawValue,
            "GROKBUILD_COMPUTER_USE_TIMEOUT": String(settings.commandTimeoutSeconds),
            "GROKBUILD_COMPUTER_USE_MAX_STEPS": String(settings.maxSteps),
            "GROKBUILD_COMPUTER_USE_SCREENSHOTS": settings.includeScreenshots ? "true" : "false",
            "GROKBUILD_COMPUTER_USE_ALLOW_PHYSICAL_MOUSE": settings.allowPhysicalMouse ? "true" : "false",
            "GROKBUILD_COMPUTER_USE_SESSION": ComputerUseService.normalizedSessionName(settings.sessionName)
        ]

        let entry: [String: Any] = [
            "command": helperPath,
            "args": [String](),
            "type": "stdio",
            "env": env
        ]
        return entry
    }

    static func mergeCursorMCPConfig(entry: [String: Any], at url: URL) throws {
        let fileManager = FileManager.default
        var root: [String: Any]

        if fileManager.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw installError("Cursor MCP config at \(url.path) is not valid JSON.")
            }
            root = parsed
        } else {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            root = [:]
        }

        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers[mcpServerName] = entry
        root["mcpServers"] = servers

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    static func removeCursorMCPEntry(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let data = try Data(contentsOf: url)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw installError("Cursor MCP config at \(url.path) is not valid JSON.")
        }

        guard var servers = root["mcpServers"] as? [String: Any] else {
            return
        }

        servers.removeValue(forKey: mcpServerName)
        root["mcpServers"] = servers

        let updated = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try updated.write(to: url, options: .atomic)
    }

    static func mcpEntry(in url: URL) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any] else {
            return nil
        }
        return servers[mcpServerName] as? [String: Any]
    }

    private static func copyExecutable(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
    }

    private static func installError(_ message: String) -> NSError {
        NSError(
            domain: "ComputerUseCursorInstaller",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
