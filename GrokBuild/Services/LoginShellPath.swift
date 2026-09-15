import Darwin
import Foundation

/// Finder/Dock-launched apps inherit launchd's minimal `PATH`
/// (`/usr/bin:/bin:/usr/sbin:/sbin`), so agent shells miss Homebrew tools like `gh`.
/// At launch we ask the user's login shell for its `PATH` and merge it into this
/// process. Only `PATH` is imported — not `SSH_AUTH_SOCK`, API keys, or `JAVA_HOME`.
enum LoginShellPath {
    static let skipEnvVar = "GROKBUILD_SKIP_SHELL_PATH"
    static let markerStart = "__GROKBUILD_PATH_START__"
    static let markerEnd = "__GROKBUILD_PATH_END__"
    static let defaultTimeout: TimeInterval = 2
    static let launchdPATH = "/usr/bin:/bin:/usr/sbin:/sbin"

    enum ApplyStatus: Equatable, Sendable {
        case applied(shell: String, pathEntries: Int)
        case skipped(reason: String)
        case failed(shell: String)

        var doctorDetail: String {
            switch self {
            case .applied(_, let count):
                return "Merged your login-shell PATH (\(count) entries) so Dock/Finder sessions can find Homebrew tools."
            case .skipped(let reason) where reason == LoginShellPath.skipEnvVar:
                return "Skipped — \(LoginShellPath.skipEnvVar) is set."
            case .skipped:
                return "Not applied yet."
            case .failed:
                return "Could not read the login-shell PATH — using launchd PATH. Homebrew tools like gh may be missing."
            }
        }

        var doctorStatus: DoctorCheck.Status {
            switch self {
            case .applied: return .ok
            case .failed: return .warning
            case .skipped: return .info
            }
        }
    }

    private static let statusLock = NSLock()
    private static var storedStatus: ApplyStatus = .skipped(reason: "not applied")

    static var lastStatus: ApplyStatus {
        statusLock.lock()
        defer { statusLock.unlock() }
        return storedStatus
    }

    /// `PATH` after `applyToCurrentProcess()`, else the current process environment.
    static func currentPATH(from environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let pointer = getenv("PATH") {
            let value = String(cString: pointer)
            if !value.isEmpty { return value }
        }
        return environment["PATH"] ?? launchdPATH
    }

    /// Snapshot of the process environment with login-shell `PATH` applied.
    static func inheritedEnvironment(
        _ base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        environment["PATH"] = currentPATH(from: base)
        return environment
    }

    static func merge(_ shellPath: String, with currentPath: String) -> String {
        var seen = Set<String>()
        var entries: [String] = []
        for raw in (shellPath.split(separator: ":") + currentPath.split(separator: ":")) {
            let entry = raw.trimmingCharacters(in: .whitespaces)
            guard !entry.isEmpty, seen.insert(entry).inserted else { continue }
            entries.append(entry)
        }
        return entries.joined(separator: ":")
    }

    static func extractMarkedPath(from output: String) -> String? {
        guard let start = output.range(of: markerStart) else { return nil }
        let afterStart = output[start.upperBound...]
        guard let end = afterStart.range(of: markerEnd) else { return nil }
        let value = afterStart[..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value)
    }

    /// Account-database shell first (`getpwuid`), then `$SHELL`, then `/bin/zsh`.
    static func loginShell(
        passwdShell: String?,
        environment: [String: String]
    ) -> String {
        if let passwdShell, !passwdShell.trimmingCharacters(in: .whitespaces).isEmpty {
            return passwdShell
        }
        if let shell = environment["SHELL"]?.trimmingCharacters(in: .whitespaces), !shell.isEmpty {
            return shell
        }
        return "/bin/zsh"
    }

    static func shellInvocation(shell: String, command: String) -> [String] {
        let kind = URL(fileURLWithPath: shell).lastPathComponent
        if kind == "csh" || kind == "tcsh" {
            return ["-c", command]
        }
        return ["-i", "-l", "-c", command]
    }

    static var printPathCommand: String {
        "/bin/sh -c 'printf \"%s%s%s\" \"\(markerStart)\" \"$PATH\" \"\(markerEnd)\"'"
    }

    @discardableResult
    static func apply(
        environment: [String: String],
        passwdShell: String?,
        resolve: (String, TimeInterval) -> String?,
        setPATH: (String) -> Void
    ) -> ApplyStatus {
        if let skip = environment[skipEnvVar]?.trimmingCharacters(in: .whitespaces), !skip.isEmpty {
            return record(.skipped(reason: skipEnvVar))
        }

        let userShell = loginShell(passwdShell: passwdShell, environment: environment)
        let fallback = "/bin/zsh"
        var attempts: [(shell: String, timeout: TimeInterval)] = [(userShell, defaultTimeout)]
        if userShell != fallback {
            attempts.append((fallback, defaultTimeout / 2))
        }

        let current = environment["PATH"] ?? ""
        for attempt in attempts {
            guard let shellPath = resolve(attempt.shell, attempt.timeout) else { continue }
            let merged = merge(shellPath, with: current)
            setPATH(merged)
            let count = merged.split(separator: ":").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            return record(.applied(shell: attempt.shell, pathEntries: count))
        }
        return record(.failed(shell: userShell))
    }

    /// Merge login-shell `PATH` into this process via `setenv`. Failures never block launch.
    @discardableResult
    static func applyToCurrentProcess() -> ApplyStatus {
        apply(
            environment: ProcessInfo.processInfo.environment,
            passwdShell: passwdLoginShell(),
            resolve: { shell, timeout in capturePATH(fromShell: shell, timeout: timeout) },
            setPATH: { path in
                path.withCString { _ = setenv("PATH", $0, 1) }
            }
        )
    }

    static func passwdLoginShell() -> String? {
        guard let pw = getpwuid(getuid()) else { return nil }
        let shell = String(cString: pw.pointee.pw_shell)
        let trimmed = shell.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func capturePATH(fromShell shell: String, timeout: TimeInterval) -> String? {
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = shellInvocation(shell: shell, command: printPathCommand)
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            return nil
        }
        process.waitUntilExit()
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return extractMarkedPath(from: output)
    }

    @discardableResult
    private static func record(_ status: ApplyStatus) -> ApplyStatus {
        statusLock.lock()
        storedStatus = status
        statusLock.unlock()
        return status
    }
}
