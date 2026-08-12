import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ProjectOpenTarget {
    case finder
    case cursor
    case vsCode
    case terminal
    case iTerm
    case zed
}

struct ChatView: View {
    @Bindable var store: ChatStore
    var reviewFileCount: Int = 0
    var isReviewVisible: Bool = false
    var onToggleReview: () -> Void = {}
    var onSelectSession: (UUID) -> Void = { _ in }
    var onBrowseSessions: () -> Void = {}
    var onNewSession: () -> Void = {}
    var onAddProject: () -> Void = {}
    var onOpenProjectIn: (ProjectOpenTarget) -> Void = { _ in }
    var onToggleBrowserTools: () -> Void = {}
    var onSelectBrowserRuntime: (BrowserRuntimeMode) -> Void = { _ in }
    var onToggleComputerUse: () -> Void = {}
    var onOpenBrowserSettings: () -> Void = {}
    var onOpenComputerUseSettings: () -> Void = {}
    var onOpenAgentSettings: () -> Void = {}
    var onOpenMemorySettings: () -> Void = {}
    var onOpenWorkflowSettings: () -> Void = {}
    var onForkSession: () -> Void = {}
    var onOpenDashboard: () -> Void = {}
    var onSwitchBranch: () -> Void = {}

    @State private var input: String = ""
    @State private var isFileDropTargeted = false
    @State private var fileMentionIndex: [String] = []
    @State private var mentionActiveIndex = 0
    @State private var slashActiveIndex = 0
    @State private var slashSkillsExpanded = false
    @State private var slashCommandsExpanded = false
    @State private var toolActivityExpanded = false
    @State private var thinkingScrollTask: Task<Void, Never>?
    @State private var voiceInput = VoiceInputService()
    @State private var pendingReasoningEffortChange: String?
    @State private var isModelSelectorOpen = false
    @FocusState private var inputFocused: Bool
    @AppStorage(BrowserSettingsKeys.appliedEnabled) private var browserToolsEnabled = BrowserSettings.defaults.enabled
    @AppStorage(ComputerUseSettingsKeys.appliedEnabled) private var computerUseEnabled = ComputerUseSettings.defaults.enabled
    @AppStorage(GrokSettingsKeys.memoryEnabled) private var memoryEnabled = GrokPermissionSettings.defaults.memoryEnabled
    @AppStorage(GrokSettingsKeys.privacyMode) private var privacyMode = false

    @State private var showMemoryBrowser = false
    @State private var showRememberPrompt = false
    @State private var memoryNoteText = ""
    @State private var cachedCustomSubagentNames: [String] = []
    @State private var showSavedWorkflows = false
    @State private var showDeepResearch = false
    @State private var showSetGoal = false
    @State private var showCreateSkill = false
    @State private var showImagine = false
    @State private var createSkillName = ""
    @State private var imaginePrompt = ""
    @State private var workflowsEnabled = WorkflowsConfigStore.loadEnabled()
    @State private var rewindTargetID: UUID?

    private var slashMatch: (query: String, range: Range<String.Index>)? {
        SlashAutocomplete.match(in: input)
    }

    private var filteredSlashCommands: [SlashCommand] {
        guard let match = slashMatch else { return [] }
        let q = match.query.lowercased()
        return store.availableSlashCommands.filter { $0.name.lowercased().hasPrefix(q) }
    }

    private var slashGroups: (skills: [SlashCommand], commands: [SlashCommand]) {
        SlashAutocompleteGroups.split(filteredSlashCommands)
    }

    private var slashFiltering: Bool {
        !(slashMatch?.query.isEmpty ?? true)
    }

    private var slashMenuEntries: [SlashMenuEntry] {
        SlashAutocompleteGroups.navigableEntries(
            skills: slashGroups.skills,
            commands: slashGroups.commands,
            skillsExpanded: slashSkillsExpanded,
            commandsExpanded: slashCommandsExpanded,
            filtering: slashFiltering
        )
    }

    private var showSlashPopover: Bool {
        !slashMenuEntries.isEmpty && inputFocused
    }

    private var mentionMatch: (query: String, range: Range<String.Index>)? {
        FileMentionMatch.match(in: input)
    }

    private var filteredMentions: [String] {
        guard let match = mentionMatch else { return [] }
        return FileMentionFilter.filter(fileMentionIndex, query: match.query, limit: 8)
    }

