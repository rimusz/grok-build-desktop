import Foundation
import Observation
import SwiftUI

@Observable
final class ChatStore {
    private struct SessionSelection: Codable {
        var mode: String?
        var model: String?
    }

    private(set) var messages: [Message] = []

    func clearMessages() {
        messages.removeAll()
    }
    private(set) var isStreaming = false
    private(set) var lastError: String?

    /// Set when the underlying grok CLI indicates the user is not authenticated.
    var authRequiredMessage: String?

    // MARK: - ACP Rich State
    private(set) var connectionState: GrokProcessState = .idle
    private(set) var currentMode: AgentMode = .agent
    private(set) var availableModes: [AgentMode] = [.agent, .plan, .yolo]
    private(set) var pendingPermissions: [PermissionRequest] = []
    private(set) var isYolo: Bool = false

    // MARK: - Model selection (real models from `grok models` + initialize modelState)
    private(set) var currentModel: String = "grok-composer-2.5-fast"
    private(set) var availableModels: [String] = [
        "grok-composer-2.5-fast",
        "grok-build"
    ]
    private var modelDisplayNames: [String: String] = [
        "grok-composer-2.5-fast": "Composer 2.5 Fast",
        "grok-build": "Grok Build"
    ]
    private var modelContextTokens: [String: Int] = [
        "grok-composer-2.5-fast": 200_000,
        "grok-build": 512_000
    ]

    // Persist mode/model choices per Grok session id.
    private let sessionSelectionsKey = "grokbuild.sessionSelections.v1"
    private let defaults = UserDefaults.standard
    private var sessionSelections: [String: SessionSelection] = [:]

    private(set) var commandHistory: [String] = []
    private var historyIndex: Int?

    let process: GrokProcess
    private(set) var currentWorkspace: Workspace?
    // (removed Agent personas - see AGENTS.md + sub-agents in Grok Build CLI)

    private var streamingMessageID: UUID?

    init(process: GrokProcess = GrokProcess()) {
        self.process = process
        loadSessionSelections()
        Task { [weak self] in await self?.consumeOutput() }
    }

    private func loadSessionSelections() {
        guard let data = defaults.data(forKey: sessionSelectionsKey),
              let decoded = try? JSONDecoder().decode([String: SessionSelection].self, from: data) else {
            return
        }
        sessionSelections = decoded
    }

    private func postStatusUpdate(_ status: String) {
        let authenticated = !process.needsAuthentication
        NotificationCenter.default.post(
            name: .grokStatusChanged,
            object: nil,
            userInfo: ["status": status, "authenticated": authenticated]
        )
    }

    // MARK: Context

    func setWorkspace(_ workspace: Workspace) async {
        await start(workspace: workspace)
    }

    func start(workspace: Workspace, resumeSession: GrokSessionInfo? = nil) async {
        currentWorkspace = workspace
        messages.removeAll()
        streamingMessageID = nil
        authRequiredMessage = nil
        pendingPermissions.removeAll()
        await restartProcess(resumeSessionID: resumeSession?.id)
        if let resumeSession {
            appendSystemNote("Resumed session \(resumeSession.id).")
        }
    }

    // setAgent for personas removed - use CLI's AGENTS.md, skills, or --agent for custom profiles.

    func reloadConfiguration() async {
        if currentWorkspace != nil {
            await restartProcess()
            appendSystemNote("Reloaded Grok configuration.")
        }
    }

    func startNewSession() async {
        messages.removeAll()
        streamingMessageID = nil
        pendingPermissions.removeAll()
        if currentWorkspace != nil {
            await restartProcess()
        }
    }

    func resumeSession(_ session: GrokSessionInfo) async {
        guard currentWorkspace != nil else {
            lastError = "Select a project first."
            return
        }
        messages.removeAll()
        streamingMessageID = nil
        pendingPermissions.removeAll()
        await restartProcess(resumeSessionID: session.id)
        appendSystemNote("Resumed session \(session.id).")
    }

    private func restartProcess(resumeSessionID: String? = nil) async {
        guard let ws = currentWorkspace else { return }
        isStreaming = false
        streamingMessageID = nil
        connectionState = .starting
        postStatusUpdate("starting")
        let settings = loadPermissionSettings()
        let savedSelection = resumeSessionID.flatMap { sessionSelections[$0] }
        let opts = GrokLaunchOptions(
            agent: nil,  // Agent Team / personas removed. Use --agent only for custom profiles if needed.
            noMemory: settings.noMemory,
            permissionMode: settings.permissionMode,
            reasoningEffort: settings.reasoningEffort,
            model: savedSelection?.model,
            sandboxProfile: settings.sandboxProfile,
            disableWebSearch: settings.disableWebSearch,
            noSubagents: settings.noSubagents,
            allowRules: lineList(settings.allowRules),
            denyRules: lineList(settings.denyRules),
            resumeSessionID: resumeSessionID
        )
        await process.start(workspace: ws, options: opts)
        connectionState = process.state
        postStatusUpdate(statusName(for: connectionState))
        availableModes = process.availableModes
        syncModelsFromProcess()
        restoreSessionSelection(savedSelection)
        saveCurrentSessionSelection()
    }

