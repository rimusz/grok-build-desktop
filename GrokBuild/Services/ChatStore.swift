import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
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

    // VS Code extension-style turn state
    private(set) var isGrokking = false
    private(set) var thinkingText = ""
    private(set) var thinkingDuration: TimeInterval?
    private(set) var isThinkingExpanded = false
    private(set) var liveToolCalls: [LiveToolCall] = []
    private var thinkingStartedAt: Date?

    struct LiveToolCall: Identifiable, Hashable {
        let id: String
        let title: String
        let kind: String
    }

    /// Set when the underlying grok CLI indicates the user is not authenticated.
    var authRequiredMessage: String?

    // MARK: - ACP Rich State
    private(set) var connectionState: GrokProcessState = .idle
    private(set) var currentMode: AgentMode = .agent
    private(set) var availableModes: [AgentMode] = [.agent, .plan, .yolo]
    private(set) var pendingPermissions: [PermissionRequest] = []
    private(set) var pendingExitPlan: ExitPlanRequest?
    private(set) var pendingQuestions: [QuestionRequest] = []
    private(set) var availableSlashCommands: [SlashCommand] = []
    private(set) var fileAttachments: [FileAttachment] = []
    private(set) var isYolo: Bool = false

    var grokSessionId: String? { process.sessionId }

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
    private(set) var usedContextTokens: Int?

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
    private var connectionWatchdogTask: Task<Void, Never>?

    init(process: GrokProcess? = nil) {
        self.process = process ?? GrokProcess()
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

    func prepare(workspace: Workspace) {
        currentWorkspace = workspace
        messages.removeAll()
        streamingMessageID = nil
        authRequiredMessage = nil
        pendingPermissions.removeAll()
        pendingExitPlan = nil
        pendingQuestions.removeAll()
        fileAttachments.removeAll()
        clearTurnState()
        connectionState = .idle
        lastError = nil
    }

    var hasUserMessages: Bool {
        messages.contains { $0.role == .user }
    }

    func start(workspace: Workspace, resumeSession: GrokSessionInfo? = nil) async {
        currentWorkspace = workspace
        messages.removeAll()
        streamingMessageID = nil
        authRequiredMessage = nil
        pendingPermissions.removeAll()
        pendingExitPlan = nil
        pendingQuestions.removeAll()
        fileAttachments.removeAll()
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
        pendingExitPlan = nil
        pendingQuestions.removeAll()
        fileAttachments.removeAll()
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
        pendingExitPlan = nil
        pendingQuestions.removeAll()
        fileAttachments.removeAll()
        await restartProcess(resumeSessionID: session.id)
        appendSystemNote("Resumed session \(session.id).")
    }

    private func restartProcess(resumeSessionID: String? = nil) async {
        guard let ws = currentWorkspace else { return }
        isStreaming = false
        streamingMessageID = nil
        connectionWatchdogTask?.cancel()
        usedContextTokens = nil
        connectionState = .starting
        lastError = nil
        postStatusUpdate("starting")
        startConnectionWatchdog()
        let settings = loadPermissionSettings()
        let savedSelection = resumeSessionID.flatMap { sessionSelections[$0] }
        let browserSettings = BrowserSettingsStore.load()
        if browserSettings.enabled {
            do {
                try BrowserSkillInstaller.installIfNeeded(settings: browserSettings)
            } catch {
                lastError = "Browser skill install failed: \(error.localizedDescription)"
            }
            do {
                _ = try await AgentBrowserService.ensureExternalBrowserStarted(settings: browserSettings)
            } catch {
                lastError = "External browser auto-start failed: \(error.localizedDescription)"
            }
        }
        let browserMCPServers = AgentBrowserService.browserMCPConfig(settings: browserSettings)
            .map { [$0] } ?? []
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
            resumeSessionID: resumeSessionID,
            mcpServers: browserMCPServers
        )
        await process.start(workspace: ws, options: opts)
        connectionWatchdogTask?.cancel()
        connectionState = process.state
        if case .failed(let message) = process.state {
            lastError = message
            postStatusUpdate(statusName(for: connectionState))
            return
        }
        postStatusUpdate(statusName(for: connectionState))
        availableModes = process.availableModes
        syncModelsFromProcess()
        restoreSessionSelection(savedSelection)
        saveCurrentSessionSelection()
        availableSlashCommands = process.availableSlashCommands
    }

    private func startConnectionWatchdog() {
        connectionWatchdogTask?.cancel()
        connectionWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            await self?.markConnectionTimedOutIfNeeded()
        }
    }

    private func markConnectionTimedOutIfNeeded() async {
        guard connectionState == .starting else { return }
        lastError = process.state.errorMessage ?? "Timed out while connecting to grok."
        connectionState = .failed(lastError ?? "Timed out while connecting to grok.")
        postStatusUpdate("error")
        await process.stop()
    }

    // MARK: Messaging

    @discardableResult
    func send(_ text: String) async -> Bool {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !fileAttachments.isEmpty else { return false }
        guard currentWorkspace != nil else {
            lastError = "Select a project first."
            return false
        }
        if connectionState != .ready {
            if process.sessionId == nil && connectionState != .starting {
                await restartProcess()
            }
            guard connectionState == .ready else {
                if lastError == nil {
                    lastError = connectionState == .starting
                        ? "Grok is still starting…"
                        : connectionState.errorMessage ?? "Grok is not ready yet."
                }
                return false
            }
        }

        if commandHistory.last != trimmed {
            commandHistory.append(trimmed)
        }
        historyIndex = nil

        clearTurnState()
        isGrokking = true

        let attachmentRefs = fileAttachments.map(\.reference).joined(separator: "\n")
        if !attachmentRefs.isEmpty {
            trimmed = trimmed.isEmpty ? attachmentRefs : "\(attachmentRefs)\n\(trimmed)"
        }
        fileAttachments.removeAll()

        let userMsg = Message(role: .user, content: trimmed)
        messages.append(userMsg)
        NotificationCenter.default.post(name: .liveSessionMessagesChanged, object: self)

        let assistant = Message(role: .assistant, content: "")
        messages.append(assistant)
        streamingMessageID = assistant.id
        isStreaming = true
        lastError = nil
        authRequiredMessage = nil
        pendingPermissions.removeAll()
        pendingExitPlan = nil
        pendingQuestions.removeAll()
        connectionState = .busy
        postStatusUpdate("busy")

        let payload = trimmed
        let assistantID = assistant.id

        Task { [weak self] in
            guard let self else { return }
            let ok = await self.process.send(payload)
            self.finishPrompt(assistantID: assistantID, ok: ok)
        }

        return true
    }

    private func finishPrompt(assistantID: UUID, ok: Bool) {
        isStreaming = false
        isGrokking = false
        streamingMessageID = nil
        if let start = thinkingStartedAt, !thinkingText.isEmpty {
            thinkingDuration = Date().timeIntervalSince(start)
        }
        if ok {
            connectionState = .ready
            postStatusUpdate("ready")
            return
        }

        lastError = process.state.errorMessage ?? "Failed to send to grok."
        connectionState = process.state == .ready ? .ready : process.state
        postStatusUpdate(statusName(for: connectionState))
        if let idx = messages.firstIndex(where: { $0.id == assistantID }),
           messages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.remove(at: idx)
        }
    }

    func toggleThinkingExpanded() {
        isThinkingExpanded.toggle()
    }

    func clearTurnState() {
        isGrokking = false
        thinkingText = ""
        thinkingDuration = nil
        thinkingStartedAt = nil
        isThinkingExpanded = false
        liveToolCalls = []
    }

    func stop() {
        isStreaming = false
        isGrokking = false
        streamingMessageID = nil
        pendingPermissions.removeAll()
        pendingExitPlan = nil
        pendingQuestions.removeAll()
        process.interrupt()
        connectionState = .ready
        postStatusUpdate("ready")
    }

    func shutdown() async {
        connectionWatchdogTask?.cancel()
        isStreaming = false
        isGrokking = false
        streamingMessageID = nil
        await process.stop()
        connectionState = .idle
        postStatusUpdate("idle")
    }

    func respondToExitPlan(_ request: ExitPlanRequest, verdict: ExitPlanRequest.PlanVerdict, comment: String = "") {
        process.respondToExitPlan(request.id.base, verdict: verdict)
        let marker: String
        switch verdict {
        case .approved: marker = "[Plan approved]"
        case .rejected: marker = "[Plan rejected]"
        case .abandoned: marker = "[Plan cancelled]"
        }
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = trimmedComment.isEmpty ? marker : "\(marker) \(trimmedComment)"
        Task { _ = await send(payload) }
        pendingExitPlan = nil
    }

    func respondToQuestion(_ request: QuestionRequest, answers: [String: String]) {
        process.respondToQuestion(request.id.base, answers: answers)
        pendingQuestions.removeAll { $0.id == request.id }
    }

    func cancelQuestion(_ request: QuestionRequest) {
        process.respondToQuestionCancelled(request.id.base)
        pendingQuestions.removeAll { $0.id == request.id }
    }

    func addFileAttachment(path: String) {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !fileAttachments.contains(where: { $0.path == standardized }) else { return }
        fileAttachments.append(FileAttachment(path: standardized, workspaceRoot: currentWorkspace?.path))
    }

    func removeFileAttachment(id: UUID) {
        fileAttachments.removeAll { $0.id == id }
    }

    func toggleFileAttachmentHidden(id: UUID) {
        guard let idx = fileAttachments.firstIndex(where: { $0.id == id }) else { return }
        fileAttachments[idx].isHidden.toggle()
    }

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
        guard let limit = modelContextTokens[currentModel] else { return "—/—" }
        let used = usedContextTokens ?? 0
        return "\(Self.compactTokenCount(used))/\(Self.compactTokenCount(limit))"
    }

    var contextUsageFraction: Double {
        guard let limit = modelContextTokens[currentModel], limit > 0 else { return 0 }
        return min(1, Double(usedContextTokens ?? 0) / Double(limit))
    }

    var currentModelContextLimit: Int? {
        modelContextTokens[currentModel]
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

    func reportError(_ message: String) {
        lastError = message
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
        for await event in process.acpEventStream {
            handleAcpEvent(event)
        }
    }

    private func handleAcpEvent(_ event: AcpEvent) {
        switch event {
        case .messageChunk(let text):
            isGrokking = false
            appendAssistantText(text)
        case .thoughtChunk(let text):
            isGrokking = false
            if thinkingStartedAt == nil { thinkingStartedAt = Date() }
            thinkingText += text
        case .toolCall(let tc):
            isGrokking = false
            if !liveToolCalls.contains(where: { $0.id == tc.id }) {
                liveToolCalls.append(liveToolCall(from: tc))
            }
            if QuestionRequest.isQuestionTool(tc),
               let items = QuestionRequest.questionsFromToolCall(tc),
               !pendingQuestions.contains(where: { $0.id == AnyHashable(tc.id) }) {
                pendingQuestions.append(QuestionRequest(
                    id: AnyHashable(tc.id),
                    sessionId: process.sessionId ?? "",
                    questions: items,
                    isResolved: false,
                    answerSummary: nil
                ))
            }
        case .toolCallUpdate(let tc):
            if let idx = liveToolCalls.firstIndex(where: { $0.id == tc.id }) {
                liveToolCalls[idx] = mergedToolCall(existing: liveToolCalls[idx], update: tc)
            } else {
                liveToolCalls.append(liveToolCall(from: tc))
            }
            if QuestionRequest.isQuestionTool(tc),
               let items = QuestionRequest.questionsFromToolCall(tc),
               !pendingQuestions.contains(where: { $0.id == AnyHashable(tc.id) }) {
                pendingQuestions.append(QuestionRequest(
                    id: AnyHashable(tc.id),
                    sessionId: process.sessionId ?? "",
                    questions: items,
                    isResolved: false,
                    answerSummary: nil
                ))
            }
        case .plan:
            break
        case .planFileContent(let content):
            if !content.isEmpty, var plan = pendingExitPlan {
                plan.planText = content
                pendingExitPlan = plan
            }
        case .exitPlanRequest(let req):
            pendingExitPlan = req
        case .questionRequest(let req):
            if !pendingQuestions.contains(where: { $0.id == req.id }) {
                pendingQuestions.append(req)
            }
        case .availableCommands(let commands):
            availableSlashCommands = commands
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
        case .contextUsage(let totalTokens):
            usedContextTokens = totalTokens

        case .rawLine(let line):
            appendAssistantText(line)
        case .error(let msg):
            lastError = msg
        }
    }

    private func liveToolCall(from toolCall: ToolCall) -> LiveToolCall {
        LiveToolCall(
            id: toolCall.id,
            title: displayTitle(for: toolCall),
            kind: displayKind(for: toolCall)
        )
    }

    private func mergedToolCall(existing: LiveToolCall, update: ToolCall) -> LiveToolCall {
        let title = isPlaceholderTitle(update.title) ? existing.title : displayTitle(for: update)
        let kind = isPlaceholderKind(update.kind) ? existing.kind : displayKind(for: update)
        return LiveToolCall(id: existing.id, title: title, kind: kind)
    }

    private func displayTitle(for toolCall: ToolCall) -> String {
        if !isPlaceholderTitle(toolCall.title) {
            return toolCall.title
        }
        if let name = toolCall.rawInput?["toolName"] as? String
            ?? toolCall.rawInput?["tool_name"] as? String
            ?? toolCall.rawInput?["name"] as? String {
            return name
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
        return "Tool call"
    }

    private func displayKind(for toolCall: ToolCall) -> String {
        if !isPlaceholderKind(toolCall.kind) {
            return toolCall.kind
        }
        if let name = toolCall.rawInput?["toolName"] as? String
            ?? toolCall.rawInput?["tool_name"] as? String,
           name.hasPrefix("browser_") {
            return "browser"
        }
        return "tool"
    }

    private func isPlaceholderTitle(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "unknown" || normalized == "tool call"
    }

    private func isPlaceholderKind(_ kind: String) -> Bool {
        let normalized = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "unknown"
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
