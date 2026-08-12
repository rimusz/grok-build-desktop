import Darwin
import Foundation

/// UserDefaults keys for the GrokBuild-managed Cursor bridge sidecar.
enum CursorBridgeSettingsKeys {
    /// When true, GrokBuild starts the bundled OpenAI `/v1` sidecar on launch (if an API key is set).
    /// Set automatically when the Cursor provider is installed; cleared when that provider is removed.
    /// Not exposed as a Settings toggle.
    static let managedEnabled = "GrokBuild.cursorBridge.managedEnabled"
}

/// Lifecycle for the optional embedded Cursor OpenAI bridge.
///
/// Starts a Node `@cursor/sdk` script on loopback port `18787` when the user enables Cursor
/// support and saves a `CURSOR_API_KEY` locally (Application Support). This is the only Cursor bridge path
/// GrokBuild supports (no external community proxies).
enum CursorBridgeRuntime {
    /// Fixed loopback port for the managed sidecar.
    static let managedPort = 18787

    /// Loopback endpoint written into imported `[model.*]` tables.
    static var managedEndpoint: CursorBridge.Endpoint { CursorBridge.managedEndpoint }

    enum Status: Equatable, Sendable {
        case stopped
        case starting
        case running
        case failed(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }

        var summary: String {
            switch self {
            case .stopped: return "Stopped"
            case .starting: return "Starting…"
            case .running: return "Running on 127.0.0.1:\(CursorBridgeRuntime.managedPort)"
            case .failed(let message): return message
            }
        }
    }

    /// Serial queue for process/status mutation (safe from async contexts; avoids NSLock-in-async).
    private static let queue = DispatchQueue(label: "com.grokbuild.cursor-bridge-runtime")
    private static var process: Process?
    private static var statusValue: Status = .stopped
    private static var stderrPipe: Pipe?
    /// When true, the next termination is from `stop()` and must not surface as a failure.
    private static var intentionalStop = false

    /// Posted on the main queue whenever `status` changes.
    static let statusDidChange = Notification.Name("GrokBuild.cursorBridgeRuntimeStatusDidChange")

