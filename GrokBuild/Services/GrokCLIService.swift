import Foundation

struct GrokCLIResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var combinedOutput: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let value = data
        lock.unlock()
        return value
    }
}

struct GrokPluginInfo: Identifiable, Hashable, Sendable {
    let id: String
    let status: String
    let name: String
    let version: String
    let scope: String
    let source: String
    let marketplace: String
    let isEnabled: Bool
    let description: String
    let componentSummary: String

    init(dictionary: [String: Any]) {
        let name = Self.stringValue(dictionary, keys: ["name", "plugin_name", "id"]) ?? "Unknown"
        self.id = Self.stringValue(dictionary, keys: ["id"]) ?? name
        self.status = Self.stringValue(dictionary, keys: ["status"]) ?? ""
        self.name = name
        self.version = Self.stringValue(dictionary, keys: ["version"]) ?? ""
        self.scope = Self.stringValue(dictionary, keys: ["scope", "location", "kind"]) ?? ""
        self.source = Self.stringValue(dictionary, keys: ["source", "path", "url"]) ?? ""
        self.marketplace = Self.stringValue(dictionary, keys: ["marketplace"]) ?? ""
        self.isEnabled = Self.boolValue(dictionary, keys: ["enabled", "is_enabled"]) ?? true
        self.description = Self.stringValue(dictionary, keys: ["description"]) ?? ""

        let components = dictionary["components"] as? [String: Any] ?? dictionary
        let componentKeys = ["skills", "commands", "agents", "hooks", "mcp_servers", "mcps", "lsp_servers"]
        let parts = componentKeys.compactMap { key -> String? in
            let countKey: String
            switch key {
            case "mcp_servers", "mcps": countKey = "mcp_count"
            case "lsp_servers": countKey = "lsp_count"
            default: countKey = "\(key)_count"
            }
            let directCount = dictionary[countKey]
            let value = components[key] ?? dictionary[key] ?? directCount
            guard let value else { return nil }
            if let array = value as? [Any], !array.isEmpty {
                return "\(key.replacingOccurrences(of: "_", with: " ")): \(array.count)"
            }
            if let count = value as? Int, count > 0 {
                return "\(key.replacingOccurrences(of: "_", with: " ")): \(count)"
            }
            return nil
        }
        self.componentSummary = parts.joined(separator: " · ")
    }

    private static func stringValue(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty { return value }
            if dictionary[key] is NSNull { continue }
            if let value = dictionary[key] { return "\(value)" }
        }
        return nil
    }

    private static func boolValue(_ dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dictionary[key] as? Bool { return value }
            if let value = dictionary[key] as? String { return ["true", "yes", "enabled"].contains(value.lowercased()) }
        }
        return nil
    }
}

struct GrokMarketplaceSource: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: String
    let location: String

    init(dictionary: [String: Any]) {
        name = dictionary["name"] as? String ?? "Unknown"
        kind = dictionary["kind"] as? String ?? ""
        if let source = dictionary["source"] as? [String: Any] {
            location = source["url"] as? String ?? source["path"] as? String ?? ""
        } else {
            location = dictionary["url"] as? String ?? dictionary["path"] as? String ?? ""
        }
        id = "\(name)-\(location)"
    }
}

struct GrokHookInfo: Identifiable, Hashable, Sendable {
    let id: String
    let event: String
    let hookType: String
    let target: String
    let matcher: String
    let sourceType: String
    let sourcePath: String
    let pluginName: String
    let vendor: String

    init(dictionary: [String: Any]) {
        event = dictionary["event"] as? String ?? ""
        hookType = dictionary["hookType"] as? String ?? dictionary["hook_type"] as? String ?? ""
        target = dictionary["target"] as? String ?? ""
        matcher = dictionary["matcher"] as? String ?? ""
        vendor = dictionary["vendor"] as? String ?? ""

        let source = dictionary["source"] as? [String: Any] ?? [:]
        sourceType = source["type"] as? String ?? ""
        sourcePath = source["path"] as? String ?? ""
        pluginName = source["plugin_name"] as? String ?? source["pluginName"] as? String ?? ""
        id = [event, hookType, target, sourcePath, pluginName].joined(separator: "|")
    }
}

