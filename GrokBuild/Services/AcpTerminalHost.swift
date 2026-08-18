import Foundation

/// JSON-RPC errors for ACP `terminal/*` host methods.
enum AcpTerminalError: Error, Equatable {
    case missingCommand
    case missingTerminalId
    case unknownTerminal
    case launchFailed(String)

    var jsonRPC: [String: Any] {
        switch self {
        case .missingCommand:
            return ["code": -32602, "message": "terminal/create requires command"]
        case .missingTerminalId:
            return ["code": -32602, "message": "terminal request requires terminalId"]
        case .unknownTerminal:
            return ["code": -32602, "message": "Unknown terminalId"]
        case .launchFailed(let message):
            return ["code": -32000, "message": message]
        }
    }
}

enum AcpTerminalWait {
    case alreadyExited([String: Any])
    case pending
}

/// Runs shell commands for grok's ACP `terminal/*` client methods.
///
/// `initialize` advertises `clientCapabilities.terminal = true`, so grok routes
/// its agent shell through these RPCs. An empty `{}` ACK makes the CLI fail with
/// "failed to deserialize response".
final class AcpTerminalHost: @unchecked Sendable {
    static let defaultOutputByteLimit = 2_000_000

    private let lock = NSLock()
    private var sessions: [String: Session] = [:]

    private final class Session {
        let id: String
        let process: Process
        let byteLimit: Int
        var output = Data()
        var truncated = false
        var exitStatus: [String: Any]?
        var waiters: [([String: Any]) -> Void] = []

        init(id: String, process: Process, byteLimit: Int) {
            self.id = id
            self.process = process
            self.byteLimit = byteLimit
        }
    }

    func create(params: [String: Any], defaultCwd: URL) throws -> [String: Any] {
        guard let request = Self.parseCreateRequest(params) else {
            throw AcpTerminalError.missingCommand
        }
        let cwd = resolvedCwd(request.cwd, defaultCwd: defaultCwd)
        let launch = Self.resolveLaunch(command: request.command, args: request.args)
        let id = "term_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.exe)
        process.arguments = launch.args
        process.currentDirectoryURL = cwd
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in request.env {
            environment[key] = value
        }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let session = Session(id: id, process: process, byteLimit: request.byteLimit)
        pipe.fileHandleForReading.readabilityHandler = { [weak self, weak session] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let session else { return }
            self?.appendOutput(chunk, to: session)
        }
        process.terminationHandler = { [weak self, weak session] finished in
            guard let self, let session else { return }
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = nil
            let leftover = handle.availableData
            if !leftover.isEmpty {
                self.appendOutput(leftover, to: session)
            }
            let status = Self.exitStatusJSON(
                reason: finished.terminationReason,
                status: finished.terminationStatus
            )
            let waiters: [([String: Any]) -> Void]
            self.lock.lock()
            session.exitStatus = status
            waiters = session.waiters
            session.waiters.removeAll()
            self.lock.unlock()
            let payload = Self.waitResponse(from: status)
            for waiter in waiters {
                waiter(payload)
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            throw AcpTerminalError.launchFailed(error.localizedDescription)
        }

        lock.lock()
        sessions[id] = session
        lock.unlock()
        return ["terminalId": id]
    }

    func output(terminalId: String) throws -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        guard let session = sessions[terminalId] else { throw AcpTerminalError.unknownTerminal }
        var result: [String: Any] = [
            "output": String(decoding: session.output, as: UTF8.self),
            "truncated": session.truncated
        ]
        if let exitStatus = session.exitStatus {
            result["exitStatus"] = exitStatus
        }
        return result
    }

    func waitForExit(terminalId: String, onExit: @escaping ([String: Any]) -> Void) throws -> AcpTerminalWait {
        lock.lock()
        defer { lock.unlock() }
        guard let session = sessions[terminalId] else { throw AcpTerminalError.unknownTerminal }
        if let exitStatus = session.exitStatus {
            return .alreadyExited(Self.waitResponse(from: exitStatus))
        }
        session.waiters.append(onExit)
        return .pending
    }

    func kill(terminalId: String) throws -> [String: Any] {
        lock.lock()
        let session = sessions[terminalId]
        lock.unlock()
        guard let session else { throw AcpTerminalError.unknownTerminal }
        if session.process.isRunning {
            session.process.terminate()
        }
        return [:]
    }

    func release(terminalId: String) throws -> [String: Any] {
        lock.lock()
        let session = sessions.removeValue(forKey: terminalId)
        lock.unlock()
        guard let session else { throw AcpTerminalError.unknownTerminal }
        tearDown(session)
        return [:]
    }

    func releaseAll() {
        lock.lock()
        let all = Array(sessions.values)
        sessions.removeAll()
        lock.unlock()
        for session in all {
            tearDown(session)
        }
    }

    // MARK: - Parsing / JSON (testable)

