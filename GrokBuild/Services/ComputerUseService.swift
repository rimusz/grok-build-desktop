import Foundation

struct ComputerUseBackendStatus: Sendable, Equatable {
    var isInstalled: Bool
    var isReady: Bool
    var executablePath: String?
    var version: String?
    var diagnostic: String

    static let unavailable = ComputerUseBackendStatus(
        isInstalled: false,
        isReady: false,
        executablePath: nil,
        version: nil,
        diagnostic: "agent-desktop is not installed."
    )
}

struct ComputerUsePermissionStatus: Sendable, Equatable {
    var accessibility: String
    var screenRecording: String
    var diagnostic: String

    static let unavailable = ComputerUsePermissionStatus(
        accessibility: "unknown",
        screenRecording: "unknown",
        diagnostic: "Permission status is unavailable until agent-desktop is installed."
    )

    var isReady: Bool {
        accessibility == "granted"
    }
}

enum ComputerUseService {
    private struct CommandResult: Sendable {
        var output: String
        var exitCode: Int32
    }

    static func executableURL(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) -> URL? {
        let configured = settings.agentDesktopPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            let url = URL(fileURLWithPath: (configured as NSString).expandingTildeInPath)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }

        if let path = ProcessInfo.processInfo.environment["AGENT_DESKTOP_PATH"], !path.isEmpty {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }

        for candidate in [
            "/opt/homebrew/bin/agent-desktop",
            "/usr/local/bin/agent-desktop",
            "\(NSHomeDirectory())/.local/bin/agent-desktop",
            "\(NSHomeDirectory())/bin/agent-desktop"
        ] where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(directory))
                    .appendingPathComponent("agent-desktop")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }

    static func helperURL() -> URL? {
        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            let candidate = executableDirectory.appendingPathComponent("GrokBuildComputerUseMCP")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        for configuration in ["release", "debug"] {
            var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            for _ in 0..<4 {
                let candidate = directory
                    .appendingPathComponent(".build")
                    .appendingPathComponent(configuration)
                    .appendingPathComponent("GrokBuildComputerUseMCP")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
                directory.deleteLastPathComponent()
            }
        }

        return nil
    }

    static func computerUseMCPConfig(
        settings: ComputerUseSettings = ComputerUseSettingsStore.load(),
        helperOverride: URL? = nil,
        agentDesktopOverride: URL? = nil
    ) -> MCPServerConfig? {
        guard settings.enabled,
              settings.backend == .agentDesktop,
              let helper = helperOverride ?? helperURL() else {
            return nil
        }

        var env: [String: String] = [
            "GROKBUILD_COMPUTER_USE_POLICY": settings.permissionPolicy.rawValue,
            "GROKBUILD_COMPUTER_USE_TIMEOUT": String(settings.commandTimeoutSeconds),
            "GROKBUILD_COMPUTER_USE_MAX_STEPS": String(settings.maxSteps),
            "GROKBUILD_COMPUTER_USE_SCREENSHOTS": settings.includeScreenshots ? "true" : "false",
            "GROKBUILD_COMPUTER_USE_ALLOW_PHYSICAL_MOUSE": settings.allowPhysicalMouse ? "true" : "false",
            "GROKBUILD_COMPUTER_USE_SESSION": normalizedSessionName(settings.sessionName)
        ]

        if let executable = agentDesktopOverride ?? executableURL(settings: settings) {
            env["AGENT_DESKTOP_PATH"] = executable.path
        }

        return MCPServerConfig(
            name: "grokbuild-computer-use",
            transport: .stdio,
            command: helper.path,
            args: [],
            env: env
        )
    }

    static func configurationIssue(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) -> String? {
        guard settings.backend == .agentDesktop else {
            return "Computer Use backend is not configured."
        }
        guard helperURL() != nil else {
            return "Computer Use MCP helper is missing. Rebuild the app."
        }
        guard executableURL(settings: settings) != nil else {
            return "Install agent-desktop first."
        }
        return nil
    }

    static func status(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) async -> ComputerUseBackendStatus {
        guard let executable = executableURL(settings: settings) else { return .unavailable }
        let versionResult = try? await run([executable.path, "version"], timeout: 8)
        let permissionResult = try? await runResult([executable.path, "permissions"], timeout: 8)
        let version = versionResult.flatMap(parseVersion)
        let diagnostic = permissionResult?.output.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "agent-desktop found at \(executable.path)."

        return ComputerUseBackendStatus(
            isInstalled: true,
            isReady: permissionResult?.exitCode == 0,
            executablePath: executable.path,
            version: version?.isEmpty == false ? version : nil,
            diagnostic: diagnostic
        )
    }

    static func permissionStatus(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) async -> ComputerUsePermissionStatus {
        guard let executable = executableURL(settings: settings) else { return .unavailable }
        do {
            let output = try await run([executable.path, "permissions"], timeout: 8)
            return parsePermissions(output)
        } catch {
            return ComputerUsePermissionStatus(
                accessibility: "unknown",
                screenRecording: "unknown",
                diagnostic: error.localizedDescription
            )
        }
    }

    static func requestPermissions(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) async throws -> String {
        guard let executable = executableURL(settings: settings) else {
            throw NSError(
                domain: "ComputerUseService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "agent-desktop is not installed."]
            )
        }
        return try await run([executable.path, "permissions", "--request"], timeout: 30)
    }

    static func installAgentDesktop() async throws -> String {
        try await run(["/usr/bin/env", "npm", "install", "-g", "agent-desktop"], timeout: 180)
    }

    static func commandPreview(_ args: [String], settings: ComputerUseSettings = ComputerUseSettingsStore.load()) -> [String] {
        [executableURL(settings: settings)?.path ?? "agent-desktop"] + args
    }

    static func normalizedSessionName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ComputerUseSettings.defaults.sessionName : trimmed
    }

    static func parseVersion(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return trimmed.isEmpty ? nil : trimmed
        }

        if let data = json["data"] as? [String: Any],
           let version = data["version"] as? String,
           !version.isEmpty {
            return version
        }
        if let version = json["version"] as? String, !version.isEmpty {
            return version
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    static func parsePermissions(_ output: String) -> ComputerUsePermissionStatus {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ComputerUsePermissionStatus(
                accessibility: "unknown",
                screenRecording: "unknown",
                diagnostic: output.isEmpty ? "No permission diagnostics returned." : output
            )
        }

        let payload = (json["data"] as? [String: Any]) ?? json

        func state(_ key: String) -> String {
            if let dict = payload[key] as? [String: Any],
               let value = dict["state"] as? String {
                return value
            }
            return "unknown"
        }

        return ComputerUsePermissionStatus(
            accessibility: state("accessibility"),
            screenRecording: state("screen_recording"),
            diagnostic: output
        )
    }

    private static func run(_ command: [String], timeout: TimeInterval) async throws -> String {
        let result = try await runResult(command, timeout: timeout)
        if result.exitCode != 0 {
            throw NSError(
                domain: "ComputerUseService",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: result.output.isEmpty ? "Command failed." : result.output]
            )
        }
        return result.output
    }

    private static func runResult(_ command: [String], timeout: TimeInterval) async throws -> CommandResult {
        guard let executable = command.first else {
            throw NSError(domain: "ComputerUseService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing command."])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(command.dropFirst())
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            final class ResumeBox: @unchecked Sendable {
                let lock = NSLock()
                var didResume = false
            }
            let box = ResumeBox()

            @Sendable
            func finish(_ result: Result<CommandResult, Error>) {
                box.lock.lock()
                guard !box.didResume else {
                    box.lock.unlock()
                    return
                }
                box.didResume = true
                box.lock.unlock()
                continuation.resume(with: result)
            }

            process.terminationHandler = { process in
                let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                finish(.success(CommandResult(output: out.isEmpty ? err : out, exitCode: process.terminationStatus)))
            }

            do {
                try process.run()
            } catch {
                finish(.failure(error))
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                    finish(.failure(NSError(
                        domain: "ComputerUseService",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "agent-desktop command timed out."]
                    )))
                }
            }
        }
    }
}
