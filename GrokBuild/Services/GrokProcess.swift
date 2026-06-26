import Foundation
import Observation

enum GrokProcessState: Sendable, Equatable {
    case idle
    case starting
    case ready
    case busy
    case failed(String)

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

struct GrokLaunchOptions: Sendable {
    var agent: String? = nil  // advanced: for custom --agent profiles only (built-in personas removed)
    var extraArgs: [String] = []
    var noMemory: Bool = false
    var permissionMode: String? = nil
    var reasoningEffort: String? = nil   // passed to `grok agent --reasoning-effort X stdio`
    var model: String? = nil             // e.g. model name like "gpt-5.5-extra-high" or grok variant
    var sandboxProfile: String? = nil
    var disableWebSearch: Bool = false
    var noSubagents: Bool = false
    var allowRules: [String] = []
    var denyRules: [String] = []
    var resumeSessionID: String? = nil
    var mcpServers: [MCPServerConfig] = []
}

// MARK: - Typed ACP Models

struct AgentMode: RawRepresentable, Sendable, Hashable, Equatable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    // Grok CLI modes for the bottom selector (Agent / Plan / Yolo)
    static let agent = AgentMode(rawValue: "agent")
    static let plan  = AgentMode(rawValue: "plan")
    static let yolo  = AgentMode(rawValue: "yolo")
}

struct ToolCall: @unchecked Sendable, Identifiable, Hashable {
    let id: String          // toolCallId
    let kind: String
    let title: String
    let rawInput: [String: Any]?

    var identifier: String { id }

    // Improved specifics
    var isEdit: Bool {
        let k = kind.lowercased()
        return k == "edit" || k == "write" || k == "write_file" || k.contains("edit")
    }

    var isExecute: Bool {
        let k = kind.lowercased()
        return k == "execute" || k == "terminal" || k == "run" || k.contains("exec")
    }

    var filePath: String? {
        if let path = rawInput?["path"] as? String { return path }
        if let file = rawInput?["file"] as? String { return file }
        if let args = rawInput?["args"] as? [String], let first = args.first, first.hasPrefix("/") || first.contains(".") {
            return first
        }
        return nil
    }

    var proposedContent: String? {
        if let content = rawInput?["content"] as? String { return content }
        if let newText = rawInput?["newText"] as? String { return newText }
        if let text = rawInput?["text"] as? String { return text }
        if let patch = rawInput?["patch"] as? String { return patch }
        return nil
    }

    var oldContent: String? {
        if let old = rawInput?["oldContent"] as? String { return old }
        if let original = rawInput?["original"] as? String { return original }
        return nil
    }

    var command: String? {
        if let cmd = rawInput?["command"] as? String { return cmd }
        if let cmd = rawInput?["cmd"] as? String { return cmd }
        if let args = rawInput?["args"] as? [String] { return args.joined(separator: " ") }
        return nil
    }

    // More specific kinds
    var editFilePath: String? { filePath }
    var executeCommand: String? { command }

    static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct PermissionOption: Sendable, Identifiable, Hashable {
    let id: String          // optionId
    let kind: String        // "allow_always", "allow_once", "reject_once", etc.
    let name: String

    var identifier: String { id }
}

struct PermissionRequest: @unchecked Sendable, Identifiable, Hashable {
    let id: AnyHashable     // request id from protocol (can be Int or String)
    let sessionId: String
    let toolCall: ToolCall
    let options: [PermissionOption]

    var identifier: AnyHashable { id }
}

// MARK: - Structured ACP Events

enum AcpEvent: @unchecked Sendable {
    case messageChunk(text: String)
    case thoughtChunk(text: String)
    case toolCall(ToolCall)
    case toolCallUpdate(ToolCall)   // simplified
    case plan(payload: [String: Any])
    case planFileContent(String)
    case exitPlanRequest(ExitPlanRequest)
    case questionRequest(QuestionRequest)
    case permissionRequest(PermissionRequest)
    case modeChanged(mode: AgentMode)
    case contextUsage(totalTokens: Int)
    case availableCommands([SlashCommand])
    case rawLine(String)
    case error(String)
}

/// ACP client for `grok agent stdio`.
/// Replaces the old TUI scraping approach with proper JSON-RPC.
@Observable
final class GrokProcess: @unchecked Sendable {
    private let ioLock = NSLock()
    private(set) var state: GrokProcessState = .idle
    private(set) var currentWorkspace: Workspace?
    private(set) var outputLines: [String] = []

