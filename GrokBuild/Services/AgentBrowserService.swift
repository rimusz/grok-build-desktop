import Foundation

struct BrowserBackendStatus: Sendable, Equatable {
    var isInstalled: Bool
    var executablePath: String?
    var version: String?
    var diagnostic: String

    static let unavailable = BrowserBackendStatus(
        isInstalled: false,
        executablePath: nil,
        version: nil,
        diagnostic: "agent-browser is not installed."
    )
}

enum AgentBrowserService {
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
        let trimmedCDP = settings.cdpURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCDP.isEmpty {
            env["GROKBUILD_BROWSER_CDP_URL"] = trimmedCDP
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

    static func status() async -> BrowserBackendStatus {
        guard let executable = executableURL() else { return .unavailable }
        let versionResult = try? await run([executable.path, "--version"])
        let doctorResult = try? await run([executable.path, "doctor"], allowFailure: true)

        return BrowserBackendStatus(
            isInstalled: true,
            executablePath: executable.path,
            version: versionResult?.trimmingCharacters(in: .whitespacesAndNewlines),
            diagnostic: doctorResult?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "agent-browser found at \(executable.path)."
        )
    }

    static func commandPreview(_ args: [String]) -> [String] {
        let executable = executableURL()?.path ?? "agent-browser"
        return [executable] + args
    }

    @discardableResult
    static func run(_ command: [String], allowFailure: Bool = false) async throws -> String {
        guard let executable = command.first else { return "" }
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
                if process.terminationStatus == 0 || allowFailure {
                    continuation.resume(returning: out.isEmpty ? err : out)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "AgentBrowser",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: err.isEmpty ? out : err]
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