    static func parseCreateRequest(_ params: [String: Any]) -> (
        command: String,
        args: [String],
        cwd: String?,
        env: [String: String],
        byteLimit: Int
    )? {
        var args = (params["args"] as? [String]) ?? []
        let command: String
        if let value = params["command"] as? String {
            command = value
        } else if let tokens = params["command"] as? [Any] {
            let strings = tokens.compactMap { $0 as? String }
            guard let first = strings.first else { return nil }
            command = first
            args = Array(strings.dropFirst()) + args
        } else if let value = params["commandLine"] as? String ?? params["cmd"] as? String {
            command = value
        } else {
            return nil
        }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cwd = params["cwd"] as? String
        var env: [String: String] = [:]
        if let list = params["env"] as? [[String: Any]] {
            for item in list {
                if let name = item["name"] as? String, let value = item["value"] as? String {
                    env[name] = value
                }
            }
        } else if let dict = params["env"] as? [String: Any] {
            for (name, raw) in dict {
                if let value = raw as? String {
                    env[name] = value
                }
            }
        }
        let byteLimit: Int
        if let value = params["outputByteLimit"] as? Int {
            byteLimit = max(0, value)
        } else if let value = params["outputByteLimit"] as? NSNumber {
            byteLimit = max(0, value.intValue)
        } else {
            byteLimit = defaultOutputByteLimit
        }
        return (trimmed, args, cwd, env, byteLimit)
    }

    static func resolveLaunch(command: String, args: [String]) -> (exe: String, args: [String]) {
        let tokens = splitCommandLine(command)
        let exeToken: String
        let extraArgs: [String]
        if tokens.count >= 2 {
            exeToken = tokens[0]
            extraArgs = Array(tokens.dropFirst()) + args
        } else if tokens.count == 1 {
            exeToken = tokens[0]
            extraArgs = args
        } else {
            return ("/bin/zsh", ["-c", shellJoin([command] + args)])
        }

        if exeToken.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: exeToken) {
            return (exeToken, extraArgs)
        }
        if !exeToken.contains("/"), let resolved = lookupInPath(exeToken) {
            return (resolved, extraArgs)
        }
        return ("/bin/zsh", ["-c", shellJoin([command] + args)])
    }

    /// Split `bash -lc 'echo hi'` into `["bash", "-lc", "echo hi"]` so Process never
    /// treats the whole line as a single executable path.
    static func splitCommandLine(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if let active = quote {
                if character == active {
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    static func truncateFromStart(_ data: Data, byteLimit: Int) -> (data: Data, truncated: Bool) {
        guard byteLimit >= 0, data.count > byteLimit else { return (data, false) }
        var start = data.count - byteLimit
        let bytes = [UInt8](data)
        while start < bytes.count && (bytes[start] & 0xC0) == 0x80 {
            start += 1
        }
        return (Data(bytes[start...]), true)
    }

    static func exitStatusJSON(reason: Process.TerminationReason, status: Int32) -> [String: Any] {
        if reason == .uncaughtSignal {
            return ["exitCode": NSNull(), "signal": signalName(status)]
        }
        return ["exitCode": Int(status), "signal": NSNull()]
    }

    static func exitStatus(from process: Process) -> [String: Any] {
        if process.isRunning {
            return exitStatusJSON(reason: .uncaughtSignal, status: 15)
        }
        return exitStatusJSON(reason: process.terminationReason, status: process.terminationStatus)
    }

    static func waitResponse(from exitStatus: [String: Any]) -> [String: Any] {
        [
            "exitCode": exitStatus["exitCode"] ?? NSNull(),
            "signal": exitStatus["signal"] ?? NSNull()
        ]
    }

    static func signalName(_ status: Int32) -> String {
        switch status {
        case 1: return "SIGHUP"
        case 2: return "SIGINT"
        case 9: return "SIGKILL"
        case 15: return "SIGTERM"
        default: return String(status)
        }
    }

    // MARK: - Private

    private func appendOutput(_ chunk: Data, to session: Session) {
        lock.lock()
        defer { lock.unlock() }
        session.output.append(chunk)
        let trimmed = Self.truncateFromStart(session.output, byteLimit: session.byteLimit)
        session.output = trimmed.data
        if trimmed.truncated {
            session.truncated = true
        }
    }

    private func tearDown(_ session: Session) {
        if let handle = (session.process.standardOutput as? Pipe)?.fileHandleForReading {
            handle.readabilityHandler = nil
        }
        if session.process.isRunning {
            session.process.terminate()
        }
        lock.lock()
        let waiters = session.waiters
        session.waiters.removeAll()
        let status = session.exitStatus ?? Self.exitStatus(from: session.process)
        session.exitStatus = status
        lock.unlock()
        let payload = Self.waitResponse(from: status)
        for waiter in waiters {
            waiter(payload)
        }
    }

    private func resolvedCwd(_ cwd: String?, defaultCwd: URL) -> URL {
        guard let cwd, !cwd.isEmpty else { return defaultCwd }
        if cwd.hasPrefix("/") {
            return URL(fileURLWithPath: cwd, isDirectory: true)
        }
        return defaultCwd.appendingPathComponent(cwd).standardizedFileURL
    }

    private static func lookupInPath(_ command: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(command).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func shellJoin(_ tokens: [String]) -> String {
        tokens.map { token in
            if token.isEmpty { return "''" }
            if token.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-/=+:,@%")).contains($0) }) {
                return token
            }
            return "'" + token.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ")
    }
}