    var needsAuthentication: Bool {
        if case .failed(let message) = state {
            let m = message.lowercased()
            return m.contains("login") || m.contains("auth") || m.contains("not authenticated")
        }
        return false
    }

    /// Preferred: structured ACP events.
    var acpEventStream: AsyncStream<AcpEvent> { _acpEventStream }
    private let _acpEventStream: AsyncStream<AcpEvent>
    private var acpEventContinuation: AsyncStream<AcpEvent>.Continuation?

    /// Legacy text stream for incremental migration.
    var outputStream: AsyncStream<String> { _outputStream }
    private let _outputStream: AsyncStream<String>
    private var outputContinuation: AsyncStream<String>.Continuation?

    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: Pipe?
    private var stderr: Pipe?
    private var readerTask: Task<Void, Never>?
    private var stdoutBuffer = ""
    private var startupStderr = ""

    private var nextRequestId = 1
    private struct PendingRequest {
        let continuation: CheckedContinuation<Any?, Error>
        let timeoutTask: Task<Void, Never>?
    }
    private var pendingRequests: [Int: PendingRequest] = [:]
    private(set) var sessionId: String?
    private(set) var currentMode: AgentMode = .agent
    private(set) var availableModes: [AgentMode] = [.agent, .plan, .yolo]
    private(set) var currentModelId: String?
    /// Set when a model switch fails or times out; the UI can surface and then clear it.
    var modelSwitchError: String?
    /// Set when the failed switch is recoverable by starting a new session (the agent
    /// returned `MODEL_SWITCH_INCOMPATIBLE_AGENT` / suggested `start_new_session`).
    var modelSwitchNeedsNewSession = false
    /// True while a `session/set_model` RPC is in-flight; cleared (false) on success or failure.
    /// Use this rather than `currentModelId` to detect completion, since `currentModelId` is
    /// set optimistically and cannot distinguish "pending" from "confirmed".
    var modelSwitchPending = false

    // Populated from initialize modelState so we use real models from grok CLI
    private(set) var availableModelsInfo: [(id: String, name: String, contextTokens: Int?)] = []
    private(set) var availableSlashCommands: [SlashCommand] = []
    private var latestPlanFileContent = ""

    // MARK: - Parsing helpers (instance for access to state if needed)

    private func parseToolCall(from payload: [String: Any]) -> ToolCall? {
        // Support multiple wire shapes from grok agent stdio
        let tool = payload["toolCall"] as? [String: Any]
            ?? payload["tool_call"] as? [String: Any]
            ?? payload // direct in some updates

        let tcid = (tool["toolCallId"] as? String)
            ?? (tool["tool_call_id"] as? String)
            ?? (tool["id"] as? String)
            ?? UUID().uuidString

        var raw = tool["rawInput"] as? [String: Any]
            ?? tool["raw_input"] as? [String: Any]
            ?? tool["input"] as? [String: Any]
            ?? tool["arguments"] as? [String: Any]
            ?? tool["args"] as? [String: Any]
            ?? [:]

        if let toolName = tool["toolName"] as? String ?? tool["tool_name"] as? String {
            raw["toolName"] = toolName
        }
        if let serverName = tool["serverName"] as? String ?? tool["server_name"] as? String {
            raw["serverName"] = serverName
        }

        let rawToolName = raw["toolName"] as? String
            ?? raw["tool_name"] as? String
            ?? raw["name"] as? String
            ?? raw["tool"] as? String

        let kind = (tool["kind"] as? String)
            ?? (tool["type"] as? String)
            ?? rawToolName.map { toolKind(for: $0) }
            ?? "unknown"

        let title = (tool["title"] as? String)
            ?? (tool["name"] as? String)
            ?? rawToolName.map { displayToolName($0) }
            ?? (kind == "unknown" ? "Tool call" : kind)

        // More parsing for specific kinds (edit, execute, etc.)
        if let path = tool["path"] as? String { raw["path"] = path }
        if let content = tool["content"] as? String { raw["content"] = content }
        if let cmd = tool["command"] as? String { raw["command"] = cmd }
        if let newText = tool["newText"] as? String { raw["newText"] = newText }

        return ToolCall(id: tcid, kind: kind, title: title, rawInput: raw.isEmpty ? nil : raw)
    }

