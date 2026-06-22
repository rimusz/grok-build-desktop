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
    var onOpenProjectIn: (ProjectOpenTarget) -> Void = { _ in }
    var onToggleBrowserTools: () -> Void = {}
    var onSelectBrowserRuntime: (BrowserRuntimeMode) -> Void = { _ in }
    var onSwitchBranch: () -> Void = {}

    @State private var input: String = ""
    @State private var isFileDropTargeted = false
    @State private var slashActiveIndex = 0
    @State private var slashSkillsExpanded = false
    @State private var slashCommandsExpanded = false
    @State private var toolActivityExpanded = false
    @State private var voiceInput = VoiceInputService()
    @FocusState private var inputFocused: Bool
    @AppStorage(BrowserSettingsKeys.enabled) private var browserToolsEnabled = BrowserSettings.defaults.enabled

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

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if store.messages.isEmpty && store.currentWorkspace != nil {
                            switch store.connectionState {
                            case .failed: EmptyView()
                            default: welcomeState
                            }
                        }

                        ForEach(store.messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }

                        if store.isGrokking {
                            GrokkingIndicator()
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
                    scrollToBottom(proxy: proxy)
                }
            }

            composer
        }
        .onAppear { inputFocused = true }
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
                Image(systemName: "square.and.arrow.up")
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

    private var welcomeState: some View {
        VStack(spacing: 8) {
            Group {
                if let icon = GrokBrandIcon.mark() {
                    Image(nsImage: icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Grok Build")
                .font(.title3.weight(.semibold))
            Text(connectionSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
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

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.fileAttachments.isEmpty {
                FileChipBar(
                    attachments: store.fileAttachments,
                    onToggleHidden: { store.toggleFileAttachmentHidden(id: $0) },
                    onRemove: { store.removeFileAttachment(id: $0) }
                )
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
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
                        if showSlashPopover {
                            activateSlashEntry(at: slashActiveIndex)
                        } else {
                            Task { await submit() }
                        }
                    }
                    .onChange(of: input) { _, _ in
                        slashActiveIndex = 0
                        slashSkillsExpanded = false
                        slashCommandsExpanded = false
                    }
                    .onKeyPress { press in
                        if press.key == .tab, showSlashPopover, !slashMenuEntries.isEmpty {
                            activateSlashEntry(at: slashActiveIndex)
                            return .handled
                        }
                        if press.key == .return && !press.modifiers.contains(.shift) {
                            if showSlashPopover {
                                activateSlashEntry(at: slashActiveIndex)
                            } else {
                                Task { await submit() }
                            }
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.upArrow) {
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
                    fraction: store.contextUsageFraction
                )
                .help("Context usage")

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
            .frame(maxWidth: 780, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isFileDropTargeted ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isFileDropTargeted ? 1.5 : 1)
            }
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isFileDropTargeted) { providers in
                handleFileDrop(providers)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            projectStatusRow
        }
        .padding(12)
        .background(.bar)
    }

    private var projectStatusRow: some View {
        HStack(spacing: 16) {
            if let project = store.currentWorkspace {
                Label(project.displayName, systemImage: "folder")
                Button(action: onSwitchBranch) {
                    Label(currentBranchLabel(for: project.path), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
                .buttonStyle(.plain)
                .help("Branches & worktrees")
                browserStatusPill
            } else {
                Label("No project selected", systemImage: "folder")
            }
            Spacer()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var browserStatusPill: some View {
        let settings = BrowserSettingsStore.load()
        let configurationIssue = AgentBrowserService.browserToolsConfigurationIssue(settings: settings)
        let browserBaseReady = settings.backend == .agentBrowser
            && AgentBrowserService.bridgeScriptURL() != nil
            && AgentBrowserService.executableURL() != nil
        let managedRuntimeReady = AgentBrowserService.browserRuntimeConfigurationIssue(settings: settings, mode: .managed) == nil
        let externalRuntimeReady = AgentBrowserService.browserRuntimeConfigurationIssue(settings: settings, mode: .external) == nil
        let canChooseRuntime = browserBaseReady && (managedRuntimeReady || externalRuntimeReady)
        let isConfigured = configurationIssue == nil
        let title = browserToolsEnabled
            ? (isConfigured ? "Browser Tools On" : "Browser Setup Needed")
            : "Browser Tools Off"
        let icon = browserToolsEnabled && isConfigured ? "globe.badge.chevron.backward" : "globe"
        let tint: Color = browserToolsEnabled ? (isConfigured ? .accentColor : .orange) : .secondary

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
        } label: {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(browserToolsEnabled ? tint.opacity(0.14) : Color.secondary.opacity(0.10)))
                .foregroundStyle(tint)
        }
        .menuStyle(.borderlessButton)
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
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.fileAttachments.isEmpty ||
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
        Menu {
            ForEach(store.availableModels, id: \.self) { modelId in
                let isSelected = store.currentModel == modelId
                Button {
                    store.setModel(modelId)
                } label: {
                    HStack(spacing: 6) {
                        Text(store.modelDisplayName(modelId))
                        Spacer(minLength: 12)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(store.modelDisplayName(store.currentModel))
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
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Select model")
    }

    private func submit() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        _ = await store.send(text)
        inputFocused = true
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = fileURL(from: item)
                guard let url else { return }
                Task { @MainActor in
                    appendDroppedFile(url)
                }
            }
        }
        return true
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
        store.addFileAttachment(path: url.path)
        inputFocused = true
    }

    private func pickSlashCommand(_ command: SlashCommand) {
        guard let match = slashMatch else { return }
        input = SlashAutocomplete.apply(command: command, to: input, matchRange: match.range)
        inputFocused = true
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

// MARK: - Context Usage

private struct ContextUsageIndicator: View {
    let label: String
    let fraction: Double

    private var ringColor: Color {
        switch fraction {
        case 0.85...: return .red
        case 0.65...: return .orange
        default: return .green
        }
    }

    var body: some View {
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
            let oldContent = (try? String(contentsOfFile: path)) ?? ""
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