    // MARK: Messaging

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard currentWorkspace != nil else {
            lastError = "Select a project first."
            return
        }

        if commandHistory.last != trimmed {
            commandHistory.append(trimmed)
        }
        historyIndex = nil

        let userMsg = Message(role: .user, content: trimmed)
        messages.append(userMsg)

        let assistant = Message(role: .assistant, content: "")
        messages.append(assistant)
        streamingMessageID = assistant.id
        isStreaming = true
        lastError = nil
        authRequiredMessage = nil
        pendingPermissions.removeAll()
        connectionState = .busy
        postStatusUpdate("busy")

        let payload = trimmed

        let ok = await process.send(payload)
        if !ok {
            isStreaming = false
            streamingMessageID = nil
            lastError = "Failed to send to grok."
            connectionState = process.state == .ready ? .ready : process.state
            postStatusUpdate(statusName(for: connectionState))
            if let id = streamingMessageID, let idx = messages.firstIndex(where: { $0.id == id }) {
                messages.remove(at: idx)
            }
        } else {
            isStreaming = false
            streamingMessageID = nil
            connectionState = .ready
            postStatusUpdate("ready")
        }
    }

    func stop() {
        isStreaming = false
        streamingMessageID = nil
        pendingPermissions.removeAll()
        process.interrupt()
        connectionState = .ready
        postStatusUpdate("ready")
    }

    // MARK: - ACP Responses & Modes

    func respondToPermission(_ request: PermissionRequest, with optionId: String) {
        let isAllow = optionId.lowercased().contains("allow")

        if isAllow && request.toolCall.isEdit,
           let path = request.toolCall.editFilePath,
           let newContent = request.toolCall.proposedContent {

            // Trigger actual patch/application from the permission response
            do {
                let base = currentWorkspace?.path ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                let url = URL(fileURLWithPath: path, relativeTo: base)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try newContent.write(to: url, atomically: true, encoding: .utf8)

                // Also use existing diff apply logic if we can construct a simple diff
                if request.toolCall.oldContent != nil {
                    // For richer, we could build unified diff here, but direct write is reliable
                    appendSystemNote("Applied edit to \(path) from permission approval.")
                }
            } catch {
                lastError = "Failed to apply edit from permission: \(error.localizedDescription)"
            }
        }

        process.respondToPermission(request, with: optionId)
        // Remove from pending
        pendingPermissions.removeAll { $0.id == request.id }
    }

    func setMode(_ mode: AgentMode) {
        process.setMode(mode)
        // Optimistically update; will be confirmed by modeChanged event
        currentMode = mode
        isYolo = (mode == .yolo)
        saveCurrentSessionSelection()
    }

    /// Convenience for the three common modes
    func setAgentMode() { setMode(.agent) }
    func setPlanMode()  { setMode(.plan) }
    func setYoloMode()  { setMode(.yolo) }

    func setModel(_ model: String) {
        guard availableModels.contains(model) else { return }
        currentModel = model
        process.setModel(model)
        saveCurrentSessionSelection()
    }

    func modelDisplayName(_ id: String) -> String {
        modelDisplayNames[id] ?? id
    }

    var currentModelContextLabel: String {
        guard let tokens = modelContextTokens[currentModel] else { return "Context: unknown" }
        return "Context: \(Self.compactTokenCount(tokens))"
    }

    private static func compactTokenCount(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return "\(tokens / 1_000_000)M"
        }
        if tokens >= 1_000 {
            return "\(tokens / 1_000)K"
        }
        return "\(tokens)"
    }

    func setYolo(_ enabled: Bool) {
        isYolo = enabled
        if enabled {
            // Auto-approve any current pending
            for perm in pendingPermissions {
                if let allow = perm.options.first(where: { $0.kind.contains("allow") }) ?? perm.options.first {
                    respondToPermission(perm, with: allow.id)
                }
            }
            pendingPermissions.removeAll()
        }
    }

    /// Attempts to restart the grok process (useful after running `grok login`).
    func retryConnection() async {
        authRequiredMessage = nil
        lastError = nil
        if currentWorkspace != nil {
            await restartProcess()
        }
    }

    // MARK: History

    func previousHistory(from current: String) -> String? {
        guard !commandHistory.isEmpty else { return nil }
        if let idx = historyIndex {
            let ni = max(0, idx - 1)
            historyIndex = ni
            return commandHistory[ni]
        } else {
            historyIndex = commandHistory.count - 1
            return commandHistory.last
        }
    }

    func nextHistory(from current: String) -> String? {
        guard let idx = historyIndex else { return nil }
        let ni = idx + 1
        if ni < commandHistory.count {
            historyIndex = ni
            return commandHistory[ni]
        }
        historyIndex = nil
        return ""
    }

    // MARK: Diffs + Apply (public API used by preview)

    struct DetectedDiff: Identifiable, Hashable {
        let id = UUID()
        let raw: String
        let filePath: String?
    }

    func detectedDiffs(in message: Message) -> [DetectedDiff] {
        guard message.role == .assistant else { return [] }
        var out: [DetectedDiff] = []
        let content = message.content

        // ```diff / ```patch blocks
        if let re = try? NSRegularExpression(pattern: "```(?:diff|patch)\\s*([\\s\\S]*?)```", options: .caseInsensitive) {
            let ns = content as NSString
            for m in re.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
                if m.numberOfRanges > 1 {
                    let d = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    out.append(.init(raw: d, filePath: DiffUtils.firstFilePath(in: d)))
                }
            }
        }

        if out.isEmpty && content.contains("diff --git") {
            let parts = content.components(separatedBy: "\ndiff --git")
            for (i, p) in parts.enumerated() {
                var block = p
                if i > 0 { block = "diff --git" + block }
                if block.contains("diff --git") {
                    let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
                    out.append(.init(raw: trimmed, filePath: DiffUtils.firstFilePath(in: trimmed)))
                }
            }
        }
        return out
    }

    @discardableResult
    func applyDiffs(from message: Message, workspace: Workspace) -> (applied: Int, errors: [String]) {
        let diffs = detectedDiffs(in: message)
        guard !diffs.isEmpty else { return (0, []) }

        var applied = 0
        var errs: [String] = []
        for d in diffs {
            do {
                try DiffUtils.applyUnifiedDiff(d.raw, root: workspace.path)
                applied += 1
            } catch {
                errs.append("\(d.filePath ?? "file"): \(error.localizedDescription)")
            }
        }
        if applied > 0 {
            appendSystem("Applied \(applied) patch(es).")
        }
        return (applied, errs)
    }

    // MARK: Internal

    private func consumeOutput() async {
        // Primary: structured ACP events from `grok agent stdio`
        for await event in process.acpEventStream {
            await MainActor.run { self.handleAcpEvent(event) }
        }
    }

    private func handleAcpEvent(_ event: AcpEvent) {
        switch event {
        case .messageChunk(let text):
            appendAssistantText(text)
        case .thoughtChunk(let text):
            appendAssistantText(text)
        case .toolCall:
            // TODO: create rich tool call UI entry if desired
            break
        case .toolCallUpdate:
            break
        case .plan:
            break
        case .permissionRequest(let req):
            if isYolo {
                // Auto-approve in YOLO mode (prefer allow_always or first allow)
                if let allow = req.options.first(where: { $0.kind.contains("always") || $0.kind.contains("allow") }) ?? req.options.first {
                    respondToPermission(req, with: allow.id)
                }
                return
            }
            // Avoid duplicates
            if !pendingPermissions.contains(where: { $0.id == req.id }) {
                pendingPermissions.append(req)
            }
        case .modeChanged(let mode):
            currentMode = mode
            availableModes = process.availableModes // keep in sync
            saveCurrentSessionSelection()
            // availableModes stay as reported from CLI, but we can filter if needed

        case .rawLine(let line):
            appendAssistantText(line)
        case .error(let msg):
            lastError = msg
        }
    }

    private func appendAssistantText(_ text: String) {
        guard let id = streamingMessageID,
              let idx = messages.firstIndex(where: { $0.id == id }) else { return }

        let clean = text.replacingOccurrences(of: "<<USER>> ", with: "")
        if clean.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(">") &&
           !clean.contains("diff") { return }

        if !clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !messages[idx].content.isEmpty {
            messages[idx].content += clean
        }
    }

    // Legacy fallback (still works with old string stream if needed)
    private func handleChunk(_ raw: String) {
        appendAssistantText(raw)
    }

    private func appendSystem(_ text: String) {
        messages.append(Message(role: .system, content: text))
    }

    private func appendSystemNote(_ text: String) {
        appendSystem(text)
    }

    private func loadPermissionSettings() -> GrokPermissionSettings {
        GrokPermissionSettings(
            permissionMode: defaults.string(forKey: GrokSettingsKeys.permissionMode) ?? GrokPermissionSettings.defaults.permissionMode,
            sandboxProfile: defaults.string(forKey: GrokSettingsKeys.sandboxProfile) ?? "",
            reasoningEffort: defaults.string(forKey: GrokSettingsKeys.reasoningEffort) ?? "",
            noMemory: defaults.bool(forKey: GrokSettingsKeys.noMemory),
            disableWebSearch: defaults.bool(forKey: GrokSettingsKeys.disableWebSearch),
            noSubagents: defaults.bool(forKey: GrokSettingsKeys.noSubagents),
            allowRules: defaults.string(forKey: GrokSettingsKeys.allowRules) ?? "",
            denyRules: defaults.string(forKey: GrokSettingsKeys.denyRules) ?? ""
        )
    }

    private func lineList(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func syncModelsFromProcess() {
        guard !process.availableModelsInfo.isEmpty else { return }
        availableModels = process.availableModelsInfo.map { $0.id }
        modelDisplayNames = Dictionary(uniqueKeysWithValues: process.availableModelsInfo.map { ($0.id, $0.name) })
        modelContextTokens = Dictionary(uniqueKeysWithValues: process.availableModelsInfo.compactMap { model in
            guard let tokens = model.contextTokens else { return nil }
            return (model.id, tokens)
        })
    }

    private func restoreSessionSelection(_ fallbackSelection: SessionSelection?) {
        let selection = process.sessionId.flatMap { sessionSelections[$0] } ?? fallbackSelection

        if let model = selection?.model, availableModels.contains(model) {
            currentModel = model
            if process.currentModelId != model {
                process.setModel(model)
            }
        } else if let processModel = process.currentModelId, availableModels.contains(processModel) {
            currentModel = processModel
        } else if !availableModels.contains(currentModel) {
            currentModel = availableModels.first ?? currentModel
        }

        let selectedMode = selection?.mode.map(AgentMode.init(rawValue:)) ?? process.currentMode
        if availableModes.contains(selectedMode) {
            currentMode = selectedMode
        } else {
            currentMode = availableModes.first ?? .agent
        }
        isYolo = (currentMode == .yolo)
        if currentMode != process.currentMode {
            process.setMode(currentMode)
        }
    }

    private func saveCurrentSessionSelection() {
        guard let sessionId = process.sessionId else { return }
        sessionSelections[sessionId] = SessionSelection(
            mode: currentMode.rawValue,
            model: currentModel
        )
        if let data = try? JSONEncoder().encode(sessionSelections) {
            defaults.set(data, forKey: sessionSelectionsKey)
        }
    }

    private func statusName(for state: GrokProcessState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .starting:
            return "starting"
        case .ready:
            return "ready"
        case .busy:
            return "busy"
        case .failed:
            return "error"
        }
    }
}