    private func toolKind(for toolName: String) -> String {
        if toolName.hasPrefix("browser_") { return "browser" }
        if toolName.localizedCaseInsensitiveContains("read") { return "read" }
        if toolName.localizedCaseInsensitiveContains("write") || toolName.localizedCaseInsensitiveContains("edit") {
            return "edit"
        }
        return "tool"
    }

    private func displayToolName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    private func parsePermissionRequest(id: Any?, params: [String: Any]) -> PermissionRequest? {
        guard let sid = params["sessionId"] as? String ?? params["session_id"] as? String,
              let toolDict = params["toolCall"] as? [String: Any] ?? params["tool_call"] as? [String: Any],
              let tool = parseToolCall(from: ["toolCall": toolDict]) else { return nil }

        let optionsArray = (params["options"] as? [[String: Any]]) ?? []
        let options = optionsArray.compactMap { opt -> PermissionOption? in
            guard let oid = opt["optionId"] as? String ?? opt["option_id"] as? String,
                  let okind = opt["kind"] as? String else { return nil }
            let oname = opt["name"] as? String ?? okind
            return PermissionOption(id: oid, kind: okind, name: oname)
        }

        let reqId: AnyHashable = (id as? Int).map { AnyHashable($0) } ?? AnyHashable(id as? String ?? UUID().uuidString)
        return PermissionRequest(id: reqId, sessionId: sid, toolCall: tool, options: options)
    }

    init() {
        var acpC: AsyncStream<AcpEvent>.Continuation!
        _acpEventStream = AsyncStream(bufferingPolicy: .unbounded) { acpC = $0 }
        acpEventContinuation = acpC

        var txtC: AsyncStream<String>.Continuation!
        _outputStream = AsyncStream(bufferingPolicy: .unbounded) { txtC = $0 }
        outputContinuation = txtC
    }

    // MARK: - Lifecycle

    func start(workspace: Workspace, options: GrokLaunchOptions = .init()) async {
        await stop()

        state = .starting
        currentWorkspace = workspace
        outputLines.removeAll()
        sessionId = nil
        currentModelId = nil
        availableModelsInfo.removeAll()

        guard let cli = Self.locateGrokCLI() else {
            state = .failed("Could not locate the `grok` CLI. Run `grok login` or set GROK_CLI_PATH.")
            return
        }

        let proc = Process()
        proc.executableURL = cli
        proc.currentDirectoryURL = workspace.path
        proc.environment = ProcessInfo.processInfo.environment

        // ACP: grok [top-level flags] agent [agent flags] stdio
        var args: [String] = []
        if let a = options.agent, !a.isEmpty { args += ["--agent", a] }
        if options.noMemory { args.append("--no-memory") }
        if let mode = options.permissionMode, !mode.isEmpty, mode != "default" {
            args += ["--permission-mode", mode]
        }
        if let sandbox = options.sandboxProfile, !sandbox.isEmpty {
            args += ["--sandbox", sandbox]
        }
        if options.disableWebSearch { args.append("--disable-web-search") }
        if options.noSubagents { args.append("--no-subagents") }
        for rule in options.allowRules where !rule.isEmpty {
            args += ["--allow", rule]
        }
        for rule in options.denyRules where !rule.isEmpty {
            args += ["--deny", rule]
        }

        args.append("agent")
        if let e = options.reasoningEffort, !e.isEmpty {
            args += ["--reasoning-effort", e]
        }
        if let m = options.model, !m.isEmpty {
            args += ["--model", m]
        }
        args.append("stdio")
        args += options.extraArgs

        proc.arguments = args

        let i = Pipe(), o = Pipe(), e = Pipe()
        proc.standardInput = i
        proc.standardOutput = o
        proc.standardError = e

        do { try proc.run() } catch {
            state = .failed("Failed to launch: \(error.localizedDescription)")
            return
        }

        self.process = proc
        self.stdin = i.fileHandleForWriting
        self.stdout = o
        self.stderr = e
        self.stdoutBuffer = ""
        self.startupStderr = ""

        setupReaders(stdout: o, stderr: e)

        do {
            try await initializeACP()
            if let resumeSessionID = options.resumeSessionID, !resumeSessionID.isEmpty {
                try await loadSession(id: resumeSessionID, workspace: workspace, mcpServers: options.mcpServers)
            } else {
                try await createSession(workspace: workspace, mcpServers: options.mcpServers)
            }
            state = .ready
            notifyStatus()
        } catch {
            let stderrDetails = startupStderrSnapshot()
            let suffix = stderrDetails.isEmpty ? "" : "\n\(stderrDetails)"
            state = .failed("ACP initialize failed: \(error.localizedDescription)\(suffix)")
            await cleanupProcess(setIdle: false)
            notifyStatus()
        }
    }