    private var showMentionPopover: Bool {
        mentionMatch != nil && !filteredMentions.isEmpty && inputFocused && !showSlashPopover
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if let authMsg = store.authRequiredMessage {
                AuthBanner(
                    message: authMsg,
                    onDismiss: { store.authRequiredMessage = nil },
                    onRetry: { Task { await store.retryConnection() } }
                )
            }

            if let error = store.lastError {
                ErrorBanner(message: error)
            }

            if let switchError = store.modelSwitchError {
                ModelSwitchBanner(
                    message: switchError,
                    canStartNewSession: store.modelSwitchNeedsNewSession,
                    onStartNewSession: {
                        store.modelSwitchError = nil
                        store.modelSwitchNeedsNewSession = false
                        Task { await store.startNewSession() }
                    },
                    onDismiss: {
                        store.modelSwitchError = nil
                        store.modelSwitchNeedsNewSession = false
                    }
                )
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if store.messages.isEmpty {
                            if store.currentWorkspace == nil {
                                noProjectState
                            } else if case .failed = store.connectionState {
                                EmptyView()
                            } else if store.isResumedSessionTab {
                                EmptyView()
                            } else {
                                welcomeState
                            }
                        }

                        ForEach(store.messages) { msg in
                            MessageBubble(
                                message: msg,
                                isStreaming: store.isStreaming && msg.id == store.streamingMessageID,
                                onRewind: { rewindTargetID = msg.id },
                                rewindDisabled: store.isStreaming
                            )
                            .id(msg.id)
                        }

                        if store.isGrokking {
                            GrokkingIndicator(startedAt: store.turnStartedAt)
                                .padding(.leading, 2)
                        }

                        if !store.thinkingText.isEmpty || store.thinkingDuration != nil {
                            ThinkingBlock(
                                text: store.thinkingText,
                                duration: store.thinkingDuration,
                                isExpanded: store.isThinkingExpanded,
                                isLive: store.isStreaming && store.thinkingDuration == nil
                            ) {
                                store.toggleThinkingExpanded()
                            }
                        }

                        if !store.liveToolCalls.isEmpty {
                            ToolActivityGroup(
                                tools: store.liveToolCalls,
                                isExpanded: toolActivityExpanded
                            ) {
                                toolActivityExpanded.toggle()
                            }
                        }

                        if !store.workflowRuns.isEmpty {
                            WorkflowRunsCard(
                                runs: store.workflowRuns,
                                isStreaming: store.isStreaming,
                                onPause: { id in Task { await store.pauseWorkflowRun(id) } },
                                onResume: { id in Task { await store.resumeWorkflowRun(id) } },
                                onStop: { id in Task { await store.stopWorkflowRun(id) } }
                            )
                        }

                        if let plan = store.pendingExitPlan {
                            PlanReviewCard(plan: plan) { verdict, comment in
                                store.respondToExitPlan(plan, verdict: verdict, comment: comment)
                            }
                        }

                        ForEach(store.pendingQuestions) { question in
                            QuestionCard(
                                request: question,
                                onSubmit: { answers in store.respondToQuestion(question, answers: answers) },
                                onSkip: { store.cancelQuestion(question) }
                            )
                        }

                        ForEach(store.pendingPermissions) { perm in
                            PermissionCard(permission: perm) { optionId in
                                store.respondToPermission(perm, with: optionId)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: store.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: store.isGrokking) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: store.thinkingText) { _, _ in
                    thinkingScrollTask?.cancel()
                    thinkingScrollTask = Task {
                        try? await Task.sleep(for: .milliseconds(200))
                        guard !Task.isCancelled else { return }
                        scrollToBottom(proxy: proxy)
                    }
                }
            }

            if let goal = store.goalState {
                GoalBanner(state: goal, store: store)
                    .padding(.horizontal, 12)
            }

            if let aside = store.btwAsideText {
                BtwAsideBanner(text: aside) {
                    store.clearBtwAside()
                }
                .padding(.horizontal, 12)
            }

            composer
        }
        .onAppear { inputFocused = true }
        .onDisappear {
            thinkingScrollTask?.cancel()
            thinkingScrollTask = nil
        }
        .confirmationDialog(
            "Rewind conversation?",
            isPresented: Binding(
                get: { rewindTargetID != nil },
                set: { if !$0 { rewindTargetID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Rewind", role: .destructive) {
                if let id = rewindTargetID {
                    _ = store.rewind(to: id)
                }
                rewindTargetID = nil
            }
            Button("Cancel", role: .cancel) {
                rewindTargetID = nil
            }
        } message: {
            Text("Messages after this point are removed from the transcript. This does not restore files on disk.")
        }
        .confirmationDialog(
            "Change reasoning effort?",
            isPresented: Binding(
                get: { pendingReasoningEffortChange != nil },
                set: { if !$0 { pendingReasoningEffortChange = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Summarize & Restart") {
                if let effort = pendingReasoningEffortChange {
                    Task {
                        await store.applyReasoningEffort(effort, strategy: .summarizeAndRestart)
                    }
                }
                pendingReasoningEffortChange = nil
            }
            Button("Restart", role: .destructive) {
                if let effort = pendingReasoningEffortChange {
                    Task {
                        await store.applyReasoningEffort(effort, strategy: .restart)
                    }
                }
                pendingReasoningEffortChange = nil
            }
            Button("Cancel", role: .cancel) {
                pendingReasoningEffortChange = nil
            }
        } message: {
            if let effort = pendingReasoningEffortChange {
                Text("Apply \(store.reasoningEffortDisplayName(effort)) when Grok restarts. Summarize & restart runs /compact first to preserve context.")
            }
        }
        .sheet(isPresented: $showMemoryBrowser) {
            MemoryBrowserPanel()
        }
        .sheet(isPresented: $showRememberPrompt) {
            rememberPromptSheet
        }
        .sheet(isPresented: $showSavedWorkflows) {
            SavedWorkflowsPanel(projectRoot: store.currentWorkspace?.path) { workflow, argsJSON in
                Task {
                    let args = Self.parseWorkflowArgsJSON(argsJSON)
                    _ = await store.launchSavedWorkflow(name: workflow.name, args: args)
                }
            }
        }
        .sheet(isPresented: $showDeepResearch) {
            DeepResearchSheet { query in
                Task { _ = await store.startDeepResearch(query) }
            }
        }
        .sheet(isPresented: $showSetGoal) {
            SetGoalSheet { objective, budget in
                Task { _ = await store.setGoal(objective, budget: budget) }
            }
        }
        .sheet(isPresented: $showCreateSkill) {
            createSkillSheet
        }
        .sheet(isPresented: $showImagine) {
            imagineSheet
        }
        .onAppear {
            workflowsEnabled = WorkflowsConfigStore.loadEnabled()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workflowsConfigChanged)) { _ in
            workflowsEnabled = WorkflowsConfigStore.loadEnabled()
        }
        .onChange(of: store.connectionState) { _, newState in
            if case .ready = newState {
                // Clear stale auth message if the CLI became ready again
                if store.authRequiredMessage != nil {
                    store.authRequiredMessage = nil
                }
            } else if case .failed(let msg) = newState,
                      (msg.lowercased().contains("login") || msg.lowercased().contains("auth")),
                      store.authRequiredMessage == nil {
                store.authRequiredMessage = msg
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(action: onNewSession) {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .disabled(store.currentWorkspace == nil)
            .help("New session")

            Button(action: onBrowseSessions) {
                Image(systemName: "clock")
            }
            .buttonStyle(.plain)
            .help("Browse sessions")

            Button(action: onOpenDashboard) {
                Image(systemName: "square.grid.2x2")
            }
            .buttonStyle(.plain)
            .help("Session dashboard")

            Menu {
                if store.isResumedSessionTab || store.grokSessionId != nil {
                    Button("Fork session") {
                        onForkSession()
                    }
                }
                if store.hasShareCommand {
                    Button("Share session") {
                        Task { _ = await store.shareSession() }
                    }
                    .disabled(store.isStreaming)
                }
                if store.hasGoalCommand {
                    Button("Set goal…") {
                        showSetGoal = true
                    }
                    .disabled(store.isStreaming)
                }
                if store.hasCreateSkillCommand {
                    Button("Create skill…") {
                        createSkillName = ""
                        showCreateSkill = true
                    }
                    .disabled(store.isStreaming)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .disabled(store.currentWorkspace == nil)
            .help("Session actions")

            Spacer()

            Menu {
                openInButton(title: "Finder", target: .finder, appURL: finderURL, fallbackSystemImage: "finder")
                if let app = installedApp(bundleIdentifiers: ["com.todesktop.230313mzl4w4u92", "com.cursor.Cursor"], appNames: ["Cursor"]) {
                    openInButton(title: "Cursor", target: .cursor, appURL: app, fallbackSystemImage: "cursorarrow")
                }
                if let app = installedApp(bundleIdentifiers: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"], appNames: ["Visual Studio Code", "Visual Studio Code - Insiders"]) {
                    openInButton(title: "VS Code", target: .vsCode, appURL: app, fallbackSystemImage: "chevron.left.forwardslash.chevron.right")
                }
                Divider()
                if let app = installedApp(bundleIdentifiers: ["com.apple.Terminal"], appNames: ["Terminal"]) {
                    openInButton(title: "Terminal", target: .terminal, appURL: app, fallbackSystemImage: "terminal")
                }
                if let app = installedApp(bundleIdentifiers: ["com.googlecode.iterm2"], appNames: ["iTerm", "iTerm2"]) {
                    openInButton(title: "iTerm", target: .iTerm, appURL: app, fallbackSystemImage: "terminal.fill")
                }
                if let app = installedApp(bundleIdentifiers: ["dev.zed.Zed", "dev.zed.Zed-Preview", "com.zed.Zed"], appNames: ["Zed", "Zed Preview"]) {
                    Divider()
                    openInButton(title: "Zed", target: .zed, appURL: app, fallbackSystemImage: "square.and.pencil")
                }
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .menuStyle(.borderlessButton)
            .disabled(store.currentWorkspace == nil)
            .help("Open project in")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var finderURL: URL {
        URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    }

    private func openInButton(
        title: String,
        target: ProjectOpenTarget,
        appURL: URL,
        fallbackSystemImage: String
    ) -> some View {
        Button {
            onOpenProjectIn(target)
        } label: {
            Label {
                Text(title)
            } icon: {
                appIcon(for: appURL, fallbackSystemImage: fallbackSystemImage)
            }
        }
    }

    private func appIcon(for appURL: URL, fallbackSystemImage: String) -> Image {
        if FileManager.default.fileExists(atPath: appURL.path) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 16, height: 16)
            return Image(nsImage: icon)
        }
        return Image(systemName: fallbackSystemImage)
    }

    private func installedApp(bundleIdentifiers: [String], appNames: [String]) -> URL? {
        for bundleIdentifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return url
            }
        }

        for appName in appNames {
            for directory in ["/Applications", "\(NSHomeDirectory())/Applications"] {
                let candidate = URL(fileURLWithPath: directory).appendingPathComponent("\(appName).app")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }

    private var brandMark: some View {
        Group {
            if let icon = GrokBrandIcon.mark() {
                Image(nsImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var welcomeState: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                brandMark
                Text("How can I help?")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionStatusColor)
                        .frame(width: 6, height: 6)
                    Text(connectionSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                ForEach(QuickStartPrompt.defaults) { item in
                    QuickStartChip(item: item) {
                        input = item.prompt
                        inputFocused = true
                    }
                }
            }

            Text("⏎ send · ⇧⏎ new line · / for skills")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
        .padding(.horizontal, 24)
    }

    private var noProjectState: some View {
        VStack(spacing: 18) {
            brandMark
            VStack(spacing: 6) {
                Text("Welcome to GrokBuild")
                    .font(.title2.weight(.semibold))
                Text("Add a project folder to start a Grok session — then plan, build, and explore your code together.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onAddProject) {
                Label("Add Project", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Choose a folder to work in")
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .padding(.horizontal, 24)
    }

    private var connectionStatusColor: Color {
        switch store.connectionState {
        case .starting: return .yellow
        case .ready, .busy: return .green
        case .failed: return .red
        case .idle: return store.currentWorkspace == nil ? .secondary : .green
        }
    }

    private var connectionSubtitle: String {
        switch store.connectionState {
        case .starting: return "Starting…"
        case .ready: return "Connected"
        case .busy: return "Working…"
        case .failed: return "Connection error"
        case .idle: return store.currentWorkspace == nil ? "Idle" : "Ready"
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = store.messages.last {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    /// Skill + research + imagine chips in curated order, shown as one horizontal bar.
    private var composerChips: [SlashCommand] {
        SkillSlashCommands.filter(store.availableSlashCommands)
            + ResearchSlashCommands.filter(store.availableSlashCommands)
            + ImagineSlashCommands.filter(store.availableSlashCommands)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.fileAttachments.isEmpty {
                FileChipBar(
                    attachments: store.fileAttachments,
                    onToggleHidden: { store.toggleFileAttachmentHidden(id: $0) },
                    onRemove: { store.removeFileAttachment(id: $0) }
                )
            }

            if !store.imageAttachments.isEmpty {
                ImageChipBar(
                    attachments: store.imageAttachments,
                    onRemove: { store.removeImageAttachment(id: $0) }
                )
            }

            if !composerChips.isEmpty {
                WorkflowChipBar(
                    commands: composerChips,
                    isDisabled: store.isStreaming || store.currentWorkspace == nil
                ) { command in
                    Task { await handleComposerChip(command) }
                }
            }

            if !store.promptQueue.isEmpty {
                promptQueueBar
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    if showMentionPopover {
                        FileMentionListView(
                            paths: filteredMentions,
                            activeIndex: mentionActiveIndex,
                            onSelect: pickMention
                        )
                    }

                    if showSlashPopover {
                        SlashAutocompleteView(
                            entries: slashMenuEntries,
                            activeIndex: slashActiveIndex,
                            onSelect: pickSlashCommand,
                            onShowMoreSkills: {
                                slashSkillsExpanded = true
                                clampSlashActiveIndex()
                            },
                            onShowMoreCommands: {
                                slashCommandsExpanded = true
                                clampSlashActiveIndex()
                            }
                        )
                    }

                    TextField("Plan, Build, / for skills", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .lineLimit(2, reservesSpace: true)
                    .submitLabel(.send)
                    .onSubmit {
                        if showMentionPopover {
                            activateMention(at: mentionActiveIndex)
                        } else if showSlashPopover {
                            activateSlashEntry(at: slashActiveIndex)
                        } else {
                            Task { await submit() }
                        }
                    }
                    .onChange(of: input) { _, _ in
                        slashActiveIndex = 0
                        slashSkillsExpanded = false
                        slashCommandsExpanded = false
                        mentionActiveIndex = 0
                    }
                    .onKeyPress { press in
                        if press.key == .tab, showMentionPopover, !filteredMentions.isEmpty {
                            activateMention(at: mentionActiveIndex)
                            return .handled
                        }
                        if press.key == .tab, showSlashPopover, !slashMenuEntries.isEmpty {
                            activateSlashEntry(at: slashActiveIndex)
                            return .handled
                        }
                        if press.key == .return && !press.modifiers.contains(.shift) {
                            if showMentionPopover {
                                activateMention(at: mentionActiveIndex)
                            } else if showSlashPopover {
                                activateSlashEntry(at: slashActiveIndex)
                            } else {
                                Task { await submit() }
                            }
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.upArrow) {
                        if showMentionPopover, !filteredMentions.isEmpty {
                            moveMentionSelection(by: -1)
                            return .handled
                        }
                        if showSlashPopover, !slashMenuEntries.isEmpty {
                            moveSlashSelection(by: -1)
                            return .handled
                        }
                        if let prev = store.previousHistory(from: input) {
                            input = prev
                        }
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        if showMentionPopover, !filteredMentions.isEmpty {
                            moveMentionSelection(by: 1)
                            return .handled
                        }
                        if showSlashPopover, !slashMenuEntries.isEmpty {
                            moveSlashSelection(by: 1)
                            return .handled
                        }
                        if let next = store.nextHistory(from: input) {
                            input = next
                        }
                        return .handled
                    }
                }

                HStack(spacing: 6) {
                modeSelector
                modelSelector

                ContextUsageIndicator(
                    label: store.currentModelContextLabel,
                    fraction: store.contextUsageFraction,
                    usedTokens: store.usedContextTokens,
                    limitTokens: store.currentModelContextLimit,
                    canCompact: store.currentWorkspace != nil && !store.isStreaming,
                    onCompact: { Task { await store.compactContext() } }
                )
                .help("Context usage — click for details and Compact")

                Spacer()

                reviewControls

                MicButton(voice: voiceInput, input: $input)

                Button {
                    chooseFiles()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Attach files")

                sessionActionButton
            }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: MainWindowLayout.composerMaxWidth, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isFileDropTargeted ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isFileDropTargeted ? 1.5 : 1)
            }
            .onDrop(of: [UTType.fileURL.identifier, UTType.image.identifier], isTargeted: $isFileDropTargeted) { providers in
                handleFileDrop(providers)
            }
            .onPasteCommand(of: [UTType.image]) { providers in
                handleImagePaste(providers)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            projectStatusRow
        }
        .padding(12)
        .background(.bar)
        .task(id: store.currentWorkspace?.id) {
            loadFileMentionIndex()
        }
    }

    private var projectStatusRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if let project = store.currentWorkspace {
                    Label(PrivacyMode.redactLabel(project.displayName, placeholder: "Project", enabled: privacyMode), systemImage: "folder")
                        .lineLimit(1)
                    Button(action: onSwitchBranch) {
                        Label(currentBranchLabel(for: project.path), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    }
                    .buttonStyle(.plain)
                    .help("Branches & worktrees")
                    agentStatusPill
                    browserStatusPill
                    computerUseStatusPill
                    if showWorkflowsPill {
                        workflowsStatusPill
                    }
                    tasksStatusPill
                    if memoryEnabled {
                        memoryStatusPill
                    }
                } else {
                    Label("No project selected", systemImage: "folder")
                }
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .task(id: store.currentWorkspace?.id) {
            await store.loadDiscoveredAgentsIfNeeded()
            cachedCustomSubagentNames = SubagentRoleStore.load().map(\.name)
        }
        .onReceive(NotificationCenter.default.publisher(for: .subagentRolesChanged)) { _ in
            cachedCustomSubagentNames = SubagentRoleStore.load().map(\.name)
        }
    }

    private var agentStatusPill: some View {
        let effective = store.effectiveAgentSelection
        let title = store.effectiveAgentDisplayName
        let overriding = store.hasExplicitAgent
        let tint: Color = overriding ? .teal : .secondary

        return Menu {
            Section("This session's agent") {
                ForEach(GrokAgentProfiles.builtInOptions) { option in
                    Button {
                        Task { await store.setSessionAgent(option.id) }
                    } label: {
                        Label(option.title, systemImage: effective == option.id ? "checkmark" : "person")
                    }
                }
            }

            let discovered = store.discoveredAgents.map(\.name)
                .filter { name in !GrokAgentProfiles.builtInOptions.contains { $0.id == name } }
            if !discovered.isEmpty {
                Section("Discovered") {
                    ForEach(discovered, id: \.self) { name in
                        Button {
                            Task { await store.setSessionAgent(name) }
                        } label: {
                            Label(name, systemImage: effective == name ? "checkmark" : "person.crop.square")
                        }
                    }
                }
            }

            let excluded = Set(GrokAgentProfiles.builtInOptions.map(\.id) + store.discoveredAgents.map(\.name))
            let customSubagents = cachedCustomSubagentNames.filter { !excluded.contains($0) }
            if !customSubagents.isEmpty {
                Section("Run as custom role") {
                    ForEach(customSubagents, id: \.self) { name in
                        Button {
                            Task { await store.setSessionAgent(name) }
                        } label: {
                            Label(name, systemImage: effective == name ? "checkmark" : "person.2")
                        }
                    }
                }
            }

            Divider()

            Button {
                onOpenAgentSettings()
            } label: {
                Label("Open Agent Settings", systemImage: "gearshape")
            }
        } label: {
            Label(title, systemImage: "person.2.badge.gearshape")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(tint.opacity(overriding ? 0.14 : 0.10)))
                .foregroundStyle(tint)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(store.currentWorkspace == nil)
        .help(overriding
            ? "Session agent (overrides the default). Changing it restarts this session's grok."
            : "Session agent (follows the Settings default). Changing it restarts this session's grok.")
    }

    private var showWorkflowsPill: Bool {
        workflowsEnabled
            || !store.workflowRuns.isEmpty
            || store.hasWorkflowCommand
            || store.hasDeepResearchCommand
    }

    private var workflowsStatusPill: some View {
        let runs = store.workflowRuns
        let count = runs.count
        let tint: Color = count > 0 ? .indigo : .secondary
        let title = count > 0 ? "Workflows (\(count))" : "Workflows"

        return Menu {
            if runs.isEmpty {
                Button("No workflow runs") {}
                    .disabled(true)
            } else {
                Section("Runs") {
                    ForEach(runs) { run in
                        Menu(workflowMenuTitle(run)) {
                            if !run.phase.isEmpty {
                                Text("Phase: \(run.phase)")
                            }
                            if !run.progress.isEmpty {
                                Text(run.progress)
                            }
                            Text("Status: \(run.status)")
                            Divider()
                            if run.status.lowercased() != "paused" {
                                Button {
                                    Task { await store.pauseWorkflowRun(run.id) }
                                } label: {
                                    Label("Pause", systemImage: "pause.fill")
                                }
                            }
                            if run.status.lowercased() == "paused" {
                                Button {
                                    Task { await store.resumeWorkflowRun(run.id) }
                                } label: {
                                    Label("Resume", systemImage: "play.fill")
                                }
                            }
                            Button(role: .destructive) {
                                Task { await store.stopWorkflowRun(run.id) }
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                Task { await store.refreshWorkflowRuns() }
            } label: {
                Label("Refresh Runs", systemImage: "arrow.clockwise")
            }
            .disabled(store.isStreaming)

            Button {
                showSavedWorkflows = true
            } label: {
                Label("Saved Workflows…", systemImage: "doc.text")
            }

            if store.hasDeepResearchCommand {
                Button {
                    showDeepResearch = true
                } label: {
                    Label("Deep Research…", systemImage: "magnifyingglass")
                }
                .disabled(store.isStreaming)
            }

            Button {
                onOpenWorkflowSettings()
            } label: {
                Label("Open Workflow Settings", systemImage: "gearshape")
            }
        } label: {
            Label(title, systemImage: count > 0 ? "arrow.triangle.branch" : "arrow.triangle.branch")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(tint.opacity(count > 0 ? 0.14 : 0.10)))
                .foregroundStyle(tint)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(store.currentWorkspace == nil)
        .help("Background workflow runs for this session. Pause/stop via /workflow; saved scripts live in .grok/workflows.")
        .accessibilityLabel(title)
    }

    private func workflowMenuTitle(_ run: WorkflowRun) -> String {
        let status = run.status.isEmpty ? "run" : run.status
        let label = run.name.isEmpty ? run.id : run.name
        let short = label.count > 28 ? String(label.prefix(28)) + "…" : label
        return "\(short) · \(status)"
    }

    private static func parseWorkflowArgsJSON(_ text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private var tasksStatusPill: some View {
        let activities = store.backgroundActivities
        let scheduled = activities.filter { $0.kind == .scheduled }
        let background = activities.filter { $0.kind == .backgroundCommand }
        let monitors = activities.filter { $0.kind == .monitor }
        let subagents = activities.filter { $0.kind == .subagent }
        let count = activities.count
        let available = store.hasLoopCommand
        let tint: Color = count > 0 ? .accentColor : .secondary
        let title = count > 0 ? "Tasks (\(count))" : "Tasks"

        return Menu {
            if activities.isEmpty {
                Button("No background tasks") {}
                    .disabled(true)
            } else {
                if !scheduled.isEmpty {
                    Section("Scheduled") {
                        ForEach(scheduled) { activity in
                            backgroundActivityMenu(activity)
                        }
                    }
                }
                if !background.isEmpty {
                    Section("Background commands") {
                        ForEach(background) { activity in
                            backgroundActivityMenu(activity)
                        }
                    }
                }
                if !monitors.isEmpty {
                    Section("Monitors") {
                        ForEach(monitors) { activity in
                            backgroundActivityMenu(activity)
                        }
                    }
                }
                if !subagents.isEmpty {
                    Section("Subagents") {
                        ForEach(subagents) { activity in
                            backgroundActivityMenu(activity)
                        }
                    }
                }
            }

            Divider()

            Button {
                Task { await store.refreshScheduledTasks() }
            } label: {
                Label("Refresh Tasks", systemImage: "arrow.clockwise")
            }
            .disabled(store.isStreaming)

            Button("Type /loop <interval> <prompt> to schedule") {}
                .disabled(true)
        } label: {
            Label(title, systemImage: count > 0 ? "clock.badge.checkmark" : "clock")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(tint.opacity(count > 0 ? 0.14 : 0.10)))
                .foregroundStyle(tint)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(store.currentWorkspace == nil)
        .help(available
            ? "Background tasks observed in this session (scheduled, shells, monitors, subagents)."
            : "Background tasks mirror — refresh to query grok.")
    }

    @ViewBuilder
    private func backgroundActivityMenu(_ activity: BackgroundActivity) -> some View {
        if activity.kind == .scheduled, let task = activity.scheduledTask {
            Menu(taskMenuTitle(task)) {
                Text(task.prompt.isEmpty ? "(no prompt)" : task.prompt)
                if let next = task.nextFireAt {
                    Text("Next: \(next.formatted(date: .abbreviated, time: .shortened))")
                }
                Divider()
                Button(role: .destructive) {
                    Task { await store.cancelScheduledTask(task.id) }
                } label: {
                    Label("Cancel Task", systemImage: "trash")
                }
            }
        } else {
            Menu(backgroundActivityTitle(activity)) {
                if !activity.detail.isEmpty {
                    Text(activity.detail)
                }
                if !activity.status.isEmpty {
                    Text("Status: \(activity.status)")
                }
            }
        }
    }

    private func backgroundActivityTitle(_ activity: BackgroundActivity) -> String {
        let label = activity.title
        let short = label.count > 32 ? String(label.prefix(32)) + "…" : label
        return activity.status.isEmpty ? short : "\(short) · \(activity.status)"
    }

    private var promptQueueBar: some View {
        HStack(spacing: 8) {
            Label("Queue (\(store.promptQueue.count))", systemImage: "tray.full")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Menu {
                ForEach(Array(store.promptQueue.enumerated()), id: \.offset) { index, prompt in
                    Menu(prompt.count > 40 ? String(prompt.prefix(40)) + "…" : prompt) {
                        if store.isStreaming {
                            Button("Steer into current turn") {
                                _ = store.steerQueuedPromptNow(at: index)
                            }
                        }
                        Button("Send now") {
                            Task { _ = await store.sendQueuedPromptNow(at: index) }
                        }
                        Button("Remove", role: .destructive) {
                            store.removeQueuedPrompt(at: index)
                        }
                    }
                }
            } label: {
                Text("Queued prompts")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var createSkillSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Skill")
                .font(.headline)
            TextField("Skill name", text: $createSkillName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showCreateSkill = false }
                Button("Create") {
                    let name = createSkillName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    showCreateSkill = false
                    Task { _ = await store.send("/create-skill \(name)") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(createSkillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var imagineSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Imagine")
                .font(.headline)
            TextField("Describe the image or video…", text: $imaginePrompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
            HStack {
                Spacer()
                Button("Cancel") { showImagine = false }
                Button("Send /imagine") {
                    let prompt = imaginePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !prompt.isEmpty else { return }
                    showImagine = false
                    Task { _ = await store.send("/imagine \(prompt)") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(imaginePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func taskMenuTitle(_ task: ScheduledTask) -> String {
        let interval = task.intervalHuman.isEmpty ? "task" : task.intervalHuman
        let prompt = task.prompt.isEmpty ? task.id : task.prompt
        let shortPrompt = prompt.count > 32 ? String(prompt.prefix(32)) + "…" : prompt
        return "\(interval): \(shortPrompt)"
    }

    // Only shown while cross-session memory is enabled (see `projectStatusRow`); the pill label
    // is just "Memory" — an off state isn't surfaced because the pill is hidden when disabled.
    private var memoryStatusPill: some View {
        Menu {
            Button {
                showMemoryBrowser = true
            } label: {
                Label("Browse Memory Files…", systemImage: "folder")
            }

            Button {
                memoryNoteText = ""
                showRememberPrompt = true
            } label: {
                Label("Remember…", systemImage: "text.badge.plus")
            }

            Divider()

            Button {
                onOpenMemorySettings()
            } label: {
                Label("Open Memory Settings", systemImage: "gearshape")
            }
        } label: {
            Label("Memory", systemImage: "brain.head.profile")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.pink.opacity(0.14)))
                .foregroundStyle(Color.pink)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(store.currentWorkspace == nil)
        .help("Cross-session memory is on. Browse files, save a note, or open Memory settings.")
    }

    private var rememberPromptSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remember a Note")
                .font(.headline)
            Text("Saved to your global memory so Grok can recall it in future sessions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $memoryNoteText)
                .font(.body)
                .frame(minWidth: 380, minHeight: 120)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
            HStack {
                Spacer()
                Button("Cancel") { showRememberPrompt = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    _ = store.remember(memoryNoteText)
                    showRememberPrompt = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(memoryNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var browserStatusPill: some View {
        let settings = BrowserSettingsStore.load()
        let configurationIssue = AgentBrowserService.browserToolsConfigurationIssue(settings: settings)
        let browserBaseReady = AgentBrowserService.bridgeScriptURL() != nil
            && AgentBrowserService.executableURL() != nil
        let managedRuntimeReady = AgentBrowserService.browserRuntimeConfigurationIssue(settings: settings, mode: .managed) == nil
        let externalRuntimeReady = AgentBrowserService.browserRuntimeConfigurationIssue(settings: settings, mode: .external) == nil
        let canChooseRuntime = browserBaseReady && (managedRuntimeReady || externalRuntimeReady)
        let isConfigured = configurationIssue == nil
        let needsSetup = browserToolsEnabled && !isConfigured
        let title = needsSetup ? "Browser Setup Needed" : "Browser Tools"
        let icon = browserToolsEnabled && isConfigured ? "globe.badge.chevron.backward" : "globe"
        // Enabled → white (primary); disabled → greyed out; needs-setup keeps the orange warning.
        let tint: Color = needsSetup ? .orange : (browserToolsEnabled ? .primary : .secondary)

        return Menu {
            if browserToolsEnabled || isConfigured {
                Button(browserToolsEnabled ? "Turn Browser Tools Off" : "Turn Browser Tools On") {
                    onToggleBrowserTools()
                }
            }

            if canChooseRuntime {
                Divider()

                Button {
                    onSelectBrowserRuntime(.managed)
                } label: {
                    Label("Managed Browser Runtime", systemImage: settings.runtimeMode == .managed ? "checkmark" : "shippingbox")
                }

                Button {
                    onSelectBrowserRuntime(.external)
                } label: {
                    Label("Existing Chromium Browser", systemImage: settings.runtimeMode == .external ? "checkmark" : "globe")
                }
            }

            if let configurationIssue {
                Button(configurationIssue) {}
                    .disabled(true)
            }

            Divider()

            Button {
                onOpenBrowserSettings()
            } label: {
                Label("Open Browser Settings", systemImage: "gearshape")
            }
        } label: {
            Group {
                if needsSetup {
                    Label(title, systemImage: icon)
                } else {
                    Image(systemName: icon)
                        .accessibilityLabel(title)
                }
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, needsSetup ? 8 : 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(browserToolsEnabled ? tint.opacity(0.14) : Color.secondary.opacity(0.10)))
            .foregroundStyle(tint)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(browserStatusHelp(isConfigured: isConfigured, issue: configurationIssue))
    }

    private func browserStatusHelp(isConfigured: Bool, issue: String?) -> String {
        if !isConfigured {
            return issue ?? "Finish browser setup in Settings before using the quick toggle."
        }
        return browserToolsEnabled
            ? "Disable browser MCP tools and restart the Grok connection."
            : "Enable browser MCP tools and restart the Grok connection."
    }

    private var computerUseStatusPill: some View {
        let settings = ComputerUseSettingsStore.load()
        let configurationIssue = ComputerUseService.configurationIssue(settings: settings)
        let isConfigured = configurationIssue == nil
        let needsSetup = computerUseEnabled && !isConfigured
        let title = needsSetup ? "Computer Use Setup Needed" : "Computer Use"
        let icon = computerUseEnabled && isConfigured ? "desktopcomputer.badge.checkmark" : "desktopcomputer"
        // Enabled → white (primary); disabled → greyed out; needs-setup keeps the orange warning.
        let tint: Color = needsSetup ? .orange : (computerUseEnabled ? .primary : .secondary)

        return Menu {
            if computerUseEnabled || isConfigured {
                Button(computerUseEnabled ? "Turn Computer Use Off" : "Turn Computer Use On") {
                    onToggleComputerUse()
                }
            }

            if let configurationIssue {
                Button(configurationIssue) {}
                    .disabled(true)
            } else if !computerUseEnabled {
                Button("Requires Accessibility permission") {}
                    .disabled(true)
            }

            Divider()

            Button {
                onOpenComputerUseSettings()
            } label: {
                Label("Open Computer Use Settings", systemImage: "gearshape")
            }
        } label: {
            Group {
                if needsSetup {
                    Label(title, systemImage: icon)
                } else {
                    Image(systemName: icon)
                        .accessibilityLabel(title)
                }
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, needsSetup ? 8 : 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(computerUseEnabled ? tint.opacity(0.14) : Color.secondary.opacity(0.10)))
            .foregroundStyle(tint)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(computerUseStatusHelp(isConfigured: isConfigured, issue: configurationIssue))
    }

    private func computerUseStatusHelp(isConfigured: Bool, issue: String?) -> String {
        if !isConfigured {
            return issue ?? "Finish Computer Use setup in Settings before using the quick toggle."
        }
        return computerUseEnabled
            ? "Disable Computer Use MCP tools and restart the Grok connection."
            : "Enable Computer Use MCP tools if Accessibility permission is ready."
    }

    @ViewBuilder
    private var sessionActionButton: some View {
        if store.isStreaming {
            Button {
                store.stop()
            } label: {
                ZStack {
                    ProgressView()
                        .controlSize(.small)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 7, weight: .bold))
                }
                .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Stop session (⌘.)")
            .keyboardShortcut(".", modifiers: .command)
        } else {
            Button {
                Task { await submit() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.hasSendableAttachments ||
                      store.currentWorkspace == nil ||
                      store.authRequiredMessage != nil)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    @ViewBuilder
    private var reviewControls: some View {
        if reviewFileCount > 0 {
            Button {
                onToggleReview()
            } label: {
                Label(
                    "\(reviewFileCount) Changed \(reviewFileCount == 1 ? "File" : "Files")",
                    systemImage: "doc.on.doc"
                )
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isReviewVisible ? .accentColor : .secondary)
            .help(isReviewVisible ? "Hide changed files" : "Show changed files")
        }
    }

    private var modeSelector: some View {
        Menu {
            ForEach(store.availableModes, id: \.rawValue) { mode in
                Button {
                    store.setMode(mode)
                } label: {
                    modeMenuRow(
                        icon: iconName(for: mode),
                        title: displayName(for: mode),
                        isSelected: store.currentMode == mode
                    )
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: iconName(for: store.currentMode))
                    .font(.caption.weight(.semibold))
                    .frame(width: 14)
                Text(displayName(for: store.currentMode))
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Change agent mode")
    }

    private func modeMenuRow(icon: String, title: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16, alignment: .center)
            Text(title)
            Spacer(minLength: 16)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
            }
        }
    }

    private func displayName(for mode: AgentMode) -> String {
        switch mode.rawValue {
        case "plan": return "Plan"
        case "yolo": return "YOLO"
        default: return "Agent"
        }
    }

    private func iconName(for mode: AgentMode) -> String {
        switch mode.rawValue {
        case "plan": return "list.bullet.indent"
        case "yolo": return "bolt.fill"
        default: return "infinity"
        }
    }

    private var modelSelector: some View {
        Button {
            isModelSelectorOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(modelSelectorLabel)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isModelSelectorOpen, arrowEdge: .bottom) {
            modelSelectorPopoverContent
        }
        .accessibilityLabel("Model and reasoning effort")
        .accessibilityValue(modelSelectorLabel)
        .accessibilityIdentifier("grok-model-effort-selector")
        .help(modelSelectorHelp)
    }

    private var modelSelectorPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Model")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(store.availableModels, id: \.self) { modelId in
                Button {
                    store.setModel(modelId)
                    isModelSelectorOpen = false
                } label: {
                    modelMenuRow(
                        title: store.modelDisplayName(modelId),
                        subtitle: store.modelCapabilityHint(for: modelId),
                        isSelected: store.currentModel == modelId
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .accessibilityIdentifier("grok-model-option-\(modelId)")
            }

            if store.currentModelSupportsReasoningEffort {
                Divider()
                    .padding(.vertical, 6)

                Text("Reasoning effort")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)

                Text("Saved for this project. Set the default for new projects in Settings → Permissions.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                ForEach(ReasoningEffortLevel.menuCases) { level in
                    Button {
                        requestReasoningEffortChange(to: level.rawValue)
                        isModelSelectorOpen = false
                    } label: {
                        modelMenuRow(
                            title: level.displayName,
                            subtitle: nil,
                            isSelected: store.currentReasoningEffort == level.rawValue
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .disabled(store.isStreaming || store.currentWorkspace == nil)
                    .accessibilityIdentifier("grok-effort-option-\(level.rawValue)")
                }
            } else if store.isCurrentModelCustom {
                Divider()
                    .padding(.vertical, 6)

                Text("Reasoning effort is off for this custom model. Enable it in Settings → Models if the provider supports it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
        .frame(minWidth: 240)
        .padding(.bottom, 8)
    }

    private var modelSelectorLabel: String {
        store.modelDisplayName(store.currentModel)
    }

    private var modelSelectorHelp: String {
        if store.isStreaming {
            return "Select model; wait for the current turn to finish before changing reasoning effort"
        }
        if !store.currentModelSupportsReasoningEffort {
            return "Model selector; reasoning effort is off for this custom model"
        }
        return "Model and reasoning effort"
    }

    private func modelMenuRow(title: String, subtitle: String?, isSelected: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
            }
        }
    }

    private func requestReasoningEffortChange(to effort: String) {
        guard store.currentModelSupportsReasoningEffort else { return }
        guard effort != store.currentReasoningEffort else { return }
        guard store.currentWorkspace != nil, !store.isStreaming else { return }
        if store.needsReasoningEffortConfirmation(for: effort) {
            pendingReasoningEffortChange = effort
        } else {
            Task { await store.applyReasoningEffort(effort, strategy: .restart) }
        }
    }

    private func handleComposerChip(_ command: SlashCommand) async {
        switch command.name {
        case "imagine", "imagine-video":
            showImagine = true
        case "deep-research":
            showDeepResearch = true
        default:
            _ = await store.send("/\(command.name)")
            inputFocused = true
        }
    }

    private func submit() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        _ = await store.send(text)
        inputFocused = true
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url = fileURL(from: item)
                    guard let url else { return }
                    Task { @MainActor in
                        appendDroppedFile(url)
                    }
                }
            } else {
                loadPastedImage(from: provider)
            }
        }
        return true
    }

    private func handleImagePaste(_ providers: [NSItemProvider]) {
        for provider in providers {
            loadPastedImage(from: provider)
        }
    }

    /// Loads raw image bytes from a pasteboard/drag provider and attaches them as vision content.
    private func loadPastedImage(from provider: NSItemProvider) {
        let candidates: [(UTType, String)] = [
            (.png, "image/png"),
            (.jpeg, "image/jpeg"),
            (.gif, "image/gif"),
        ]
        for (type, mime) in candidates where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                guard let data, !data.isEmpty else { return }
                Task { @MainActor in
                    store.addImageAttachment(data: data, mimeType: mime, displayName: "Pasted image")
                    inputFocused = true
                }
            }
            return
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Attach"
        if panel.runModal() == .OK {
            for url in panel.urls {
                appendDroppedFile(url)
            }
        }
    }

    private func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }

    @MainActor
    private func appendDroppedFile(_ url: URL) {
        if ImageAttachmentSupport.isImagePath(url.path) {
            store.addImageAttachment(path: url.path)
        } else {
            store.addFileAttachment(path: url.path)
        }
        inputFocused = true
    }

    private func pickSlashCommand(_ command: SlashCommand) {
        guard let match = slashMatch else { return }
        input = SlashAutocomplete.apply(command: command, to: input, matchRange: match.range)
        inputFocused = true
    }

    private func pickMention(_ path: String) {
        guard let match = mentionMatch else { return }
        input = FileMentionMatch.apply(path: path, to: input, matchRange: match.range)
        mentionActiveIndex = 0
        inputFocused = true
    }

    private func moveMentionSelection(by delta: Int) {
        let count = filteredMentions.count
        guard count > 0 else { return }
        mentionActiveIndex = (mentionActiveIndex + delta + count) % count
    }

    private func activateMention(at index: Int) {
        guard filteredMentions.indices.contains(index) else { return }
        pickMention(filteredMentions[index])
    }

    private func loadFileMentionIndex() {
        guard let root = store.currentWorkspace?.path else {
            fileMentionIndex = []
            return
        }
        Task.detached(priority: .utility) {
            let files = FileMentionIndex.enumerate(root: root)
            await MainActor.run { fileMentionIndex = files }
        }
    }

    private func moveSlashSelection(by delta: Int) {
        let count = slashMenuEntries.count
        guard count > 0 else { return }
        slashActiveIndex = (slashActiveIndex + delta + count) % count
    }

    private func activateSlashEntry(at index: Int) {
        guard slashMenuEntries.indices.contains(index) else { return }
        switch slashMenuEntries[index] {
        case .command(let command):
            pickSlashCommand(command)
        case .showMoreSkills:
            slashSkillsExpanded = true
            clampSlashActiveIndex()
        case .showMoreCommands:
            slashCommandsExpanded = true
            clampSlashActiveIndex()
        }
    }

    private func clampSlashActiveIndex() {
        let count = slashMenuEntries.count
        guard count > 0 else {
            slashActiveIndex = 0
            return
        }
        slashActiveIndex = min(slashActiveIndex, count - 1)
    }

    private func currentBranchLabel(for projectURL: URL) -> String {
        GitService.currentBranch(in: projectURL) ?? "No branch"
    }
}

// MARK: - Quick Start

private struct QuickStartChip: View {
    let item: QuickStartPrompt
    var onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.callout)
                    .foregroundStyle(.tint)
                    .frame(width: 20)
                Text(item.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.primary.opacity(isHovered ? 0.09 : 0.05),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(isHovered ? 0.16 : 0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(item.prompt)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Context Usage

private struct ContextUsageIndicator: View {
    let label: String
    let fraction: Double
    var usedTokens: Int? = nil
    var limitTokens: Int? = nil
    var canCompact: Bool = false
    var onCompact: () -> Void = {}

    @State private var isPopoverOpen = false

    private var ringColor: Color {
        switch fraction {
        case 0.85...: return .red
        case 0.65...: return .orange
        default: return .green
        }
    }

    var body: some View {
        Button {
            isPopoverOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.15), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(0.04, fraction))
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 14, height: 14)

                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPopoverOpen, arrowEdge: .top) {
            popoverContent
        }
        .accessibilityLabel("Context usage")
        .accessibilityValue(label)
        .accessibilityIdentifier("grok-context-usage")
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context Usage")
                .font(.subheadline.weight(.semibold))

            Text(ContextUsageFormatter.summary(used: usedTokens, limit: limitTokens))
                .font(.callout)
                .monospacedDigit()

            if let percent = ContextUsageFormatter.percent(used: usedTokens, limit: limitTokens) {
                ProgressView(value: Double(percent), total: 100)
                    .tint(ringColor)
                Text("\(percent)% of the model's context window used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Billed cost (USD) isn't reported over the grok agent connection, so only token usage is shown.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button {
                onCompact()
                isPopoverOpen = false
            } label: {
                Label("Compact context", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!canCompact)
            .help("Run /compact to summarize the conversation and free context")
        }
        .padding(14)
        .frame(width: 300)
    }
}

// MARK: - Auth Banner

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

private struct ModelSwitchBanner: View {
    let message: String
    var canStartNewSession: Bool = false
    var onStartNewSession: () -> Void = {}
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
            if canStartNewSession {
                Button("Start New Session", action: onStartNewSession)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

struct AuthBanner: View {
    let message: String
    var onDismiss: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                Text("Authentication Required")
                    .font(.headline)
            }

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    openTerminalForLogin()
                } label: {
                    Label("Open Terminal & Run `grok login`", systemImage: "terminal")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    copyLoginCommand()
                } label: {
                    Label("Copy Command", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                if let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func openTerminalForLogin() {
        // Use AppleScript to open Terminal and run the login command
        let script = """
        tell application "Terminal"
            activate
            do script "grok login"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error != nil {
                // Fallback: just open Terminal
                openTerminalApp()
            }
        } else {
            openTerminalApp()
        }
    }

    private func openTerminalApp() {
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(terminalURL)
    }

    private func copyLoginCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("grok login", forType: .string)
    }
}

// MARK: - Permission Card with Diff Preview

struct PermissionCard: View {
    let permission: PermissionRequest
    let onRespond: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: permission.toolCall.isEdit ? "doc.text" : "terminal")
                Text(permission.toolCall.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            if permission.toolCall.isEdit, let path = permission.toolCall.filePath {
                HStack {
                    Text("\(path) — proposed edit")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("open diff preview →") {
                        openNativeDiffPreview(permission.toolCall)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            } else if permission.toolCall.isExecute, let cmd = permission.toolCall.command {
                Text("Command: \(cmd)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                ForEach(permission.options) { option in
                    Button(option.name) {
                        onRespond(option.id)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.3), value: permission.id)
    }

    private func openNativeDiffPreview(_ toolCall: ToolCall) {
        guard let path = toolCall.filePath,
              let proposed = toolCall.proposedContent else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let oldURL = tempDir.appendingPathComponent("grok-old-\(UUID().uuidString).txt")
        let newURL = tempDir.appendingPathComponent("grok-new-\(UUID().uuidString).txt")

        do {
            // Try to get current content as "old"
            let oldContent = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            try oldContent.write(to: oldURL, atomically: true, encoding: .utf8)
            try proposed.write(to: newURL, atomically: true, encoding: .utf8)

            // Deeper: use opendiff (FileMerge) or Xcode for native diff
            let process = Process()
            if FileManager.default.fileExists(atPath: "/usr/bin/opendiff") {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/opendiff")
                process.arguments = [oldURL.path, newURL.path]
            } else {
                // Fallback to opening both or use VS Code if available
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", "Xcode", oldURL.path, newURL.path]
            }
            try process.run()
        } catch {
            // Silent fallback
            print("Failed to open native diff: \(error)")
        }
    }
}

// Simple inline diff lines for polish in permission card (reuses idea from DiffView)
struct DiffLinesView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(content.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                let (text, color, bg) = diffStyle(for: line)
                Text(text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(color)
                    .padding(.horizontal, 4)
                    .background(bg, in: Rectangle())
            }
        }
        .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }

    private func diffStyle(for line: String) -> (String, Color, Color) {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return (line, .green, .green.opacity(0.15))
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return (line, .red, .red.opacity(0.15))
        } else if line.hasPrefix("@@") {
            return (line, .blue, .blue.opacity(0.1))
        } else {
            return (line, .primary, .clear)
        }
    }
}