    static var status: Status {
        queue.sync { statusValue }
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: CursorBridgeSettingsKeys.managedEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: CursorBridgeSettingsKeys.managedEnabled) }
    }

    static var isRunning: Bool { status.isRunning }

    /// True when status is `.running` *or* the managed port already answers `/v1/models`
    /// (e.g. after relaunch left an orphan sidecar). Never treat as running without a saved API key —
    /// an orphan may still listen after the secret was cleared. Pure for tests when flags are injected.
    static func shouldTreatAsRunning(status: Status, endpointOnline: Bool, hasAPIKey: Bool) -> Bool {
        guard hasAPIKey else { return false }
        return status.isRunning || endpointOnline
    }

    /// Orphan reattach is only allowed while a Cursor API key is still stored locally.
    static func mayReattachToLiveEndpoint(hasAPIKey: Bool, endpointOnline: Bool) -> Bool {
        hasAPIKey && endpointOnline
    }

    private static let missingAPIKeyMessage = "Add a Cursor API key to start the managed bridge."

    /// Pure helpers for tests / diagnostics (no process I/O).
    enum Locator {
        /// Resolves a Node binary suitable for the bridge (Node ≥ 22.13 preferred).
        static func nodeURL(fileManager: FileManager = .default, pathEnv: String? = ProcessInfo.processInfo.environment["PATH"]) -> URL? {
            let candidates = [
                "/opt/homebrew/bin/node",
                "/usr/local/bin/node",
                "\(NSHomeDirectory())/.local/bin/node",
                "\(NSHomeDirectory())/bin/node"
            ]
            for path in candidates where fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
            guard let pathEnv else { return nil }
            for dir in pathEnv.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("node")
                if fileManager.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
            return nil
        }

        /// Directory containing `cursor-openai-bridge.mjs` (+ installed `node_modules`).
        static func bridgeDirectory(
            bundle: Bundle = .main,
            fileManager: FileManager = .default,
            env: [String: String] = ProcessInfo.processInfo.environment
        ) -> URL? {
            if let override = env["GROKBUILD_CURSOR_BRIDGE_DIR"], !override.isEmpty {
                let url = URL(fileURLWithPath: override, isDirectory: true)
                if hasBridgeScript(at: url, fileManager: fileManager) { return url }
            }
            if let resources = bundle.resourceURL {
                let bundled = resources.appendingPathComponent("CursorBridge", isDirectory: true)
                if hasBridgeScript(at: bundled, fileManager: fileManager) { return bundled }
            }
            // Dev fallback: source tree next to a `make run` / swift build layout.
            if let exec = bundle.executableURL {
                let candidates = [
                    exec.deletingLastPathComponent() // Contents/MacOS
                        .deletingLastPathComponent() // Contents
                        .appendingPathComponent("Resources/CursorBridge", isDirectory: true),
                    exec.deletingLastPathComponent()
                        .deletingLastPathComponent()
                        .deletingLastPathComponent()
                        .appendingPathComponent("GrokBuild/Resources/CursorBridge", isDirectory: true)
                ]
                for url in candidates where hasBridgeScript(at: url, fileManager: fileManager) {
                    return url
                }
            }
            return nil
        }

        static func hasBridgeScript(at directory: URL, fileManager: FileManager = .default) -> Bool {
            fileManager.fileExists(atPath: directory.appendingPathComponent("cursor-openai-bridge.mjs").path)
        }

        static func hasValidateScript(at directory: URL, fileManager: FileManager = .default) -> Bool {
            fileManager.fileExists(atPath: directory.appendingPathComponent("cursor-validate-key.mjs").path)
        }

        static func hasNodeModules(at directory: URL, fileManager: FileManager = .default) -> Bool {
            fileManager.fileExists(atPath: directory.appendingPathComponent("node_modules/@cursor/sdk").path)
        }
    }

    /// Validates a Cursor API key via the bundled `cursor-validate-key.mjs` (`Cursor.models.list`).
    /// Call before saving the Cursor provider or starting the sidecar.
    static func validateAPIKey(_ apiKey: String) async -> CursorBridge.APIKeyValidation {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .missing }
        guard CursorBridge.looksLikeAPIKey(trimmed) else {
            return .rejected("Key looks too short or invalid. Paste the full key from Cursor Integrations.")
        }

        let nodeProbe = probeNode()
        guard nodeProbe.meetsMinimum, let nodePath = nodeProbe.binaryPath else {
            return CursorBridge.APIKeyValidation(isValid: false, message: nodeProbe.detail)
        }
        guard let bridgeDir = Locator.bridgeDirectory() else {
            return CursorBridge.APIKeyValidation(
                isValid: false,
                message: "Cursor bridge script is missing from the app bundle. Rebuild with make run / make app."
            )
        }
        guard Locator.hasValidateScript(at: bridgeDir), Locator.hasNodeModules(at: bridgeDir) else {
            return CursorBridge.APIKeyValidation(
                isValid: false,
                message: "Cursor bridge dependencies missing. Rebuild the app (npm install runs during packaging)."
            )
        }

        let script = bridgeDir.appendingPathComponent("cursor-validate-key.mjs")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: nodePath)
        proc.arguments = [script.path]
        proc.currentDirectoryURL = bridgeDir
        var environment = ProcessInfo.processInfo.environment
        environment["CURSOR_API_KEY"] = trimmed
        proc.environment = environment
        let err = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = err

        do {
            try proc.run()
        } catch {
            return CursorBridge.APIKeyValidation(
                isValid: false,
                message: "Could not validate Cursor API key: \(error.localizedDescription)"
            )
        }

        // Bound wait so a hung SDK call cannot block Settings forever.
        let deadline = Date().addingTimeInterval(45)
        while proc.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if proc.isRunning {
            proc.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
            }
            return CursorBridge.APIKeyValidation(
                isValid: false,
                message: "Timed out validating the Cursor API key. Check your network and try again."
            )
        }
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CursorBridge.validationResult(exitCode: proc.terminationStatus, stderr: stderr)
    }

    /// Locates `node` and reads `--version` (for Doctor / Settings install guidance).
    static func probeNode() -> CursorBridge.NodeRequirement.Snapshot {
        guard let node = Locator.nodeURL() else {
            return CursorBridge.NodeRequirement.snapshot(binaryPath: nil, versionDisplay: "")
        }
        let process = Process()
        process.executableURL = node
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CursorBridge.NodeRequirement.snapshot(binaryPath: node.path, versionDisplay: raw)
        } catch {
            return CursorBridge.NodeRequirement.snapshot(binaryPath: node.path, versionDisplay: "")
        }
    }

    /// Starts the sidecar when enabled + API key + Node + bridge script are available.
    /// Idempotent when already running, or when something is already serving the managed port
    /// *and* a key is still saved (common after `make run` leaves an orphan Node process).
    @discardableResult
    static func startIfNeeded() async -> Status {
        guard isEnabled else {
            stop()
            return status
        }

        guard let apiKey = CursorBridgeKeychain.load(), !apiKey.isEmpty else {
            await stopForMissingAPIKey()
            return status
        }

        // Already owned and running — skip re-validation until an explicit restart.
        if isRunning { return status }

        setStatus(.starting)
        let keyCheck = await validateAPIKey(apiKey)
        guard keyCheck.isValid else {
            // Tear down any orphan so a rejected key cannot keep serving on 18787.
            stop()
            setStatus(.failed(keyCheck.message))
            return status
        }

        // Reattach only after the stored key validates (orphan may still hold an older env key).
        if await endpointIsOnline() {
            setStatus(.running)
            return status
        }

        let nodeProbe = probeNode()
        guard nodeProbe.meetsMinimum, let nodePath = nodeProbe.binaryPath else {
            setStatus(.failed(nodeProbe.detail))
            return status
        }
        let node = URL(fileURLWithPath: nodePath)
        guard let bridgeDir = Locator.bridgeDirectory() else {
            setStatus(.failed("Cursor bridge script is missing from the app bundle. Rebuild with make run / make app."))
            return status
        }
        if !Locator.hasNodeModules(at: bridgeDir) {
            setStatus(.failed("Cursor bridge dependencies missing. Rebuild the app (npm install runs during packaging)."))
            return status
        }

        queue.sync { intentionalStop = false }

        let script = bridgeDir.appendingPathComponent("cursor-openai-bridge.mjs")
        let cwd = workspaceDirectory()
        try? FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = node
        proc.arguments = [script.path]
        proc.currentDirectoryURL = bridgeDir

        var environment = ProcessInfo.processInfo.environment
        environment["CURSOR_API_KEY"] = apiKey
        environment["CURSOR_BRIDGE_HOST"] = "127.0.0.1"
        environment["CURSOR_BRIDGE_PORT"] = "\(managedPort)"
        environment["CURSOR_BRIDGE_CWD"] = cwd.path
        proc.environment = environment

        let err = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = err
        proc.terminationHandler = { finished in
            handleTermination(finished)
        }

        do {
            try proc.run()
        } catch {
            if await endpointIsOnline() {
                setStatus(.running)
                return status
            }
            setStatus(.failed("Failed to start Node bridge: \(error.localizedDescription)"))
            return status
        }

        queue.sync {
            process = proc
            stderrPipe = err
        }

        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if !proc.isRunning {
                if await endpointIsOnline() {
                    cleanupProcess()
                    setStatus(.running)
                    return status
                }
                let message = readStderrSnippet(from: err) ?? "Bridge process exited early."
                setStatus(.failed(message))
                cleanupProcess()
                return status
            }
            let probe = await CursorBridge.probe(managedEndpoint, timeout: 1.5)
            if probe.isOnline {
                setStatus(.running)
                return status
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        if proc.isRunning {
            setStatus(.running)
            return status
        }
        if await endpointIsOnline() {
            cleanupProcess()
            setStatus(.running)
            return status
        }
        setStatus(.failed(readStderrSnippet(from: err) ?? "Bridge failed to become ready."))
        cleanupProcess()
        return status
    }

    /// Reconcile UI status with the live port (call when Settings appears).
    /// Without a saved API key, tears down any orphan listener so “Running” cannot outlive the key.
    @discardableResult
    static func reconcile() async -> Status {
        guard CursorBridgeKeychain.hasAPIKey() else {
            await stopForMissingAPIKey()
            return status
        }
        if await endpointIsOnline() {
            if !isRunning { setStatus(.running) }
            return status
        }
        let ownedRunning = queue.sync { process?.isRunning == true }
        if case .running = status, !ownedRunning {
            setStatus(.stopped)
        }
        return status
    }

    /// Called when the user clears the Cursor API key — always stop the sidecar.
    static func handleAPIKeyCleared() {
        stop()
        if isEnabled {
            setStatus(.failed(missingAPIKeyMessage))
        }
    }

    /// Stops owned + orphan listeners, then surfaces the missing-key failure when the bridge is enabled.
    private static func stopForMissingAPIKey() async {
        let online = await endpointIsOnline()
        let ownedRunning = queue.sync { process?.isRunning == true }
        if online || ownedRunning || isRunning {
            stop()
        }
        if isEnabled {
            setStatus(.failed(missingAPIKeyMessage))
        } else {
            setStatus(.stopped)
        }
    }

    /// Stops the sidecar process tree (best-effort terminate).
    static func stop() {
        let proc: Process? = queue.sync {
            intentionalStop = true
            let current = process
            process = nil
            stderrPipe = nil
            return current
        }
        if let proc, proc.isRunning {
            proc.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                if proc.isRunning {
                    kill(proc.processIdentifier, SIGKILL)
                }
            }
        }
        terminateOrphanListeners()
        setStatus(.stopped)
        queue.sync { intentionalStop = false }
    }

    /// Enable/disable preference and start or stop accordingly.
    static func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        if enabled {
            _ = await startIfNeeded()
        } else {
            stop()
        }
    }

    // MARK: - Internals

    private static func workspaceDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GrokBuild", isDirectory: true)
            .appendingPathComponent("cursor-bridge-workspace", isDirectory: true)
        return support
    }

    private static func setStatus(_ next: Status) {
        let changed: Bool = queue.sync {
            let didChange = statusValue != next
            statusValue = next
            return didChange
        }
        guard changed else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: statusDidChange, object: nil)
        }
    }

    private static func cleanupProcess() {
        queue.sync {
            process = nil
            stderrPipe = nil
        }
    }

    private static func endpointIsOnline() async -> Bool {
        let probe = await CursorBridge.probe(managedEndpoint, timeout: 1.5)
        return probe.isOnline
    }

    /// Best-effort kill of whatever is still listening on the managed port after we release our Process.
    private static func terminateOrphanListeners() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-tiTCP:\(managedPort)", "-sTCP:LISTEN"]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return }
        for line in text.split(whereSeparator: { $0.isNewline }) {
            guard let pid = Int32(line.trimmingCharacters(in: .whitespaces)) else { continue }
            kill(pid, SIGTERM)
        }
    }

    private static func handleTermination(_ finished: Process) {
        let snapshot: (current: Process?, pipe: Pipe?, status: Status, intentional: Bool) = queue.sync {
            (process, stderrPipe, statusValue, intentionalStop)
        }
        // Only react to the Process we currently own — ignore siblings that lost the port bind.
        guard snapshot.current === finished else { return }
        queue.sync {
            if process === finished {
                process = nil
                stderrPipe = nil
            }
        }
        if snapshot.intentional { return }
        if case .starting = snapshot.status {
            setStatus(.failed(readStderrSnippet(from: snapshot.pipe) ?? "Bridge process exited early."))
        } else if case .running = snapshot.status {
            // Defer failure: if the port is still live (orphan) *and* a key remains, keep "running".
            Task {
                if CursorBridgeKeychain.hasAPIKey(), await endpointIsOnline() {
                    setStatus(.running)
                } else if !CursorBridgeKeychain.hasAPIKey() {
                    await stopForMissingAPIKey()
                } else {
                    setStatus(.failed("Bridge process exited unexpectedly."))
                }
            }
        }
    }

    private static func readStderrSnippet(from pipe: Pipe?) -> String? {
        guard let pipe else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lines = trimmed.split(separator: "\n").suffix(4).joined(separator: " ")
        return String(lines.prefix(280))
    }
}