// MARK: - Diff utilities (extracted)

enum DiffUtils {
    static func firstFilePath(in diff: String) -> String? {
        for line in diff.components(separatedBy: .newlines) {
            if line.hasPrefix("diff --git ") {
                let comps = line.split(separator: " ")
                if comps.count >= 4 {
                    let b = String(comps[3])
                    return b.hasPrefix("b/") ? String(b.dropFirst(2)) : b
                }
            }
            if line.hasPrefix("+++ b/") { return String(line.dropFirst(6)) }
            if line.hasPrefix("--- a/") { return String(line.dropFirst(6)) }
            if line.hasPrefix("--- ") && !line.contains("--- /dev/null") {
                let p = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
                return p.hasPrefix("a/") ? String(p.dropFirst(2)) : p
            }
        }
        return nil
    }

    static func applyUnifiedDiff(_ diffText: String, root: URL) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-\(UUID().uuidString).patch")
        try diffText.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/patch")
        p.arguments = ["-p1", "-d", root.path, "-i", tmp.path]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()

        if p.terminationStatus != 0 {
            try naiveApply(diffText, root: root)
        }
    }

    private static func naiveApply(_ diff: String, root: URL) throws {
        let lines = diff.components(separatedBy: .newlines)
        var target: String?
        var content: [String] = []
        var inHunk = false

        for line in lines {
            if line.hasPrefix("+++ b/") { target = String(line.dropFirst(6)) }
            else if line.hasPrefix("@@") { inHunk = true }
            else if inHunk {
                if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    content.append(String(line.dropFirst()))
                } else if !line.hasPrefix("-") && !line.hasPrefix("\\") {
                    content.append(line)
                }
            }
        }
        guard let t = target else {
            throw NSError(domain: "GrokBuild", code: -1, userInfo: [NSLocalizedDescriptionKey: "No target path in diff"])
        }
        let dest = root.appendingPathComponent(t)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.joined(separator: "\n").write(to: dest, atomically: true, encoding: .utf8)
    }
}