    func stop() async {
        await cleanupProcess(setIdle: true)
    }

    private func cleanupProcess(setIdle: Bool) async {
        readerTask?.cancel()
        readerTask = nil
        stdout?.fileHandleForReading.readabilityHandler = nil
        stderr?.fileHandleForReading.readabilityHandler = nil

        if let sid = sessionId {
            _ = writeJson(["jsonrpc": "2.0", "method": "session/cancel", "params": ["sessionId": sid]])
        }
        try? stdin?.close()

        if let p = process, p.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
            if p.isRunning { p.terminate() }
        }

        process = nil
        stdin = nil
        stdout = nil
        stderr = nil
        sessionId = nil
        drainPendingRequests(with: NSError(
            domain: "ACP",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "Grok process stopped."]
        ))

        acpEventContinuation?.yield(.rawLine("[process stopped]"))
        outputContinuation?.yield("\n[process stopped]\n")
        if setIdle {
            state = .idle
        }
        currentWorkspace = nil
        notifyStatus()
    }

    // MARK: - Public API

    @discardableResult
    func send(_ text: String) async -> Bool {
        guard let sid = sessionId, state == .ready || state == .busy else { return false }
        state = .busy
        notifyStatus()
        outputContinuation?.yield("<<USER>> \(text)\n")

        do {
            _ = try await sendRequest(method: "session/prompt", params: [
                "sessionId": sid,
                "prompt": [["type": "text", "text": text]]
            ])
            state = .ready
            notifyStatus()
            return true
        } catch {
            state = .failed("Prompt error: \(error.localizedDescription)")
            notifyStatus()
            return false
        }
    }

    func interrupt() {
        guard let sid = sessionId else { return }
        _ = writeJson(["jsonrpc": "2.0", "method": "session/cancel", "params": ["sessionId": sid]])
    }

    // MARK: - Responding to agent requests

    func respondToPermission(_ request: PermissionRequest, with optionId: String) {
        _ = writeJson([
            "jsonrpc": "2.0",
            "id": request.id.base as Any,
            "result": ["outcome": ["outcome": "selected", "optionId": optionId]]
        ])
    }

    func respondToExitPlan(_ planRequestId: Any, verdict: ExitPlanRequest.PlanVerdict) {
        switch verdict {
        case .approved:
            _ = writeJson(["jsonrpc": "2.0", "id": planRequestId, "result": ["outcome": "approved"]])
        case .rejected:
            _ = writeJson(["jsonrpc": "2.0", "id": planRequestId, "error": ["code": -32000, "message": "User rejected the plan"]])
        case .abandoned:
            _ = writeJson(["jsonrpc": "2.0", "id": planRequestId, "error": ["code": -32000, "message": "User abandoned the plan"]])
        }
    }

    func respondToQuestion(_ requestId: Any, answers: [String: String]) {
        _ = writeJson([
            "jsonrpc": "2.0",
            "id": requestId,
            "result": ["outcome": "accepted", "answers": answers, "annotations": [:] as [String: Any]]
        ])
    }

    func respondToQuestionCancelled(_ requestId: Any) {
        _ = writeJson(["jsonrpc": "2.0", "id": requestId, "result": ["outcome": "cancelled"]])
    }

    // MARK: - Mode switching

    func setMode(_ mode: AgentMode) {
        guard let sid = sessionId else { return }
        Task {
            _ = try? await sendRequest(method: "session/set_mode", params: [
                "sessionId": sid,
                "modeId": mode.rawValue
            ])
        }
    }

    func setMode(_ modeId: String) {
        setMode(AgentMode(rawValue: modeId))
    }

    func setModel(_ modelId: String) {
        guard let sid = sessionId else { return }
        let previous = currentModelId
        // Optimistically reflect the selection; revert if grok rejects/stalls the switch.
        currentModelId = modelId
        modelSwitchPending = true
        Task {
            defer { modelSwitchPending = false }
            do {
                // Switching is a control op and should be fast — bound it so a stalled
                // set_model can never leave the UI stuck.
                let res = try await sendRequestWithTimeout(method: "session/set_model", params: [
                    "sessionId": sid,
                    "modelId": modelId
                ], seconds: 12) as? [String: Any]
                if let meta = res?["_meta"] as? [String: Any],
                   let model = meta["model"] as? [String: Any],
                   let selected = model["Ok"] as? String {
                    currentModelId = selected
                } else {
                    currentModelId = modelId
                }
            } catch {
                // Timed out or failed — restore the previous selection and surface the error.
                currentModelId = previous
                let ns = error as NSError
                let code = ns.userInfo["acpErrorCode"] as? String
                let suggestion = ns.userInfo["acpSuggestion"] as? String
                if code == "MODEL_SWITCH_INCOMPATIBLE_AGENT" || suggestion == "start_new_session" {
                    // The agent's message already explains the incompatibility and the fix.
                    modelSwitchError = ns.localizedDescription
                    modelSwitchNeedsNewSession = true
                } else {
                    modelSwitchError = "Couldn't switch to \(modelId): \(ns.localizedDescription)"
                    modelSwitchNeedsNewSession = false
                }
            }
        }
    }

    // MARK: - ACP Implementation

    private func writeJson(_ obj: [String: Any]) -> Bool {
        guard let h = stdin else { return false }
        let data: Data
        if #available(macOS 12.0, *) {
            guard let encoded = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.withoutEscapingSlashes]
            ) else { return false }
            data = encoded
        } else {
            guard let encoded = try? JSONSerialization.data(withJSONObject: obj) else { return false }
            data = encoded
        }
        var line = data
        line.append("\n".data(using: .utf8)!)
        do { try h.write(contentsOf: line); return true } catch { return false }
    }

    private func sendRequest(method: String, params: [String: Any]) async throws -> Any? {
        let id: Int = {
            ioLock.lock()
            defer { ioLock.unlock() }
            let current = nextRequestId
            nextRequestId += 1
            return current
        }()
        let req: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]

        return try await withCheckedThrowingContinuation { c in
            ioLock.lock()
            pendingRequests[id] = PendingRequest(continuation: c, timeoutTask: nil)
            ioLock.unlock()
            if !writeJson(req) {
                ioLock.lock()
                pendingRequests.removeValue(forKey: id)
                ioLock.unlock()
                c.resume(throwing: NSError(domain: "ACP", code: -1))
            }
        }
    }

    private func sendRequestWithTimeout(method: String, params: [String: Any], seconds: Double = 15) async throws -> Any? {
        let id: Int = {
            ioLock.lock()
            defer { ioLock.unlock() }
            let current = nextRequestId
            nextRequestId += 1
            return current
        }()
        let req: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]

        return try await withCheckedThrowingContinuation { c in
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.timeoutPendingRequest(id: id)
            }
            ioLock.lock()
            pendingRequests[id] = PendingRequest(continuation: c, timeoutTask: timeoutTask)
            ioLock.unlock()
            if !writeJson(req) {
                timeoutTask.cancel()
                ioLock.lock()
                pendingRequests.removeValue(forKey: id)
                ioLock.unlock()
                c.resume(throwing: NSError(domain: "ACP", code: -1))
            }
        }
    }

    private func timeoutPendingRequest(id: Int) {
        ioLock.lock()
        guard let pending = pendingRequests.removeValue(forKey: id) else {
            ioLock.unlock()
            return
        }
        ioLock.unlock()
        pending.continuation.resume(throwing: NSError(
            domain: "ACP",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for grok."]
        ))
    }

    private func drainPendingRequests(with error: Error) {
        ioLock.lock()
        let pending = Array(pendingRequests.values)
        pendingRequests.removeAll()
        ioLock.unlock()
        for item in pending {
            item.timeoutTask?.cancel()
            item.continuation.resume(throwing: error)
        }
    }

    private func startupStderrSnapshot() -> String {
        ioLock.lock()
        defer { ioLock.unlock() }
        return startupStderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func initializeACP() async throws {
        let res = try await sendRequestWithTimeout(method: "initialize", params: [
            "protocolVersion": 1,
            "clientCapabilities": [
                "fs": ["readTextFile": true, "writeTextFile": true],
                "terminal": true
            ]
        ]) as? [String: Any]

        // Parse real models from modelState (do not make up)
        let meta = res?["_meta"] as? [String: Any]
        if let ms = (res?["modelState"] as? [String: Any]) ?? (meta?["modelState"] as? [String: Any]),
           let models = ms["availableModels"] as? [[String: Any]] {
            availableModelsInfo = models.compactMap { m in
                guard let id = m["modelId"] as? String else { return nil }
                let name = m["name"] as? String ?? id
                let meta = m["_meta"] as? [String: Any]
                return (id: id, name: name, contextTokens: meta?["totalContextTokens"] as? Int)
            }
            currentModelId = ms["currentModelId"] as? String
        }
    }

    private func createSession(workspace: Workspace, mcpServers: [MCPServerConfig]) async throws {
        let res = try await sendRequestWithTimeout(method: "session/new", params: [
            "cwd": workspace.path.path,
            "mcpServers": mcpServers.map(\.jsonObject)
        ]) as? [String: Any]
        sessionId = res?["sessionId"] as? String
        updateModels(from: res?["models"] as? [String: Any])

        if let mode = res?["currentModeId"] as? String ?? res?["mode"] as? String {
            currentMode = AgentMode(rawValue: mode)
        }

        // Expose available modes if provided by the CLI
        if let modes = res?["modes"] as? [String] {
            availableModes = modes.map { AgentMode(rawValue: $0) }
        } else if let modeInfos = res?["availableModes"] as? [[String: Any]] {
            availableModes = modeInfos.compactMap { $0["id"] as? String }.map { AgentMode(rawValue: $0) }
        }
    }

    private func loadSession(id: String, workspace: Workspace, mcpServers: [MCPServerConfig]) async throws {
        let res = try await sendRequestWithTimeout(method: "session/load", params: [
            "sessionId": id,
            "cwd": workspace.path.path,
            "mcpServers": mcpServers.map(\.jsonObject)
        ]) as? [String: Any]
        sessionId = id
        updateModels(from: res?["models"] as? [String: Any])
        if let mode = res?["currentModeId"] as? String ?? res?["mode"] as? String {
            currentMode = AgentMode(rawValue: mode)
        }
    }

    private func updateModels(from modelState: [String: Any]?) {
        guard let modelState else { return }
        currentModelId = modelState["currentModelId"] as? String ?? currentModelId
        if let models = modelState["availableModels"] as? [[String: Any]] {
            availableModelsInfo = models.compactMap { m in
                guard let id = m["modelId"] as? String else { return nil }
                let name = m["name"] as? String ?? id
                let meta = m["_meta"] as? [String: Any]
                return (id: id, name: name, contextTokens: meta?["totalContextTokens"] as? Int)
            }
        }
    }

    private func setupReaders(stdout: Pipe, stderr: Pipe) {
        // Process pipe I/O synchronously on the reader thread. Dispatching to
        // MainActor here deadlocks because start() awaits ACP responses on MainActor.
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.handleStdoutData(data)
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.handleStderrData(data)
        }
    }

    private func handleStdoutData(_ data: Data) {
        var lines: [String] = []
        ioLock.lock()
        if let chunk = String(data: data, encoding: .utf8) {
            stdoutBuffer += chunk
            while let newline = stdoutBuffer.firstIndex(of: "\n") {
                lines.append(String(stdoutBuffer[..<newline]))
                stdoutBuffer.removeSubrange(...newline)
            }
        }
        ioLock.unlock()

        for rawLine in lines {
            handleAcpRawLine(rawLine)
        }
    }

    private func handleStderrData(_ data: Data) {
        ioLock.lock()
        let chunk = String(data: data, encoding: .utf8)
        if let chunk {
            startupStderr += chunk
        }
        ioLock.unlock()

        if let chunk {
            outputContinuation?.yield("[stderr] \(chunk)")
        }
    }

    private func handleAcpRawLine(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        outputLines.append(line)
        outputContinuation?.yield(line + "\n")
        handleJsonLine(line)
    }

    private func handleJsonLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            acpEventContinuation?.yield(.rawLine(line))
            return
        }

        if let method = j["method"] as? String {
            let params = j["params"] as? [String: Any] ?? [:]
            let rid = j["id"]

            if method == "session/update" {
                if let total = totalTokens(from: params) {
                    acpEventContinuation?.yield(.contextUsage(totalTokens: total))
                }
                if let u = params["update"] as? [String: Any] { routeUpdate(u) }
                return
            }

            if method == "session/request_permission" {
                if let req = parsePermissionRequest(id: rid, params: params) {
                    acpEventContinuation?.yield(.permissionRequest(req))
                }
                // UI will respond via respondToPermission
                return
            }

            if method == "x.ai/exit_plan_mode" || method == "session/exit_plan_mode"
                || method == "_x.ai/exit_plan_mode" {
                let planText = exitPlanText(from: params)
                let req = ExitPlanRequest(
                    id: requestIdHash(rid),
                    sessionId: params["sessionId"] as? String ?? sessionId ?? "",
                    planText: planText.isEmpty ? latestPlanFileContent : planText,
                    isResolved: false,
                    verdict: nil
                )
                acpEventContinuation?.yield(.exitPlanRequest(req))
                return
            }

            if method == "x.ai/ask_user_question" || method == "_x.ai/ask_user_question" {
                let questions = (params["questions"] as? [[String: Any]] ?? [])
                    .compactMap { QuestionItem.parse(from: $0) }
                let req = QuestionRequest(
                    id: requestIdHash(rid),
                    sessionId: params["sessionId"] as? String ?? sessionId ?? "",
                    questions: questions,
                    isResolved: false,
                    answerSummary: nil
                )
                acpEventContinuation?.yield(.questionRequest(req))
                return
            }

            switch method {
            case "fs/read_text_file":
                if let p = params["path"] as? String { handleFsRead(rid: rid, path: p) }
            case "fs/write_text_file":
                if let p = params["path"] as? String, let c = params["content"] as? String {
                    handleFsWrite(rid: rid, path: p, content: c)
                }
            default:
                if let r = rid { _ = writeJson(["jsonrpc": "2.0", "id": r, "result": [:]]) }
            }
            return
        }

        if let id = jsonRequestId(from: j) {
            ioLock.lock()
            let pending = pendingRequests.removeValue(forKey: id)
            ioLock.unlock()
            if let pending {
                pending.timeoutTask?.cancel()
                if let err = j["error"] {
                    var info: [String: Any] = [:]
                    if let dict = err as? [String: Any] {
                        // Prefer the agent's human-readable message over dumping the raw error object.
                        info[NSLocalizedDescriptionKey] = (dict["message"] as? String) ?? "\(err)"
                        if let data = dict["data"] as? [String: Any] {
                            if let code = data["code"] as? String { info["acpErrorCode"] = code }
                            if let suggestion = data["suggestion"] as? String { info["acpSuggestion"] = suggestion }
                        }
                    } else {
                        info[NSLocalizedDescriptionKey] = "\(err)"
                    }
                    pending.continuation.resume(throwing: NSError(domain: "ACP", code: -1, userInfo: info))
                } else {
                    pending.continuation.resume(returning: j["result"])
                }
            }
            return
        }
    }

    private func jsonRequestId(from json: [String: Any]) -> Int? {
        if let id = json["id"] as? Int { return id }
        if let id = json["id"] as? NSNumber { return id.intValue }
        if let id = json["id"] as? String, let parsed = Int(id) { return parsed }
        return nil
    }

    private func totalTokens(from params: [String: Any]) -> Int? {
        if let meta = params["_meta"] as? [String: Any],
           let total = meta["totalTokens"] as? Int {
            return total
        }
        if let update = params["update"] as? [String: Any],
           let meta = update["_meta"] as? [String: Any],
           let total = meta["totalTokens"] as? Int {
            return total
        }
        return nil
    }

    private func routeUpdate(_ u: [String: Any]) {
        guard let k = u["sessionUpdate"] as? String else { return }
        switch k {
        case "agent_message_chunk":
            let t = (u["content"] as? [String: Any])?["text"] as? String ?? ""
            acpEventContinuation?.yield(.messageChunk(text: t))
        case "agent_thought_chunk":
            let t = (u["content"] as? [String: Any])?["text"] as? String ?? ""
            acpEventContinuation?.yield(.thoughtChunk(text: t))
        case "tool_call":
            if let tc = parseToolCall(from: u) {
                acpEventContinuation?.yield(.toolCall(tc))
            } else {
                acpEventContinuation?.yield(.toolCall(ToolCall(id: UUID().uuidString, kind: "unknown", title: "Tool call", rawInput: nil)))
            }
        case "tool_call_update":
            if let tc = parseToolCall(from: u) {
                acpEventContinuation?.yield(.toolCallUpdate(tc))
            }
        case "plan":
            acpEventContinuation?.yield(.plan(payload: u))
        case "available_commands_update":
            let commands = (u["availableCommands"] as? [[String: Any]] ?? [])
                .compactMap { SlashCommand.parse(from: $0) }
            availableSlashCommands = commands
            acpEventContinuation?.yield(.availableCommands(commands))
        case "current_mode_update":
            if let m = u["currentModeId"] as? String {
                currentMode = AgentMode(rawValue: m)
                acpEventContinuation?.yield(.modeChanged(mode: currentMode))
            }
        default: break
        }
    }

    private func requestIdHash(_ id: Any?) -> AnyHashable {
        if let intId = id as? Int { return AnyHashable(intId) }
        if let strId = id as? String { return AnyHashable(strId) }
        return AnyHashable(UUID().uuidString)
    }

    private func respond(rid: Any?, result: Any = [:]) {
        guard let id = rid else { return }
        _ = writeJson(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func handleFsRead(rid: Any?, path: String) {
        do {
            let c = try String(contentsOf: resolvedProjectURL(path), encoding: .utf8)
            respond(rid: rid, result: ["content": c])
        } catch {
            _ = writeJson(["jsonrpc": "2.0", "id": rid as Any, "error": ["code": -32001, "message": error.localizedDescription]])
        }
    }

    private func handleFsWrite(rid: Any?, path: String, content: String) {
        if isPlanFileWrite(path) {
            latestPlanFileContent = content
            acpEventContinuation?.yield(.planFileContent(content))
        }
        do {
            let url = resolvedProjectURL(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            respond(rid: rid)
        } catch {
            _ = writeJson(["jsonrpc": "2.0", "id": rid as Any, "error": ["code": -32001, "message": error.localizedDescription]])
        }
    }

    private func isPlanFileWrite(_ path: String) -> Bool {
        let normalized = path.replacingOccurrences(of: "\\", with: "/").lowercased()
        return normalized.hasSuffix("/plan.md") || normalized.contains("/sessions/") && normalized.hasSuffix("plan.md")
    }

    private func exitPlanText(from params: [String: Any]) -> String {
        if let plan = params["planContent"] as? String, !plan.isEmpty { return plan }
        if let plan = params["plan"] as? String, !plan.isEmpty { return plan }
        if let input = params["input"] as? [String: Any], let plan = input["plan"] as? String { return plan }
        return ""
    }

    private func resolvedProjectURL(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return (currentWorkspace?.path ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .appendingPathComponent(path)
            .standardizedFileURL
    }

    // MARK: - Utils

    private static func locateGrokCLI() -> URL? {
        if let p = ProcessInfo.processInfo.environment["GROK_CLI_PATH"], !p.isEmpty {
            let u = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
            if FileManager.default.isExecutableFile(atPath: u.path) { return u }
        }
        for c in ["\(NSHomeDirectory())/.grok/bin/grok",
                  "\(NSHomeDirectory())/bin/grok",
                  "/opt/homebrew/bin/grok",
                  "/usr/local/bin/grok"] {
            if FileManager.default.isExecutableFile(atPath: c) { return URL(fileURLWithPath: c) }
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for d in path.split(separator: ":") {
                let f = URL(fileURLWithPath: String(d)).appendingPathComponent("grok").path
                if FileManager.default.isExecutableFile(atPath: f) { return URL(fileURLWithPath: f) }
            }
        }
        return nil
    }

    private func notifyStatus() {
        let s: String
        if case .failed = state {
            s = "error"
        } else if state == .busy {
            s = "busy"
        } else if state == .ready {
            s = "ready"
        } else {
            s = "idle"
        }
        let authenticated = !needsAuthentication
        NotificationCenter.default.post(name: .grokStatusChanged, object: nil, userInfo: ["status": s, "authenticated": authenticated])
    }
}

extension FileHandle {
    func bytesStream() -> AsyncStream<Data> {
        AsyncStream { c in
            self.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty {
                    c.finish()
                    h.readabilityHandler = nil
                } else {
                    c.yield(d)
                }
            }
            c.onTermination = { _ in self.readabilityHandler = nil }
        }
    }
}