import Foundation
import Observation
import SwiftUI
import AppKit

@Observable
@MainActor
final class ChatStore {
    private struct SessionSelection: Codable {
        var mode: String?
        var model: String?
    }

    /// Reasoning effort for the active project (not global).
    private var workspaceReasoningEffort: String = ""

    private(set) var messages: [Message] = []
    /// Grok session id restored from disk before a live process is started (lazy restore).
    private(set) var savedGrokSessionID: String?

    /// True when this tab resumes an existing grok session rather than a fresh chat.
    var isResumedSessionTab: Bool {
        grokSessionId != nil || savedGrokSessionID != nil
    }

    func clearMessages() {
        messages.removeAll()
    }

    /// Clears the visible transcript and notifies observers (keeps the live grok session).
    func clearTranscript() {
        clearMessages()
        clearTurnState()
        isStreaming = false
        isGrokking = false
        streamingMessageID = nil
        notifyMessagesChanged()
    }

    /// Chat-only rewind: keep messages up to and including `messageID`, drop the rest.
    @discardableResult
    func rewind(to messageID: UUID) -> Bool {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }) else { return false }
        messages = Array(messages.prefix(through: idx))
        clearTurnState()
        isStreaming = false
        isGrokking = false
        streamingMessageID = nil
        lastError = nil
        notifyMessagesChanged()
        return true
    }
    private(set) var isStreaming = false
    private(set) var lastError: String?
    /// Set when a model switch fails/times out; shown as a dismissible banner in the chat.
    var modelSwitchError: String?
    /// `true` when the failed switch can be resolved by starting a new session; the banner
    /// then offers a "Start New Session" action.
    var modelSwitchNeedsNewSession = false

    // VS Code extension-style turn state
    private(set) var isGrokking = false
    private(set) var thinkingText = ""
    private(set) var thinkingDuration: TimeInterval?
    private(set) var isThinkingExpanded = false
    private(set) var liveToolCalls: [LiveToolCall] = []
    private var thinkingStartedAt: Date?
    /// When the current turn began — drives the elapsed/"warming up" indicator.
    private(set) var turnStartedAt: Date?

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
    /// Local goal state updated when the user sends `/goal …`; cleared on new session.
    private(set) var goalState: SessionGoalState?
    private(set) var fileAttachments: [FileAttachment] = []
    /// Pasted/dropped images queued as vision content for the next prompt.
    private(set) var imageAttachments: [ImageAttachment] = []
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
    private var customModelsByID: [String: CustomModel] = [:]
    private(set) var usedContextTokens: Int?

    // Persist mode/model choices per Grok session id.
    private let sessionSelectionsKey = "grokbuild.sessionSelections.v1"
    private let defaults = UserDefaults.standard
    private var sessionSelections: [String: SessionSelection] = [:]

    /// Stable GrokBuild tab id (`LiveSession.id`) for per-tab model persistence.
    private(set) var tabSessionID: UUID?
    private var tabHasExplicitModel = false

    // MARK: - Session agent (per tab, launched via `--agent`)
    /// Explicit per-tab session-agent selection id. Empty string with `tabHasExplicitAgent`
    /// means "grok default"; when `tabHasExplicitAgent` is false the tab follows the global
    /// default (`grokbuild.selectedAgent`).
    private(set) var currentAgent: String = ""
    private var tabHasExplicitAgent = false
    /// Agents discovered for the current workspace (`grok inspect --json`), loaded lazily for the
    /// composer agent picker.
    private(set) var discoveredAgents: [GrokAgentInfo] = []
    /// ID of the workspace whose agents have been loaded; `nil` means not yet loaded.
    /// Scoped per workspace so switching projects triggers a fresh load.
    private var loadedAgentsWorkspaceID: UUID?

    // MARK: - Scheduled tasks (grok `scheduler_*` tools, mirrored by observing ACP tool calls)
    /// Tasks grok has scheduled, mirrored from observed `scheduler_*` tool activity in this session.
    private(set) var scheduledTasks: [ScheduledTask] = []
    private var scheduledTaskTracker = ScheduledTaskTracker()

    // MARK: - Background activity (scheduled + background shells, monitors, subagents)
    private(set) var backgroundActivities: [BackgroundActivity] = []
    private var backgroundTaskTracker = BackgroundTaskTracker()

    // MARK: - Prompt queue (send while streaming)
    private(set) var promptQueue: [String] = []

    // MARK: - /btw aside panel
    private(set) var btwAsideText: String?
    private var pendingBtw = false
    private var pendingShareURLCapture = false
    private var lastSharedURL: String?

    /// Test-only: whether the next assistant URL should be treated as a `/share` result.
    var isPendingShareURLCaptureForTests: Bool { pendingShareURLCapture }

    /// Test-only: force streaming so queue-send guards can be exercised without a live process.
    func setStreamingForTests(_ value: Bool) {
        isStreaming = value
    }

    // MARK: - Workflow runs (grok `workflow` tools, mirrored by observing ACP tool calls)
    private(set) var workflowRuns: [WorkflowRun] = []
    private var workflowRunTracker = WorkflowRunTracker()

    private var launchForkSession = false
    private var launchNewSessionID: String?

    private(set) var commandHistory: [String] = []
    private var historyIndex: Int?

    let process: GrokProcess
    private(set) var currentWorkspace: Workspace?
    // (removed Agent personas - see AGENTS.md + sub-agents in Grok Build CLI)

    private(set) var streamingMessageID: UUID?
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

    func prepare(workspace: Workspace, savedGrokSessionID: String? = nil) {
        resetSessionUI()
        self.savedGrokSessionID = savedGrokSessionID
        currentWorkspace = workspace
        mergeCustomModels()
        loadWorkspaceReasoningEffort()
    }

    /// Bind this store to a sidebar tab and apply its saved model + agent when present.
    func bindTabSession(_ id: UUID, savedModel: String?, savedAgent: String? = nil) {
        tabSessionID = id
        tabHasExplicitModel = false
        tabHasExplicitAgent = false
        currentAgent = defaultAgentSelection
        if let savedAgent {
            currentAgent = savedAgent
            tabHasExplicitAgent = true
        }
        guard let savedModel = savedModel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !savedModel.isEmpty else { return }
        applyTabModel(savedModel)
    }

    /// Global default session agent from Settings → Agents (`grokbuild.selectedAgent`).
    private var defaultAgentSelection: String {
        defaults.string(forKey: GrokSettingsKeys.selectedAgent) ?? ""
    }

    /// The agent this tab will actually launch with: an explicit per-tab override when set,
    /// otherwise the global default.
    var effectiveAgentSelection: String {
        tabHasExplicitAgent ? currentAgent : defaultAgentSelection
    }

    /// `true` when this tab overrides the global default agent.
    var hasExplicitAgent: Bool { tabHasExplicitAgent }

    /// Display label for the tab's effective session agent.
    var effectiveAgentDisplayName: String {
        GrokAgentProfiles.displayName(for: effectiveAgentSelection)
    }

    /// The value to persist for this tab (nil when it follows the global default).
    var persistedAgentSelection: String? {
        tabHasExplicitAgent ? currentAgent : nil
    }

    /// Set this session's agent and restart its grok process (agents can only change at launch).
    func setSessionAgent(_ selection: String) async {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        // No-op when this tab already explicitly uses the chosen agent.
        if tabHasExplicitAgent, trimmed == currentAgent { return }
        currentAgent = trimmed
        tabHasExplicitAgent = true
        notifyAgentChanged()
        guard currentWorkspace != nil else { return }
        await restartProcess(resumeSessionID: grokSessionId ?? savedGrokSessionID)
        appendSystemNote("Switched session agent to \(GrokAgentProfiles.displayName(for: trimmed)).")
    }

    /// Load agents discovered for the current workspace (reloads when the workspace changes).
    func loadDiscoveredAgentsIfNeeded() async {
        guard let workspaceID = currentWorkspace?.id,
              loadedAgentsWorkspaceID != workspaceID else { return }
        loadedAgentsWorkspaceID = workspaceID
        let agents = (try? await GrokCLIService().listAgents(cwd: currentWorkspace?.path)) ?? []
        discoveredAgents = agents
    }

    /// Reload per-project reasoning effort only (model stays per tab).
    func syncWorkspaceReasoningEffortFromStorage() {
        loadWorkspaceReasoningEffort()
    }

    /// @deprecated Use `syncWorkspaceReasoningEffortFromStorage()` — model is per tab now.
    func syncWorkspaceAgentSettingsFromStorage() {
        syncWorkspaceReasoningEffortFromStorage()
    }

    /// Apply the tab's `currentModel` to a live grok process when switching tabs.
    func syncTabModelToLiveProcessIfNeeded() {
        guard connectionState != .idle,
              availableModels.contains(currentModel),
              process.currentModelId != currentModel else { return }
        process.setModel(currentModel)
    }

    func clearProject() {
        resetSessionUI()
        currentWorkspace = nil
    }

    private func resetSessionUI() {
        messages.removeAll()
        streamingMessageID = nil
        authRequiredMessage = nil
        pendingPermissions.removeAll()
        pendingExitPlan = nil
        pendingQuestions.removeAll()
        fileAttachments.removeAll()
        imageAttachments.removeAll()
        goalState = nil
        clearWorkflowRunState()
        clearBackgroundTaskState()
        promptQueue.removeAll()
        btwAsideText = nil
        pendingBtw = false
        pendingShareURLCapture = false
        clearTurnState()
        connectionState = .idle
        lastError = nil
    }

    var hasUserMessages: Bool {
        messages.contains { $0.role == .user }
    }

    func start(workspace: Workspace, resumeSession: GrokSessionInfo? = nil, preserveMessages: Bool = false) async {
        currentWorkspace = workspace
        mergeCustomModels()
        loadWorkspaceReasoningEffort()
        if !preserveMessages {
            clearTransientSessionState()
        } else {
            clearTurnState()
        }
        await restartProcess(resumeSessionID: resumeSession?.id)
    }

    /// Restore a previously saved transcript when reopening a session tab.
    func restorePersistedMessages(_ saved: [Message]) {
        messages = filteredPersistedMessages(saved)
        streamingMessageID = nil
    }

    /// Load persisted (and optionally grok on-disk) transcript for a tab.
    func restorePersistedMessages(
        for sessionID: UUID,
        grokSessionID: String?,
        workspace: Workspace
    ) {
        let saved = SessionMessageStore.messages(for: sessionID)
        let recovered = SessionTranscriptRecovery.recoverIfNeeded(
            sessionID: sessionID,
            grokSessionID: grokSessionID,
            workspacePath: workspace.path,
            currentMessages: saved
        )
        restorePersistedMessages(recovered ?? saved)
    }

    /// Merge disk transcript into memory without dropping messages already loaded.
    func mergePersistedMessages(_ saved: [Message]) {
        let filtered = filteredPersistedMessages(saved)
        guard !filtered.isEmpty else { return }
        if messages.isEmpty {
            messages = filtered
            streamingMessageID = nil
            return
        }
        var seen = Set(messages.map(\.id))
        for message in filtered where !seen.contains(message.id) {
            messages.append(message)
            seen.insert(message.id)
        }
        streamingMessageID = nil
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
        imageAttachments.removeAll()
        goalState = nil
        clearWorkflowRunState()
        if currentWorkspace != nil {
            await restartProcess()
        }
    }

    func resumeSession(_ session: GrokSessionInfo) async {
        guard currentWorkspace != nil else {
            lastError = "Select a project first."
            return
        }
        clearTransientSessionState()
        await restartProcess(resumeSessionID: session.id)
    }

    /// Clears in-flight turn UI and pending prompts without wiping the saved transcript.
    private func clearTransientSessionState() {
        streamingMessageID = nil
        authRequiredMessage = nil
        pendingPermissions.removeAll()
        pendingExitPlan = nil
        pendingQuestions.removeAll()
        fileAttachments.removeAll()
        imageAttachments.removeAll()
        goalState = nil
        messages.removeAll()
        clearWorkflowRunState()
        clearTurnState()
    }

    private func clearWorkflowRunState() {
        workflowRunTracker.reset()
        workflowRuns = []
    }

    private func clearBackgroundTaskState() {
        backgroundTaskTracker.reset()
        backgroundActivities = []
    }

    private func restartProcess(resumeSessionID: String? = nil) async {
        guard let ws = currentWorkspace else { return }
        clearTurnState()
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
        let modelForLaunch = modelForProcessLaunch(fallbackSelection: savedSelection)
        let reasoningEffortForLaunch = modelSupportsReasoningEffort(modelForLaunch) ? workspaceReasoningEffort : ""
        let browserSettings = BrowserSettingsStore.loadApplied()
        let computerUseSettings = ComputerUseSettingsStore.loadApplied()
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
        if computerUseSettings.enabled {
            do {
                try ComputerUseSkillInstaller.installIfNeeded(settings: computerUseSettings)
            } catch {
                lastError = "Computer Use skill install failed: \(error.localizedDescription)"
            }
        }
        let mcpServers = [
            AgentBrowserService.browserMCPConfig(settings: browserSettings),
            ComputerUseService.computerUseMCPConfig(settings: computerUseSettings)
        ].compactMap { $0 }
        let opts = GrokLaunchOptions(
            agent: GrokAgentProfiles.launchArgument(for: effectiveAgentSelection),
            // Memory is a single app-scoped toggle: on → `--experimental-memory`, off → `--no-memory`.
            noMemory: !settings.memoryEnabled,
            experimentalMemory: settings.memoryEnabled,
            permissionMode: settings.permissionMode,
            reasoningEffort: reasoningEffortForLaunch,
            model: modelForLaunch.isEmpty ? nil : modelForLaunch,
            sandboxProfile: settings.sandboxProfile,
            disableWebSearch: settings.disableWebSearch,
            noSubagents: settings.noSubagents,
            allowRules: lineList(settings.allowRules),
            denyRules: lineList(settings.denyRules),
            resumeSessionID: resumeSessionID,
            forkSession: launchForkSession,
            newSessionID: launchNewSessionID,
            mcpServers: mcpServers
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
        if process.sessionLoadStartedFreshFallback {
            let hasLocalTranscript = messages.contains {
                $0.role == .user
                    || ($0.role == .assistant
                        && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if hasLocalTranscript {
                appendSystemNote(
                    "Previous grok session expired; started a fresh chat. Your saved transcript in this tab is still shown."
                )
            } else {
                appendSystemNote(
                    "Previous grok session expired; started a fresh chat. The prior transcript could not be restored."
                )
            }
            notifyMessagesChanged()
        }
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
        await deliverPrompt(text, waitForCompletion: false)
    }

    @discardableResult
    func sendAndWait(_ text: String) async -> Bool {
        await deliverPrompt(text, waitForCompletion: true)
    }

    var hasGoalCommand: Bool {
        availableSlashCommands.contains { $0.name == "goal" }
    }

    @discardableResult
    func setGoal(_ objective: String, budget: Int? = nil) async -> Bool {
        let trimmed = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let budget {
            return await send("/goal \(trimmed) --budget \(budget)")
        }
        return await send("/goal \(trimmed)")
    }

    var hasShareCommand: Bool {
        availableSlashCommands.contains { $0.name == "share" }
    }

    var hasBtwCommand: Bool {
        availableSlashCommands.contains { $0.name == "btw" }
    }

    var hasCreateSkillCommand: Bool {
        availableSlashCommands.contains { $0.name == "create-skill" }
    }

    var hasForkCommand: Bool {
        availableSlashCommands.contains { $0.name == "fork" }
    }

    @discardableResult
    func shareSession() async -> Bool {
        pendingShareURLCapture = true
        let ok = await send("/share")
        if !ok {
            // Avoid capturing an unrelated later assistant URL if /share never started.
            pendingShareURLCapture = false
        }
        return ok
    }

    func copyLastSharedURLToPasteboard() -> Bool {
        guard let lastSharedURL else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastSharedURL, forType: .string)
        return true
    }

    func removeQueuedPrompt(at index: Int) {
        guard promptQueue.indices.contains(index) else { return }
        promptQueue.remove(at: index)
    }

    func enqueuePrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        promptQueue.append(trimmed)
    }

    /// App setting: steer the running turn by default when sending mid-turn.
    static var steerByDefaultEnabled: Bool {
        UserDefaults.standard.bool(forKey: GrokSettingsKeys.steerByDefault)
    }

    /// Injects a prompt into the running turn without cancelling it (grok "steering").
    /// Records the prompt in the transcript so the injected instruction is visible.
    @discardableResult
    func steerRunningTurn(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isStreaming else { return false }
        guard process.steer(trimmed) else { return false }
        if commandHistory.last != trimmed { commandHistory.append(trimmed) }
        messages.append(Message(role: .user, content: trimmed))
        notifyMessagesChanged()
        return true
    }

    /// True when grok is blocked waiting on the user (permission / plan / question prompts).
    var isAwaitingUser: Bool {
        !pendingPermissions.isEmpty || pendingExitPlan != nil || !pendingQuestions.isEmpty
    }

    /// True when the session is in a failed connection / process state.
    var hasErrorState: Bool {
        if case .failed = connectionState { return true }
        return false
    }

    /// Derives the sidebar/tab activity status. `hasUnreadCompletion` is tracked by the UI
    /// (cleared on focus), so it is passed in rather than owned here.
    func activityStatus(hasUnreadCompletion: Bool) -> SessionActivityStatus {
        SessionStatusResolver.resolve(SessionStatusInputs(
            isStreaming: isStreaming,
            isAwaitingUser: isAwaitingUser,
            hasError: hasErrorState,
            hasUnreadCompletion: hasUnreadCompletion
        ))
    }

    /// Steers a queued prompt into the running turn (used by the queue "Steer" action).
    @discardableResult
    func steerQueuedPromptNow(at index: Int) -> Bool {
        guard promptQueue.indices.contains(index), isStreaming else { return false }
        let text = promptQueue[index]
        guard steerRunningTurn(text) else { return false }
        if promptQueue.indices.contains(index) { promptQueue.remove(at: index) }
        return true
    }

    func sendQueuedPromptNow(at index: Int) async -> Bool {
        guard promptQueue.indices.contains(index) else { return false }
        guard !isStreaming else {
            lastError = "Wait for the current response to finish."
            return false
        }
        let text = promptQueue.remove(at: index)
        let ok = await deliverPrompt(text, waitForCompletion: false, fromQueue: true)
        if !ok {
            // Put the prompt back so a failed send does not drop queued work.
            let insertAt = min(index, promptQueue.count)
            promptQueue.insert(text, at: insertAt)
        }
        return ok
    }

    func clearBtwAside() {
        btwAsideText = nil
    }

    /// Start a new grok process forked from an existing session id (new tab).
    func startForked(workspace: Workspace, fromSessionID: String) async {
        currentWorkspace = workspace
        mergeCustomModels()
        loadWorkspaceReasoningEffort()
        launchForkSession = true
        launchNewSessionID = UUID().uuidString
        clearTransientSessionState()
        await restartProcess(resumeSessionID: fromSessionID)
        launchForkSession = false
        launchNewSessionID = nil
        appendSystemNote("Forked from session \(fromSessionID.prefix(8))…")
    }

    @discardableResult
    func forkIntoWorktree(branch: String, path: String, fromSessionID: String?) async -> Bool {
        if hasForkCommand {
            var command = "/fork --worktree"
            if !branch.isEmpty { command += " --branch \(branch)" }
            if !path.isEmpty { command += " --path \(path)" }
            return await send(command)
        }
        guard let fromSessionID else { return false }
        // Fallback: caller should create worktree via GitService then startForked.
        _ = fromSessionID
        return false
    }

    @discardableResult
    func refreshGoalStatus() async -> Bool {
        await send("/goal status")
    }

    @discardableResult
    func pauseGoal() async -> Bool {
        await send("/goal pause")
    }

    @discardableResult
    func resumeGoal() async -> Bool {
        await send("/goal resume")
    }

    @discardableResult
    func clearGoal() async -> Bool {
        await send("/goal clear")
    }

    // MARK: - Scheduled tasks

    /// True when grok advertises the `/loop` command (scheduling is available in this session).
    var hasLoopCommand: Bool {
        availableSlashCommands.contains { $0.name == "loop" }
    }

    /// Ask grok to enumerate its scheduled tasks (drives `scheduler_list`); the reply's tool
    /// output refreshes ``scheduledTasks`` authoritatively.
    @discardableResult
    func refreshScheduledTasks() async -> Bool {
        await send("List all my scheduled tasks (use scheduler_list) and do nothing else.")
    }

    /// Schedule a recurring prompt via grok's `/loop` command.
    @discardableResult
    func createScheduledTask(interval: String, prompt: String) async -> Bool {
        let trimmedInterval = interval.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInterval.isEmpty, !trimmedPrompt.isEmpty else { return false }
        return await send("/loop \(trimmedInterval) \(trimmedPrompt)")
    }

    /// Ask grok to cancel a scheduled task by id (drives `scheduler_delete`).
    @discardableResult
    func cancelScheduledTask(_ id: String) async -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return await send("Cancel the scheduled task with id \(trimmed) (use scheduler_delete) and do nothing else.")
    }

    // MARK: - Workflow runs

    var hasWorkflowCommand: Bool {
        availableSlashCommands.contains { $0.name == "workflow" || $0.name == "workflows" }
    }

    var hasDeepResearchCommand: Bool {
        availableSlashCommands.contains { $0.name == "deep-research" }
    }

    @discardableResult
    func refreshWorkflowRuns() async -> Bool {
        if hasWorkflowCommand {
            return await send("/workflows")
        }
        return await send("List all my workflow runs (use the workflow tool) and do nothing else.")
    }

    @discardableResult
    func pauseWorkflowRun(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return await send("/workflow pause \(trimmed)")
    }

    @discardableResult
    func resumeWorkflowRun(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return await send("/workflow resume \(trimmed)")
    }

    @discardableResult
    func stopWorkflowRun(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return await send("/workflow stop \(trimmed)")
    }

    @discardableResult
    func startDeepResearch(_ query: String) async -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return await send("/deep-research \(trimmed)")
    }

    @discardableResult
    func launchSavedWorkflow(name: String, args: [String: Any]? = nil) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let args, !args.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: args),
           let json = String(data: data, encoding: .utf8) {
            return await send("/workflow \(trimmed) \(json)")
        }
        return await send("/workflow \(trimmed)")
    }

    // MARK: - Memory

    /// Save a note to grok's global memory (`~/.grok/memory/MEMORY.md`). grok's file watcher
    /// reindexes it on the next memory search, so it becomes recallable in future sessions.
    ///
    /// This writes the file directly rather than sending `/remember`: that slash command is a
    /// TUI-only pager builtin and is not exposed over `grok agent stdio` (ACP).
    @discardableResult
    func remember(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            let url = try MemoryStore.appendGlobalNote(trimmed)
            appendSystemNote("Remembered — saved to \(url.path).")
            return true
        } catch {
            lastError = "Couldn't save memory note: \(error.localizedDescription)"
            return false
        }
    }

    private func deliverPrompt(_ text: String, waitForCompletion: Bool, fromQueue: Bool = false) async -> Bool {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty
                || fileAttachments.contains(where: { !$0.isHidden })
                || !imageAttachments.isEmpty else { return false }
        guard currentWorkspace != nil else {
            lastError = "Select a project first."
            return false
        }
        if isStreaming {
            if waitForCompletion {
                lastError = "Wait for the current response to finish."
                return false
            }
            if !fromQueue {
                // Fold attachment notes into the payload and clear chips so they cannot stick
                // to a later send. Mid-turn steer/queue is text-only (no ACP image blocks).
                let payload = consumeComposerAttachments(into: trimmed)
                guard !payload.isEmpty else { return false }
                // Steer the running turn when enabled, otherwise queue for after it.
                let decision = SteerDecision.resolve(
                    isStreaming: true,
                    steerByDefault: Self.steerByDefaultEnabled
                )
                if decision == .steer, steerRunningTurn(payload) {
                    return true
                }
                enqueuePrompt(payload)
                return true
            }
            lastError = "Wait for the current response to finish."
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
        turnStartedAt = Date()

        let promptImages = imageAttachments.map {
            PromptImageContent(mimeType: $0.mimeType, base64: $0.base64)
        }
        trimmed = consumeComposerAttachments(into: trimmed)
        if let goalCommand = GoalCommand.parse(from: trimmed) {
            SessionGoalStateMutation.apply(goalCommand, to: &goalState)
        }
        if trimmed.lowercased().hasPrefix("/btw") {
            pendingBtw = true
        }

        let userMsg = Message(role: .user, content: trimmed)
        messages.append(userMsg)
        notifyMessagesChanged()

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

        if waitForCompletion {
            let ok = await process.send(payload, images: promptImages)
            finishPrompt(assistantID: assistantID, ok: ok)
            return ok
        }

        Task { [weak self] in
            guard let self else { return }
            let ok = await self.process.send(payload, images: promptImages)
            self.finishPrompt(assistantID: assistantID, ok: ok)
        }

        return true
    }

    private func finishPrompt(assistantID: UUID, ok: Bool) {
        if ok, let idx = messages.firstIndex(where: { $0.id == assistantID }) {
            captureAsideAndShare(from: messages[idx].content)
        }

        isStreaming = false
        isGrokking = false
        turnStartedAt = nil
        streamingMessageID = nil
        if let start = thinkingStartedAt, !thinkingText.isEmpty {
            thinkingDuration = Date().timeIntervalSince(start)
        }
        if ok {
            connectionState = .ready
            postStatusUpdate("ready")
            notifyMessagesChanged()
            TurnCompletionSound.playIfNeeded()
            drainPromptQueueIfNeeded()
            return
        }

        pendingShareURLCapture = false
        lastError = process.state.errorMessage ?? "Failed to send to grok."
        connectionState = process.state == .ready ? .ready : process.state
        postStatusUpdate(statusName(for: connectionState))
        if let idx = messages.firstIndex(where: { $0.id == assistantID }),
           messages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.remove(at: idx)
        }
        notifyMessagesChanged()
    }

    private func drainPromptQueueIfNeeded() {
        guard !isStreaming, !promptQueue.isEmpty else { return }
        let next = promptQueue.removeFirst()
        Task { [weak self] in
            _ = await self?.deliverPrompt(next, waitForCompletion: false)
        }
    }

    private func captureAsideAndShare(from assistantText: String) {
        let trimmed = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if pendingBtw {
            btwAsideText = trimmed
            pendingBtw = false
        }
        if pendingShareURLCapture, let url = ShareURLParser.firstURL(in: trimmed) {
            lastSharedURL = url
            pendingShareURLCapture = false
            appendSystemNote("Share link copied to clipboard.")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
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
        turnStartedAt = nil
        isThinkingExpanded = false
        liveToolCalls = []
    }

    func stop() {
        isStreaming = false
        isGrokking = false
        turnStartedAt = nil
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

    /// Folds visible file/image attachment notes into `text` and clears the chips so they
    /// cannot stick to a later send (critical on the mid-turn steer/queue path).
    @discardableResult
    private func consumeComposerAttachments(into text: String) -> String {
        var payload = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let attachmentBlock = AttachmentPromptBuilder.build(from: fileAttachments) {
            payload = payload.isEmpty ? attachmentBlock : "\(attachmentBlock)\n\n\(payload)"
        }
        if let imageNote = AttachmentPromptBuilder.imageNote(from: imageAttachments) {
            payload = payload.isEmpty ? imageNote : "\(payload)\n\n\(imageNote)"
        }
        fileAttachments.removeAll()
        imageAttachments.removeAll()
        return payload
    }

    func addFileAttachment(path: String) {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !fileAttachments.contains(where: { $0.path == standardized }) else { return }
        fileAttachments.append(FileAttachment(path: standardized, workspaceRoot: currentWorkspace?.path))
    }

    func removeFileAttachment(id: UUID) {
        fileAttachments.removeAll { $0.id == id }
    }

    /// Attach an image file as vision content (not a path chip). Silently ignores unreadable or
    /// unsupported files.
    func addImageAttachment(path: String) {
        guard let mimeType = ImageAttachmentSupport.mimeType(forPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
        imageAttachments.append(ImageAttachment(
            displayName: ImageAttachmentSupport.displayName(forPath: path),
            mimeType: mimeType,
            data: data
        ))
    }

    /// Attach raw pasted/dropped image bytes as vision content.
    func addImageAttachment(data: Data, mimeType: String, displayName: String) {
        guard !data.isEmpty else { return }
        imageAttachments.append(ImageAttachment(displayName: displayName, mimeType: mimeType, data: data))
    }

    func removeImageAttachment(id: UUID) {
        imageAttachments.removeAll { $0.id == id }
    }

    /// True when a prompt can be sent from attachments alone (visible file chip or any image).
    var hasSendableAttachments: Bool {
        hasVisibleFileAttachments || !imageAttachments.isEmpty
    }

    /// Sends `/compact` to summarize context. No-op while streaming or without a workspace.
    @discardableResult
    func compactContext() async -> Bool {
        guard currentWorkspace != nil, !isStreaming else { return false }
        return await send("/compact")
    }

    func toggleFileAttachmentHidden(id: UUID) {
        guard let idx = fileAttachments.firstIndex(where: { $0.id == id }) else { return }
        fileAttachments[idx].isHidden.toggle()
    }

    var hasVisibleFileAttachments: Bool {
        fileAttachments.contains { !$0.isHidden }
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

    var currentReasoningEffort: String {
        workspaceReasoningEffort
    }

    var currentReasoningEffortLevel: ReasoningEffortLevel {
        ReasoningEffortLevel(storedValue: currentReasoningEffort)
    }

    func reasoningEffortDisplayName(_ raw: String) -> String {
        ReasoningEffortLevel(storedValue: raw).displayName
    }

    func needsReasoningEffortConfirmation(for effort: String) -> Bool {
        effort != currentReasoningEffort && hasUserMessages
    }

    func applyReasoningEffort(_ effort: String, strategy: ReasoningEffortRestartStrategy) async {
        guard effort != currentReasoningEffort else { return }
        workspaceReasoningEffort = effort
        saveWorkspaceAgentSettings()
        guard currentWorkspace != nil else { return }

        if strategy == .summarizeAndRestart, hasUserMessages, connectionState == .ready, !isStreaming {
            _ = await sendAndWait("/compact")
        }

        let resumeID = process.sessionId
        await restartProcess(resumeSessionID: resumeID)
        appendSystemNote("Reasoning effort: \(reasoningEffortDisplayName(effort)).")
    }

    func setModel(_ model: String) {
        guard availableModels.contains(model) else { return }
        let previous = currentModel
        currentModel = model
        modelSwitchError = nil
        modelSwitchNeedsNewSession = false
        process.modelSwitchError = nil
        process.modelSwitchNeedsNewSession = false
        process.setModel(model)
        tabHasExplicitModel = true
        saveCurrentSessionSelection()
        notifyModelChanged()

        // Reconcile after the switch settles: if grok rejected/timed out the change,
        // restore the previous selection and surface the reason. Bounded so it can't hang.
        Task { [weak self] in
            guard let self else { return }
            for _ in 0..<28 {  // ~14s, just past the 12s set_model timeout
                try? await Task.sleep(for: .milliseconds(500))
                if let err = self.process.modelSwitchError {
                    self.currentModel = previous
                    self.modelSwitchError = err
                    self.modelSwitchNeedsNewSession = self.process.modelSwitchNeedsNewSession
                    self.saveCurrentSessionSelection()
                    return
                }
                if !self.process.modelSwitchPending { return }  // RPC completed successfully
            }
        }
    }

    func modelDisplayName(_ id: String) -> String {
        modelDisplayNames[id] ?? id
    }

    var currentModelSupportsReasoningEffort: Bool {
        modelSupportsReasoningEffort(currentModel)
    }

    var isCurrentModelCustom: Bool {
        isCustomModel(currentModel)
    }

    func isCustomModel(_ id: String) -> Bool {
        customModelsByID[id] != nil
    }

    func modelSupportsReasoningEffort(_ id: String) -> Bool {
        customModelsByID[id]?.supportsReasoningEffort ?? true
    }

    func modelCapabilityHint(for id: String) -> String? {
        guard let model = customModelsByID[id] else { return nil }
        var pieces = ["Custom model"]
        if let tokens = model.contextTokens {
            pieces.append("\(Self.compactTokenCount(tokens)) context")
        } else {
            pieces.append("context unknown")
        }
        pieces.append(model.supportsReasoningEffort ? "reasoning effort on" : "reasoning effort off")
        if model.supportsVision {
            pieces.append("vision")
        }
        if model.supportsThinkingDisplay {
            pieces.append("thinking")
        }
        return pieces.joined(separator: " · ")
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
        case .schedulerActivity(let payload):
            scheduledTaskTracker.apply(update: payload)
            scheduledTasks = scheduledTaskTracker.tasks
            backgroundTaskTracker.apply(update: payload)
            backgroundActivities = backgroundTaskTracker.activities
        case .workflowActivity(let payload):
            workflowRunTracker.apply(update: payload)
            workflowRuns = workflowRunTracker.runs
        case .backgroundActivity(let payload):
            backgroundTaskTracker.apply(update: payload)
            backgroundActivities = backgroundTaskTracker.activities
            scheduledTasks = backgroundTaskTracker.activities.compactMap(\.scheduledTask)
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

    private func filteredPersistedMessages(_ saved: [Message]) -> [Message] {
        saved.filter {
            !SessionMessageStore.isLegacyResumeNote($0)
                && !SessionMessageStore.isStaleSessionFallbackNote($0)
        }
    }

    private func notifyMessagesChanged() {
        NotificationCenter.default.post(name: .liveSessionMessagesChanged, object: self)
    }

    private func notifyModelChanged() {
        NotificationCenter.default.post(name: .liveSessionModelChanged, object: self)
    }

    private func notifyAgentChanged() {
        NotificationCenter.default.post(name: .liveSessionAgentChanged, object: self)
    }

    private func loadPermissionSettings() -> GrokPermissionSettings {
        GrokPermissionSettings(
            permissionMode: defaults.string(forKey: GrokSettingsKeys.permissionMode) ?? GrokPermissionSettings.defaults.permissionMode,
            sandboxProfile: defaults.string(forKey: GrokSettingsKeys.sandboxProfile) ?? "",
            reasoningEffort: workspaceReasoningEffort,
            disableWebSearch: defaults.bool(forKey: GrokSettingsKeys.disableWebSearch),
            noSubagents: defaults.bool(forKey: GrokSettingsKeys.noSubagents),
            allowRules: defaults.string(forKey: GrokSettingsKeys.allowRules) ?? "",
            denyRules: defaults.string(forKey: GrokSettingsKeys.denyRules) ?? "",
            selectedAgent: defaults.string(forKey: GrokSettingsKeys.selectedAgent) ?? "",
            memoryEnabled: defaults.bool(forKey: GrokSettingsKeys.memoryEnabled)
        )
    }

    /// Whether cross-session memory is enabled for new/restarted sessions (Settings → Memory).
    var isMemoryEnabled: Bool {
        defaults.bool(forKey: GrokSettingsKeys.memoryEnabled)
    }

    private func lineList(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func syncModelsFromProcess() {
        if !process.availableModelsInfo.isEmpty {
            availableModels = process.availableModelsInfo.map { $0.id }
            modelDisplayNames = Dictionary(uniqueKeysWithValues: process.availableModelsInfo.map { ($0.id, $0.name) })
            modelContextTokens = Dictionary(uniqueKeysWithValues: process.availableModelsInfo.compactMap { model in
                guard let tokens = model.contextTokens else { return nil }
                return (model.id, tokens)
            })
        }
        mergeCustomModels()
    }

    /// Fold custom OpenAI-compatible models from `~/.grok/config.toml` into the picker so they
    /// are selectable alongside the agent's built-in models. Without this they are only reachable
    /// by typing `/model <id>`, since the composer list is otherwise driven by the agent's
    /// advertised `modelState.availableModels`. Idempotent — safe to call on every resync.
    private func mergeCustomModels() {
        let customModels = CustomModelStore.load().models
        customModelsByID = [:]
        for model in customModels {
            customModelsByID[model.id] = model
        }
        let acpContextModelIDs = Set(process.availableModelsInfo.compactMap { model in
            model.contextTokens == nil ? nil : model.id
        })

        for model in customModels {
            if !availableModels.contains(model.id) {
                availableModels.append(model.id)
            }
            // Prefer the explicit display name, then the provider model name (what the connected
            // agent reports), then the table id — so the label is consistent before/after connect.
            let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let providerModel = model.model.trimmingCharacters(in: .whitespacesAndNewlines)
            modelDisplayNames[model.id] = !name.isEmpty ? name : (!providerModel.isEmpty ? providerModel : model.id)
            if !acpContextModelIDs.contains(model.id) {
                if let contextTokens = model.contextTokens {
                    modelContextTokens[model.id] = contextTokens
                } else {
                    modelContextTokens.removeValue(forKey: model.id)
                }
            }
        }
    }

    private func workspaceDefaultModel() -> String? {
        guard let workspace = currentWorkspace else { return nil }
        let model = SessionLayoutStore.agentSettings(for: workspace.id).model?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let model, !model.isEmpty else { return nil }
        return model
    }

    private func loadWorkspaceReasoningEffort() {
        guard let workspace = currentWorkspace else { return }
        let saved = SessionLayoutStore.agentSettings(for: workspace.id)
        // A workspace with no saved effort inherits the global default (Settings →
        // Permissions → "Default reasoning effort"); the composer picker then overrides
        // it per project.
        let globalDefault = defaults.string(forKey: GrokSettingsKeys.reasoningEffort) ?? ""
        workspaceReasoningEffort = Self.resolveReasoningEffort(saved: saved.reasoningEffort, globalDefault: globalDefault)
    }

    private func applyTabModel(_ model: String) {
        guard availableModels.contains(model) else { return }
        currentModel = model
        tabHasExplicitModel = true
    }

    private func modelForProcessLaunch(fallbackSelection: SessionSelection?) -> String {
        if tabHasExplicitModel, availableModels.contains(currentModel) {
            return currentModel
        }
        if let model = fallbackSelection?.model,
           availableModels.contains(model) {
            currentModel = model
            tabHasExplicitModel = true
            return model
        }
        if let model = workspaceDefaultModel(), availableModels.contains(model) {
            currentModel = model
            return model
        }
        if availableModels.contains(currentModel) {
            return currentModel
        }
        if let first = availableModels.first {
            currentModel = first
            return first
        }
        return currentModel
    }

    /// Resolves the effective per-project reasoning effort: an explicitly saved value
    /// (including an empty "Default") wins; otherwise the workspace inherits the global
    /// default configured in Settings → Permissions.
    nonisolated static func resolveReasoningEffort(saved: String?, globalDefault: String) -> String {
        saved ?? globalDefault
    }

    private func saveWorkspaceAgentSettings() {
        guard let workspace = currentWorkspace else { return }
        var existing = SessionLayoutStore.agentSettings(for: workspace.id)
        existing.reasoningEffort = workspaceReasoningEffort
        SessionLayoutStore.saveAgentSettings(existing, for: workspace.id)
        NotificationCenter.default.post(
            name: .workspaceAgentSettingsChanged,
            object: nil,
            userInfo: ["workspaceID": workspace.id]
        )
    }

    private func restoreSessionSelection(_ fallbackSelection: SessionSelection?) {
        let selection = process.sessionId.flatMap { sessionSelections[$0] } ?? fallbackSelection

        if tabHasExplicitModel, availableModels.contains(currentModel) {
            if process.currentModelId != currentModel {
                process.setModel(currentModel)
            }
        } else if let processModel = process.currentModelId, availableModels.contains(processModel) {
            currentModel = processModel
            tabHasExplicitModel = true
        } else if let model = selection?.model, availableModels.contains(model) {
            currentModel = model
            tabHasExplicitModel = true
            if process.currentModelId != model {
                process.setModel(model)
            }
        } else if let model = workspaceDefaultModel(), availableModels.contains(model) {
            currentModel = model
            if process.currentModelId != model {
                process.setModel(model)
            }
        } else if availableModels.contains(currentModel) {
            if process.currentModelId != currentModel {
                process.setModel(currentModel)
            }
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