struct GrokSkillInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let sourceType: String
    let sourcePath: String
    let pluginName: String
    let userInvocable: Bool

    init(dictionary: [String: Any]) {
        name = dictionary["name"] as? String ?? "Unknown"
        description = dictionary["description"] as? String ?? ""
        userInvocable = dictionary["userInvocable"] as? Bool ?? dictionary["user_invocable"] as? Bool ?? false

        let source = dictionary["source"] as? [String: Any] ?? [:]
        sourceType = source["type"] as? String ?? ""
        sourcePath = source["path"] as? String ?? ""
        pluginName = source["plugin_name"] as? String ?? source["pluginName"] as? String ?? ""
        id = [name, sourcePath, pluginName].joined(separator: "|")
    }
}

struct GrokMCPServerInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let transport: String
    let target: String
    let source: String
    let isEnabled: Bool?

    init(dictionary: [String: Any]) {
        name = dictionary["name"] as? String ?? "Unknown"
        id = dictionary["id"] as? String ?? name
        transport = dictionary["transport"] as? String ?? dictionary["type"] as? String ?? ""
        target = dictionary["target"] as? String ?? dictionary["url"] as? String ?? dictionary["command"] as? String ?? ""
        source = dictionary["source"] as? String ?? dictionary["scope"] as? String ?? ""
        isEnabled = dictionary["enabled"] as? Bool
    }
}

struct GrokMCPDoctorReport: Sendable {
    struct Server: Identifiable, Hashable, Sendable {
        struct Check: Hashable, Sendable {
            let label: String
            let passed: Bool
            let detail: String
            let hint: String
        }

        let id: String
        let name: String
        let transport: String
        let target: String
        let source: String
        let healthy: Bool
        let checks: [Check]
    }

    let healthyCount: Int
    let failingCount: Int
    let servers: [Server]

    init(dictionary: [String: Any]) {
        healthyCount = dictionary["healthy_count"] as? Int ?? 0
        failingCount = dictionary["failing_count"] as? Int ?? 0
        servers = (dictionary["servers"] as? [[String: Any]] ?? []).map { server in
            Server(
                id: server["name"] as? String ?? UUID().uuidString,
                name: server["name"] as? String ?? "Unknown",
                transport: server["transport"] as? String ?? "",
                target: server["target"] as? String ?? "",
                source: server["source"] as? String ?? "",
                healthy: server["healthy"] as? Bool ?? false,
                checks: (server["checks"] as? [[String: Any]] ?? []).map { check in
                    Server.Check(
                        label: check["label"] as? String ?? "",
                        passed: check["passed"] as? Bool ?? false,
                        detail: check["detail"] as? String ?? "",
                        hint: check["hint"] as? String ?? ""
                    )
                }
            )
        }
    }
}

struct GrokModelInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isDefault: Bool
}

struct GrokSessionInfo: Identifiable, Hashable, Sendable {
    let id: String
    let created: String
    let updated: String
    let status: String
    let summary: String

    static func parseListOutput(_ output: String) -> [GrokSessionInfo] {
        output.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > 36 else { return nil }
            let sessionID = String(trimmed.prefix(36))
            guard sessionID.range(of: #"^[0-9a-fA-F-]{36}$"#, options: .regularExpression) != nil else { return nil }

            let rest = trimmed.dropFirst(36).trimmingCharacters(in: .whitespaces)
            let pieces = rest.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard pieces.count >= 3 else { return nil }
            return GrokSessionInfo(
                id: sessionID,
                created: String(pieces[0]),
                updated: String(pieces[1]),
                status: String(pieces[2]),
                summary: pieces.count > 3 ? String(pieces[3]) : ""
            )
        }
    }
}

struct GrokPermissionSettings: Sendable {
    var permissionMode: String
    var sandboxProfile: String
    var reasoningEffort: String
    var noMemory: Bool
    var disableWebSearch: Bool
    var noSubagents: Bool
    var allowRules: String
    var denyRules: String

