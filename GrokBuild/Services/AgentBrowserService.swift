import Foundation

struct BrowserBackendStatus: Sendable, Equatable {
    var isInstalled: Bool
    var isReady: Bool
    var executablePath: String?
    var version: String?
    var diagnostic: String

    static let unavailable = BrowserBackendStatus(
        isInstalled: false,
        isReady: false,
        executablePath: nil,
        version: nil,
        diagnostic: "agent-browser is not installed."
    )
}

struct ExternalBrowserStatus: Sendable, Equatable {
    var isReachable: Bool
    var endpoint: String
    var browserName: String?
    var diagnostic: String

    static func unavailable(endpoint: String) -> ExternalBrowserStatus {
        ExternalBrowserStatus(
            isReachable: false,
            endpoint: endpoint,
            browserName: nil,
            diagnostic: "External browser is not reachable at \(endpoint)."
        )
    }
}

enum AgentBrowserService {
    private struct CommandResult: Sendable {
        var output: String
        var exitCode: Int32
    }

    static func executableURL() -> URL? {
        if let path = ProcessInfo.processInfo.environment["AGENT_BROWSER_PATH"], !path.isEmpty {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }

        for candidate in [
            "/opt/homebrew/bin/agent-browser",
            "/usr/local/bin/agent-browser",
            "\(NSHomeDirectory())/.local/bin/agent-browser",
            "\(NSHomeDirectory())/bin/agent-browser"
        ] where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(directory))
                    .appendingPathComponent("agent-browser")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }

    static func bridgeScriptURL() -> URL? {
        if let resource = Bundle.main.url(forResource: "grokbuild-browser-mcp", withExtension: nil) {
            return resource
        }

        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<4 {
            let candidate = directory
                .appendingPathComponent("scripts")
                .appendingPathComponent("grokbuild-browser-mcp")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }

        return nil
    }

    static func browserMCPConfig(settings: BrowserSettings = BrowserSettingsStore.load()) -> MCPServerConfig? {
        guard settings.enabled,
              settings.backend == .agentBrowser,
              let bridgeScript = bridgeScriptURL() else {
            return nil
        }

        var env: [String: String] = [:]
        if let executable = executableURL() {
            env["AGENT_BROWSER_PATH"] = executable.path
        }
        if settings.showBrowserWindow {
            env["AGENT_BROWSER_HEADED"] = "true"
        }
        if settings.runtimeMode == .external {
            env["GROKBUILD_BROWSER_CDP_URL"] = externalBrowserCDPURL(settings: settings)
        }
        let trimmedProfile = settings.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedProfile.isEmpty {
            env["GROKBUILD_BROWSER_PROFILE"] = trimmedProfile
        }

        return MCPServerConfig(
            name: "grokbuild-browser",
            transport: .stdio,
            command: bridgeScript.path,
            args: [],
            env: env
        )
    }

    static func browserToolsConfigurationIssue(settings: BrowserSettings = BrowserSettingsStore.load()) -> String? {
        guard settings.backend == .agentBrowser else {
            return "Browser backend is not configured."
        }
        guard bridgeScriptURL() != nil else {
            return "Browser bridge script is missing."
        }
        guard executableURL() != nil else {
            return "Install agent-browser in Browser settings first."
        }

        return browserRuntimeConfigurationIssue(settings: settings, mode: settings.runtimeMode)
    }

    static func browserRuntimeConfigurationIssue(settings: BrowserSettings, mode: BrowserRuntimeMode) -> String? {
        switch mode {
        case .managed:
            guard hasManagedRuntimeDirectory() else {
                return "Install the managed browser runtime in Browser settings first."
            }
        case .external:
            guard externalBrowserExecutableURL(settings: settings) != nil else {
                return "Choose an installed Chromium app in Browser settings first."
            }
        }

        return nil
    }

    static func externalBrowserURL(settings: BrowserSettings) -> URL? {
        let trimmedCustomPath = settings.externalBrowserAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.externalBrowserAppID == .custom, !trimmedCustomPath.isEmpty {
            let url = URL(fileURLWithPath: (trimmedCustomPath as NSString).expandingTildeInPath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        return settings.externalBrowserAppID.defaultAppURL
    }

    static func externalBrowserExecutableURL(settings: BrowserSettings) -> URL? {
        guard let appURL = externalBrowserURL(settings: settings) else { return nil }
        let infoURL = appURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")
        guard
            let info = NSDictionary(contentsOf: infoURL),
            let executableName = info["CFBundleExecutable"] as? String
        else {
            return nil
        }

        let executable = appURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent(executableName)
        return FileManager.default.isExecutableFile(atPath: executable.path) ? executable : nil
    }

    static func externalBrowserCDPURL(settings: BrowserSettings) -> String {
        let trimmed = settings.cdpURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "http://127.0.0.1:9222" : trimmed
    }

    static func externalBrowserPort(settings: BrowserSettings) -> Int {
        guard
            let url = URL(string: externalBrowserCDPURL(settings: settings)),
            let port = url.port
        else {
            return 9222
        }
        return port
    }

    static func externalBrowserProfileDirectory(settings: BrowserSettings) -> URL {
        let appName = settings.externalBrowserAppID.rawValue
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("GrokBuild")
            .appendingPathComponent("BrowserProfiles")
            .appendingPathComponent(appName)
    }

    static func externalBrowserLaunchArguments(settings: BrowserSettings) -> [String] {
        [
            "--remote-debugging-port=\(externalBrowserPort(settings: settings))",
            "--user-data-dir=\(externalBrowserProfileDirectory(settings: settings).path)",
            "--no-first-run",
            "--no-default-browser-check"
        ]
    }

    static func externalBrowserLaunchCommand(settings: BrowserSettings) -> String {
        let executable = externalBrowserExecutableURL(settings: settings)?.path
            ?? externalBrowserURL(settings: settings)?.path
            ?? settings.externalBrowserAppID.displayName
        return ([executable] + externalBrowserLaunchArguments(settings: settings))
            .map(shellQuoted)
            .joined(separator: " ")
    }

    @discardableResult
    static func launchExternalBrowser(settings: BrowserSettings) async throws -> ExternalBrowserStatus {
        guard let executable = externalBrowserExecutableURL(settings: settings) else {
            throw NSError(
                domain: "AgentBrowser",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not find \(settings.externalBrowserAppID.displayName). Choose an installed Chromium app."]
            )
        }

        let profileDirectory = externalBrowserProfileDirectory(settings: settings)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = executable
        process.arguments = externalBrowserLaunchArguments(settings: settings)
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()

        return try await waitForExternalBrowser(settings: settings)
    }

    static func ensureExternalBrowserStarted(settings: BrowserSettings) async throws -> ExternalBrowserStatus? {
        guard settings.enabled,
              settings.runtimeMode == .external,
              settings.autoStartExternalBrowser else {
            return nil
        }

        let currentStatus = await externalBrowserStatus(settings: settings)
        if currentStatus.isReachable {
            return currentStatus
        }
        return try await launchExternalBrowser(settings: settings)
    }

    static func externalBrowserStatus(settings: BrowserSettings) async -> ExternalBrowserStatus {
        let endpoint = externalBrowserCDPURL(settings: settings)
        guard let versionURL = URL(string: endpoint)?.appendingPathComponent("json/version") else {
            return ExternalBrowserStatus.unavailable(endpoint: endpoint)
        }

        do {
            var request = URLRequest(url: versionURL)
            request.timeoutInterval = 1.5
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return ExternalBrowserStatus.unavailable(endpoint: endpoint)
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let browser = json?["Browser"] as? String
            return ExternalBrowserStatus(
                isReachable: true,
                endpoint: endpoint,
                browserName: browser,
                diagnostic: browser.map { "Connected to \($0) at \(endpoint)." }
                    ?? "Connected to external browser at \(endpoint)."
            )
        } catch {
            return ExternalBrowserStatus(
                isReachable: false,
                endpoint: endpoint,
                browserName: nil,
                diagnostic: error.localizedDescription
            )
        }
    }

    static func status() async -> BrowserBackendStatus {
        guard let executable = executableURL() else { return .unavailable }
        let versionResult = try? await run([executable.path, "--version"])
        let doctorResult = try? await runResult([executable.path, "doctor"], allowFailure: true)

        return BrowserBackendStatus(
            isInstalled: true,
            isReady: doctorResult?.exitCode == 0,
            executablePath: executable.path,
            version: versionResult?.trimmingCharacters(in: .whitespacesAndNewlines),
            diagnostic: doctorResult?.output.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "agent-browser found at \(executable.path)."
        )
    }

    static func commandPreview(_ args: [String]) -> [String] {
        let executable = executableURL()?.path ?? "agent-browser"
        return [executable] + args
    }

    static func installBrowserRuntime() async throws -> String {
        guard let executable = executableURL() else {
            throw NSError(
                domain: "AgentBrowser",
                code: 127,
                userInfo: [NSLocalizedDescriptionKey: "Install agent-browser with npm or Homebrew first."]
            )
        }

        return try await run([executable.path, "install"], allowFailure: false)
    }

    static var managedRuntimeDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".agent-browser")
            .appendingPathComponent("browsers")
    }

    static func hasManagedRuntimeDirectory() -> Bool {
        FileManager.default.fileExists(atPath: managedRuntimeDirectory.path)
    }

    static func uninstallManagedRuntime() throws -> String {
        let directory = managedRuntimeDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return "Managed browser runtime is already removed."
        }

        try FileManager.default.removeItem(at: directory)
        return "Removed managed browser runtime at \(directory.path)."
    }

    private static func shellQuoted(_ value: String) -> String {
        if value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
           !value.contains("'"),
           !value.isEmpty {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func waitForExternalBrowser(settings: BrowserSettings) async throws -> ExternalBrowserStatus {
        for _ in 0..<20 {
            let status = await externalBrowserStatus(settings: settings)
            if status.isReachable {
                return status
            }
            try await Task.sleep(for: .milliseconds(250))
        }

        throw NSError(
            domain: "AgentBrowser",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Started the browser, but CDP did not become reachable at \(externalBrowserCDPURL(settings: settings))."]
        )
    }

    @discardableResult
    static func run(_ command: [String], allowFailure: Bool = false) async throws -> String {
        try await runResult(command, allowFailure: allowFailure).output
    }

    private static func runResult(_ command: [String], allowFailure: Bool = false) async throws -> CommandResult {
        guard let executable = command.first else { return CommandResult(output: "", exitCode: 0) }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(command.dropFirst())
            process.environment = ProcessInfo.processInfo.environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { process in
                let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let output = out.isEmpty ? err : out
                if process.terminationStatus == 0 || allowFailure {
                    continuation.resume(returning: CommandResult(output: output, exitCode: process.terminationStatus))
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "AgentBrowser",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: output]
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