    static let defaults = GrokPermissionSettings(
        permissionMode: "default",
        sandboxProfile: "",
        reasoningEffort: "",
        noMemory: false,
        disableWebSearch: false,
        noSubagents: false,
        allowRules: "",
        denyRules: ""
    )
}

enum GrokSettingsKeys {
    static let permissionMode = "grokbuild.permissionMode"
    static let sandboxProfile = "grokbuild.sandboxProfile"
    static let reasoningEffort = "grokbuild.reasoningEffort"
    static let noMemory = "grokbuild.noMemory"
    static let disableWebSearch = "grokbuild.disableWebSearch"
    static let noSubagents = "grokbuild.noSubagents"
    static let allowRules = "grokbuild.allowRules"
    static let denyRules = "grokbuild.denyRules"
}

final class GrokCLIService {
    enum CLIError: LocalizedError {
        case notFound
        case failed(args: [String], result: GrokCLIResult)
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "Could not locate the `grok` CLI. Set GROK_CLI_PATH or install grok."
            case .failed(let args, let result):
                let output = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                return "`grok \(args.joined(separator: " "))` failed with exit code \(result.exitCode).\n\(output)"
            case .invalidJSON(let output):
                return "The grok CLI returned output that was not valid JSON.\n\(output)"
            }
        }
    }

    func run(_ args: [String], cwd: URL? = nil, allowFailure: Bool = false) async throws -> GrokCLIResult {
        guard let cli = Self.locateGrokCLI() else { throw CLIError.notFound }

        let process = Process()
        process.executableURL = cli
        process.arguments = args
        process.currentDirectoryURL = cwd
        process.environment = ProcessInfo.processInfo.environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stdoutData = LockedData()
        let stderrData = LockedData()

        stdout.fileHandleForReading.readabilityHandler = { handle in
            stdoutData.append(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrData.append(handle.availableData)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                stdoutData.append(stdout.fileHandleForReading.readDataToEndOfFile())
                stderrData.append(stderr.fileHandleForReading.readDataToEndOfFile())
                continuation.resume()
            }

            do {
                try process.run()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }

        let out = String(decoding: stdoutData.snapshot(), as: UTF8.self)
        let err = String(decoding: stderrData.snapshot(), as: UTF8.self)
        let result = GrokCLIResult(stdout: out, stderr: err, exitCode: process.terminationStatus)
        if process.terminationStatus != 0 && !allowFailure {
            throw CLIError.failed(args: args, result: result)
        }
        return result
    }

    func listPlugins(includeAvailable: Bool = false) async throws -> [GrokPluginInfo] {
        var args = ["plugin", "list", "--json"]
        if includeAvailable { args.append("--available") }
        let json = try await jsonValue(args)
        return (json as? [[String: Any]] ?? []).map(GrokPluginInfo.init(dictionary:))
    }

    func listMarketplaceSources() async throws -> [GrokMarketplaceSource] {
        let json = try await jsonValue(["plugin", "marketplace", "list", "--json"])
        return (json as? [[String: Any]] ?? []).map(GrokMarketplaceSource.init(dictionary:))
    }

    func listHooks(cwd: URL? = nil) async throws -> [GrokHookInfo] {
        let json = try await jsonValue(["inspect", "--json"], cwd: cwd)
        let dictionary = json as? [String: Any] ?? [:]
        return (dictionary["hooks"] as? [[String: Any]] ?? []).map(GrokHookInfo.init(dictionary:))
    }

    func listSkills(cwd: URL? = nil) async throws -> [GrokSkillInfo] {
        let json = try await jsonValue(["inspect", "--json"], cwd: cwd)
        let dictionary = json as? [String: Any] ?? [:]
        return (dictionary["skills"] as? [[String: Any]] ?? []).map(GrokSkillInfo.init(dictionary:))
    }

    func pluginDetails(name: String) async throws -> String {
        try await run(["plugin", "details", name]).combinedOutput
    }

    func installPlugin(source: String, trust: Bool) async throws {
        var args = ["plugin", "install", source]
        if trust { args.append("--trust") }
        _ = try await run(args)
    }

    func uninstallPlugin(name: String, keepData: Bool) async throws {
        var args = ["plugin", "uninstall", name, "--confirm"]
        if keepData { args.append("--keep-data") }
        _ = try await run(args)
    }

    func setPlugin(name: String, enabled: Bool) async throws {
        _ = try await run(["plugin", enabled ? "enable" : "disable", name])
    }

    func updatePlugin(name: String?) async throws {
        var args = ["plugin", "update"]
        if let name, !name.isEmpty { args.append(name) }
        _ = try await run(args)
    }

    func addMarketplaceSource(_ source: String) async throws {
        _ = try await run(["plugin", "marketplace", "add", source])
    }

    func removeMarketplaceSource(_ source: String) async throws {
        _ = try await run(["plugin", "marketplace", "remove", source])
    }

    func listMCPServers() async throws -> [GrokMCPServerInfo] {
        let json = try await jsonValue(["mcp", "list", "--json"])
        return (json as? [[String: Any]] ?? []).map(GrokMCPServerInfo.init(dictionary:))
    }

    func mcpDoctor(name: String? = nil) async throws -> GrokMCPDoctorReport {
        var args = ["mcp", "doctor", "--json"]
        if let name, !name.isEmpty { args.append(name) }
        let json = try await jsonValue(args, allowFailure: true)
        return GrokMCPDoctorReport(dictionary: json as? [String: Any] ?? [:])
    }

    func addMCPServer(name: String, transport: String, target: String, scope: String) async throws {
        var args = ["mcp", "add", "--transport", transport, "--scope", scope, name]
        args += target.split(separator: " ").map(String.init)
        _ = try await run(args)
    }

    func removeMCPServer(name: String) async throws {
        _ = try await run(["mcp", "remove", name])
    }

    func listModels() async throws -> [GrokModelInfo] {
        let result = try await run(["models"])
        var models: [GrokModelInfo] = []
        for line in result.stdout.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { continue }
            let isDefault = trimmed.hasPrefix("* ")
            let raw = String(trimmed.dropFirst(2))
            let id = raw.replacingOccurrences(of: " (default)", with: "")
            models.append(GrokModelInfo(id: id, name: id, isDefault: isDefault))
        }
        return models
    }

    func listSessions(limit: Int = 30, cwd: URL? = nil) async throws -> [GrokSessionInfo] {
        let result = try await run(["sessions", "list", "--limit", "\(limit)"], cwd: cwd)
        return GrokSessionInfo.parseListOutput(result.stdout)
    }

    func searchSessions(query: String, limit: Int = 30, cwd: URL? = nil) async throws -> [GrokSessionInfo] {
        let result = try await run(["sessions", "search", "--limit", "\(limit)", query], cwd: cwd)
        return GrokSessionInfo.parseListOutput(result.stdout)
    }

    private func jsonValue(_ args: [String], cwd: URL? = nil, allowFailure: Bool = false) async throws -> Any {
        let result = try await run(args, cwd: cwd, allowFailure: allowFailure)
        let output = sanitizedJSONOutput(result.stdout)
        guard let data = output.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else {
            throw CLIError.invalidJSON(result.combinedOutput)
        }
        return value
    }

    private func sanitizedJSONOutput(_ output: String) -> String {
        let ansiPattern = #"\u{001B}\[[0-?]*[ -/]*[@-~]"#
        let noANSI = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
        let trimmed = noANSI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return trimmed }
        return String(trimmed[first...])
    }

    static func locateGrokCLI() -> URL? {
        if let path = ProcessInfo.processInfo.environment["GROK_CLI_PATH"], !path.isEmpty {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        for candidate in [
            "\(NSHomeDirectory())/.grok/bin/grok",
            "\(NSHomeDirectory())/bin/grok",
            "/opt/homebrew/bin/grok",
            "/usr/local/bin/grok"
        ] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("grok").path
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return URL(fileURLWithPath: candidate)
                }
            }
        }
        return nil
    }
}
