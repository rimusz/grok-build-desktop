import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum SettingsTab: Hashable {
    case hooks
    case plugins
    case marketplace
    case skills
    case mcpServers
    case browser
    case computerUse
    case models
    case permissions
    case app
}

struct SettingsView: View {
    @Bindable var store: ChatStore
    @Binding var selectedTab: SettingsTab
    var onBackToChat: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBackToChat()
                } label: {
                    Label("Back to Session", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)

                Text("Settings")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding()

            Divider()

            TabView(selection: $selectedTab) {
                HooksSettingsPane(workspace: store.currentWorkspace)
                    .settingsPaneColumn()
                    .tabItem {
                        Label("Hooks", systemImage: "curlybraces")
                    }
                    .tag(SettingsTab.hooks)

                PluginsSettingsPane {
                    Task { await store.reloadConfiguration() }
                }
                .settingsPaneColumn()
                .tabItem {
                    Label("Plugins", systemImage: "shippingbox")
                }
                .tag(SettingsTab.plugins)

                MarketplaceSettingsPane {
                    Task { await store.reloadConfiguration() }
                }
                .settingsPaneColumn()
                .tabItem {
                    Label("Marketplace", systemImage: "storefront")
                }
                .tag(SettingsTab.marketplace)

                SkillsSettingsPane(workspace: store.currentWorkspace)
                    .settingsPaneColumn()
                    .tabItem {
                        Label("Skills", systemImage: "wand.and.stars")
                    }
                    .tag(SettingsTab.skills)

                MCPSettingsPane {
                    Task { await store.reloadConfiguration() }
                }
                .settingsPaneColumn()
                .tabItem {
                    Label("MCP Servers", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .tag(SettingsTab.mcpServers)

                BrowserSettingsPane {
                    Task { await store.reloadConfiguration() }
                }
                .tabItem {
                    Label("Browser", systemImage: "globe")
                }
                .tag(SettingsTab.browser)

                ComputerUseSettingsPane {
                    Task { await store.reloadConfiguration() }
                }
                .tabItem {
                    Label("Computer Use", systemImage: "desktopcomputer")
                }
                .tag(SettingsTab.computerUse)

                CustomModelsSettingsPane {
                    Task { await store.reloadConfiguration() }
                }
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }
                .tag(SettingsTab.models)

                PermissionsSettingsPane {
                    Task { await store.reloadConfiguration() }
                }
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
                .tag(SettingsTab.permissions)

                AppUpdatesSettingsPane()
                .tabItem {
                    Label("App", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(SettingsTab.app)
            }
            .padding()
        }
        .frame(minWidth: 860, minHeight: 620)
    }
}

private func openPath(_ path: String) {
    let expanded = (path as NSString).expandingTildeInPath
    NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
}

private struct SettingsPaneHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private func settingsPaneHeader(_ title: String, subtitle: String, systemImage: String, color: Color) -> SettingsPaneHeader {
    SettingsPaneHeader(title: title, subtitle: subtitle, systemImage: systemImage, color: color)
}

private extension View {
    /// Matches the padded, max-width-760, top-left column layout used by the
    /// Browser / Computer Use / Models panes, so list-based panes (Hooks,
    /// Plugins, Marketplace, Skills, MCP Servers) share the same chrome.
    func settingsPaneColumn() -> some View {
        self
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct BrowserSettingsPane: View {
    let onConfigurationChanged: () -> Void

    @AppStorage(BrowserSettingsKeys.enabled) private var enabled = BrowserSettings.defaults.enabled
    @AppStorage(BrowserSettingsKeys.backend) private var backend = BrowserSettings.defaults.backend.rawValue
    @AppStorage(BrowserSettingsKeys.runtimeMode) private var runtimeMode = BrowserSettings.defaults.runtimeMode.rawValue
    @AppStorage(BrowserSettingsKeys.cdpURL) private var cdpURL = BrowserSettings.defaults.cdpURL
    @AppStorage(BrowserSettingsKeys.profileName) private var profileName = BrowserSettings.defaults.profileName
    @AppStorage(BrowserSettingsKeys.showBrowserWindow) private var showBrowserWindow = BrowserSettings.defaults.showBrowserWindow
    @AppStorage(BrowserSettingsKeys.externalBrowserAppID) private var externalBrowserAppID = BrowserSettings.defaults.externalBrowserAppID.rawValue
    @AppStorage(BrowserSettingsKeys.externalBrowserAppPath) private var externalBrowserAppPath = BrowserSettings.defaults.externalBrowserAppPath
    @AppStorage(BrowserSettingsKeys.autoStartExternalBrowser) private var autoStartExternalBrowser = BrowserSettings.defaults.autoStartExternalBrowser

    @State private var status = BrowserBackendStatus.unavailable
    @State private var externalStatus = ExternalBrowserStatus.unavailable(endpoint: "http://127.0.0.1:9222")
    @State private var isChecking = false
    @State private var isInstallingRuntime = false
    @State private var isStartingExternalBrowser = false
    @State private var installOutput: String?
    @State private var externalBrowserOutput: String?
    @State private var showBrowserSessionOptions = false
    @State private var showDiagnosticsLog = false
    @State private var showRuntimeUninstallConfirmation = false
    @State private var appliedSettings = BrowserSettingsStore.loadApplied()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                browserToolsCard
                statusCard
                browserPresetsCard
                browserRuntimeCard
                applyCard
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            normalizeExternalBrowserSelection()
            await refreshStatus()
        }
        .alert("Uninstall Managed Browser Runtime?", isPresented: $showRuntimeUninstallConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall Runtime", role: .destructive) {
                uninstallManagedRuntime()
            }
        } message: {
            Text("This removes the Chrome/Chromium runtime downloaded by `agent-browser install` from `~/.agent-browser/browsers`. The agent-browser CLI and saved settings are kept.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "globe.badge.chevron.backward")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text("Browser Control")
                    .font(.title3.weight(.semibold))
                Text("Expose Chrome/Chromium browser tools to Grok sessions through the app-managed MCP bridge.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
        }
    }

    private var browserToolsCard: some View {
        settingsCard(title: "1. Enable Browser Tools", systemImage: "wrench.and.screwdriver") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable browser tools for Grok sessions")
                            .font(.headline)
                        Text("When enabled, GrokBuild injects browser MCP tools into new and resumed Grok sessions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                settingRow("Backend") {
                    Text(BrowserBackendID(rawValue: backend)?.displayName ?? backend)
                        .foregroundStyle(.secondary)
                        .frame(width: 190, alignment: .leading)
                }

                Text("For the normal setup: install the agent-browser CLI (step 2), keep the runtime below on Managed Runtime and install it (step 3), then click Apply. GrokBuild will also install a small browser-control skill into your Grok skills folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusCard: some View {
        settingsCard(title: status.isReady ? "2. agent-browser Ready" : "2. Install agent-browser CLI", systemImage: status.isReady ? "checkmark.circle" : "arrow.down.circle", tint: installCardTint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label(browserStatusTitle, systemImage: browserStatusIcon)
                        .foregroundStyle(browserStatusColor)
                        .font(.headline)
                    Spacer()
                    Button(isChecking ? "Checking..." : "Run Diagnostics") {
                        Task { await refreshStatus() }
                    }
                    .disabled(isChecking)
                }

                if status.isReady {
                    Text("The required local CLI is available. You can use its managed browser runtime, or optionally attach it to an existing Chrome instance below.")
                        .foregroundStyle(.secondary)

                } else if status.isInstalled {
                    Text("The required local CLI is installed. If you want the recommended managed browser runtime, install it in the next section.")
                        .foregroundStyle(.secondary)

                } else {
                    Text("GrokBuild needs the local `agent-browser` CLI to expose browser tools. The browser runtime itself is optional and chosen in the next section.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        installCommandRow(title: "Homebrew", command: "brew install agent-browser")
                        installCommandRow(title: "npm", command: "npm install -g agent-browser")
                    }

                    Text("GrokBuild never installs this silently. Use these commands only when you want to set up browser automation on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let installOutput, !installOutput.isEmpty {
                    Text(installOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                        .foregroundStyle(.secondary)
                }

                if let path = status.executablePath {
                    infoLine("Path", path)
                }
                if let version = status.version, !version.isEmpty {
                    infoLine("Version", version)
                }

                DisclosureGroup(isExpanded: $showDiagnosticsLog) {
                    Text(status.diagnostic.isEmpty ? "No diagnostics yet." : status.diagnostic)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                } label: {
                    Label(showDiagnosticsLog ? "Hide diagnostics log" : "Show diagnostics log", systemImage: "doc.text.magnifyingglass")
                        .font(.callout.weight(.medium))
                }

                Button {
                    NSWorkspace.shared.open(URL(string: "https://agent-browser.dev")!)
                } label: {
                    Label("Open agent-browser Docs", systemImage: "safari")
                }
            }
        }
    }

    private var browserPresetsCard: some View {
        settingsCard(title: "Quick Presets", systemImage: "wand.and.stars", tint: .purple) {
            VStack(alignment: .leading, spacing: 12) {
                Text("One-click setups for common automation targets. Applies runtime, browser app, CDP URL, and session name — you still enable Browser Tools and Apply yourself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(BrowserPreset.allCases) { preset in
                    presetRow(preset)
                    if preset.id != BrowserPreset.allCases.last?.id { Divider() }
                }
            }
        }
    }

    private func presetRow(_ preset: BrowserPreset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(preset.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Apply Preset") {
                    applyBrowserPreset(preset)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .tint(.purple)
            }
            Text(preset.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func applyBrowserPreset(_ preset: BrowserPreset) {
        let applied = preset.applied(to: currentSettings)
        runtimeMode = applied.runtimeMode.rawValue
        externalBrowserAppID = applied.externalBrowserAppID.rawValue
        externalBrowserAppPath = applied.externalBrowserAppPath
        cdpURL = applied.cdpURL
        profileName = applied.profileName
        showBrowserWindow = applied.showBrowserWindow
        autoStartExternalBrowser = applied.autoStartExternalBrowser
        normalizeExternalBrowserSelection()
    }

    private var browserRuntimeCard: some View {
        settingsCard(title: "3. Choose Browser Runtime", systemImage: "globe") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose where browser automation runs. Most users should use the managed browser runtime.")
                    .foregroundStyle(.secondary)

                browserRuntimeOption(
                    title: "Managed browser runtime",
                    subtitle: "Recommended. `agent-browser install` sets up a separate automation Chrome/Chromium runtime, so your normal daily Chrome profile is not used.",
                    systemImage: "shippingbox.circle",
                    color: .green,
                    isSelected: selectedRuntimeMode == .managed
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(managedRuntimeStatusText, systemImage: status.isReady ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(status.isReady ? .green : .secondary)

                        Toggle(isOn: $showBrowserWindow) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show browser window while agents work")
                                    .font(.callout.weight(.medium))
                                Text("Opens the managed automation browser visibly instead of keeping it headless. Apply and restart Grok after changing this.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)

                        HStack {
                            Button("Use Managed Runtime") {
                                runtimeMode = BrowserRuntimeMode.managed.rawValue
                            }
                            .disabled(selectedRuntimeMode == .managed)

                            if status.isReady {
                                Button(isInstallingRuntime ? "Repairing..." : "Reinstall / Repair Runtime") {
                                    Task { await installBrowserRuntime() }
                                }
                                .disabled(!status.isInstalled || isInstallingRuntime)

                                Button("Uninstall Runtime...", role: .destructive) {
                                    showRuntimeUninstallConfirmation = true
                                }
                                .disabled(!AgentBrowserService.hasManagedRuntimeDirectory())
                            } else {
                                Button(isInstallingRuntime ? "Installing..." : "Install Managed Runtime") {
                                    Task { await installBrowserRuntime() }
                                }
                                .disabled(!status.isInstalled || isInstallingRuntime)
                            }

                            Button("Copy Install Command") {
                                copyToPasteboard("agent-browser install")
                            }
                        }

                        if !status.isInstalled {
                            Text("Install the agent-browser CLI first before installing the managed browser runtime.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                browserRuntimeOption(
                    title: "Existing Chromium browser",
                    subtitle: "Optional. Use any Chromium-based browser you start yourself with remote debugging enabled, such as Chrome, Chromium, Brave, Edge, or Arc.",
                    systemImage: "macwindow.badge.plus",
                    color: .orange,
                    isSelected: selectedRuntimeMode == .external
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("GrokBuild can start a separate automation profile for the selected Chromium browser, then point agent-browser at its CDP URL.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Label(externalBrowserStatusText, systemImage: externalStatus.isReachable ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(externalStatus.isReachable ? .green : .secondary)

                        settingRow("Browser app") {
                            Picker("", selection: $externalBrowserAppID) {
                                ForEach(externalBrowserChoices) { app in
                                    Text(app.displayName).tag(app.rawValue)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                        }

                        if installedKnownExternalBrowsers.isEmpty {
                            Text("No supported Chromium apps were found in `/Applications`. Choose a custom Chromium app if you have one elsewhere.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if selectedExternalBrowserApp == .custom {
                            settingRow("Custom app") {
                                HStack {
                                    TextField("Path to Chromium .app", text: $externalBrowserAppPath)
                                        .textFieldStyle(.roundedBorder)
                                    Button("Choose...") {
                                        chooseExternalBrowserApp()
                                    }
                                }
                            }
                        }

                        Toggle(isOn: $autoStartExternalBrowser) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start this browser automatically when Grok starts")
                                    .font(.callout.weight(.medium))
                                Text("Uses a separate GrokBuild profile, not your normal logged-in browser profile.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)

                        settingRow("CDP URL") {
                            TextField("For the command below: http://127.0.0.1:9222", text: $cdpURL)
                                .textFieldStyle(.roundedBorder)
                        }

                        Text(externalBrowserLaunchCommand)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))

                        if let externalBrowserOutput, !externalBrowserOutput.isEmpty {
                            Text(externalBrowserOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Button("Use Existing Browser") {
                                runtimeMode = BrowserRuntimeMode.external.rawValue
                                cdpURL = defaultCDPURL
                                autoStartExternalBrowser = true
                            }

                            Button(isStartingExternalBrowser ? "Starting..." : "Start Browser Now") {
                                Task { await startExternalBrowser() }
                            }
                            .disabled(isStartingExternalBrowser)

                            Button("Check Status") {
                                Task { await refreshExternalBrowserStatus() }
                            }
                            .disabled(isChecking)

                            Button {
                                copyToPasteboard(externalBrowserLaunchCommand)
                            } label: {
                                Label("Copy Launch Command", systemImage: "doc.on.doc")
                            }

                            Button {
                                NSWorkspace.shared.open(URL(string: "https://developer.chrome.com/docs/devtools/remote-debugging/")!)
                            } label: {
                                Label("Open Setup Docs", systemImage: "questionmark.circle")
                            }
                        }
                    }
                }

                DisclosureGroup(isExpanded: $showBrowserSessionOptions) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Optional for both managed runtime and existing Chromium browser. Use this only when you want agent-browser to keep a named browser session/state instead of using the default session.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        settingRow("Session name") {
                            TextField("Optional named browser session", text: $profileName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Advanced: Browser session state", systemImage: "slider.horizontal.3")
                        .font(.callout.weight(.medium))
                }
            }
        }
    }

    private var applyCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Apply changes")
                    .font(.headline)
                Text(hasPendingBrowserChanges ? "Restart the Grok connection so browser MCP tools are injected into the active session." : "Browser launch settings are already applied to the active configuration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Apply and Restart Grok") {
                appliedSettings = currentSettings
                BrowserSettingsStore.saveApplied(currentSettings)
                onConfigurationChanged()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasPendingBrowserChanges)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(applyTint.opacity(hasPendingBrowserChanges ? 0.08 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(applyTint.opacity(hasPendingBrowserChanges ? 0.18 : 0.10)))
    }

    @MainActor
    private func refreshStatus() async {
        isChecking = true
        defer { isChecking = false }
        status = await AgentBrowserService.status()
        externalStatus = await AgentBrowserService.externalBrowserStatus(settings: currentSettings)
    }

    @MainActor
    private func installBrowserRuntime() async {
        isInstallingRuntime = true
        installOutput = "Running `agent-browser install`..."
        defer { isInstallingRuntime = false }

        do {
            let output = try await AgentBrowserService.installBrowserRuntime()
            installOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            await refreshStatus()
        } catch {
            installOutput = error.localizedDescription
        }
    }

    @MainActor private func uninstallManagedRuntime() {
        do {
            installOutput = try AgentBrowserService.uninstallManagedRuntime()
            Task { await refreshStatus() }
        } catch {
            installOutput = error.localizedDescription
        }
    }

    @MainActor
    private func startExternalBrowser() async {
        runtimeMode = BrowserRuntimeMode.external.rawValue
        if cdpURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cdpURL = defaultCDPURL
        }
        isStartingExternalBrowser = true
        externalBrowserOutput = "Starting \(selectedExternalBrowserApp.displayName) with a separate GrokBuild automation profile..."
        defer { isStartingExternalBrowser = false }

        do {
            externalStatus = try await AgentBrowserService.launchExternalBrowser(settings: currentSettings)
            externalBrowserOutput = externalStatus.diagnostic
        } catch {
            externalBrowserOutput = error.localizedDescription
            externalStatus = await AgentBrowserService.externalBrowserStatus(settings: currentSettings)
        }
    }

    @MainActor
    private func refreshExternalBrowserStatus() async {
        isChecking = true
        defer { isChecking = false }
        externalStatus = await AgentBrowserService.externalBrowserStatus(settings: currentSettings)
    }

    private func chooseExternalBrowserApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose Chromium Browser"
        panel.message = "Choose a Chromium-based browser app that supports Chrome DevTools Protocol."
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            externalBrowserAppID = ExternalBrowserAppID.custom.rawValue
            externalBrowserAppPath = url.path
        }
    }

    private var statusBadge: some View {
        let color: Color = enabled ? browserStatusColor : .secondary
        let text = enabled ? (status.isReady ? "Ready" : "Setup needed") : "Disabled"

        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color)
    }

    private var selectedExternalBrowserApp: ExternalBrowserAppID {
        ExternalBrowserAppID(rawValue: externalBrowserAppID) ?? BrowserSettings.defaults.externalBrowserAppID
    }

    private var selectedRuntimeMode: BrowserRuntimeMode {
        BrowserRuntimeMode(rawValue: runtimeMode) ?? BrowserSettings.defaults.runtimeMode
    }

    private var installedKnownExternalBrowsers: [ExternalBrowserAppID] {
        ExternalBrowserAppID.allCases.filter { app in
            app != .custom && app.defaultAppURL != nil
        }
    }

    private var externalBrowserChoices: [ExternalBrowserAppID] {
        installedKnownExternalBrowsers + [.custom]
    }

    private func normalizeExternalBrowserSelection() {
        guard !externalBrowserChoices.contains(selectedExternalBrowserApp) else { return }
        externalBrowserAppID = installedKnownExternalBrowsers.first?.rawValue ?? ExternalBrowserAppID.custom.rawValue
    }

    private var externalBrowserLaunchCommand: String {
        AgentBrowserService.externalBrowserLaunchCommand(settings: currentSettings)
    }

    private var externalBrowserStatusText: String {
        if externalStatus.isReachable {
            return externalStatus.browserName.map { "External browser running: \($0)" }
                ?? "External browser running at \(externalStatus.endpoint)"
        }
        if selectedExternalBrowserApp == .custom && externalBrowserAppPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Choose a Chromium app to start automatically"
        }
        return "External browser not running yet"
    }

    private var defaultCDPURL: String {
        "http://127.0.0.1:9222"
    }

    private var managedRuntimeStatusText: String {
        if status.isReady {
            return "Managed runtime installed and ready"
        }
        if status.isInstalled {
            return "Managed runtime not ready or not installed"
        }
        return "Install agent-browser CLI first"
    }

    private var currentSettings: BrowserSettings {
        BrowserSettings(
            enabled: enabled,
            backend: BrowserBackendID(rawValue: backend) ?? BrowserSettings.defaults.backend,
            runtimeMode: selectedRuntimeMode,
            cdpURL: cdpURL,
            profileName: profileName,
            showBrowserWindow: showBrowserWindow,
            externalBrowserAppID: ExternalBrowserAppID(rawValue: externalBrowserAppID)
                ?? BrowserSettings.defaults.externalBrowserAppID,
            externalBrowserAppPath: externalBrowserAppPath,
            autoStartExternalBrowser: autoStartExternalBrowser
        )
    }

    private var hasPendingBrowserChanges: Bool {
        currentSettings != appliedSettings
    }

    private var applyTint: Color {
        hasPendingBrowserChanges ? .accentColor : .secondary
    }

    private var browserStatusTitle: String {
        if status.isReady { return "agent-browser ready" }
        if status.isInstalled { return "agent-browser setup needed" }
        return "agent-browser not installed"
    }

    private var browserStatusIcon: String {
        if status.isReady { return "checkmark.circle.fill" }
        if status.isInstalled { return "exclamationmark.triangle.fill" }
        return "xmark.circle.fill"
    }

    private var browserStatusColor: Color {
        if status.isReady { return .green }
        if status.isInstalled { return .orange }
        return .red
    }

    private var installCardTint: Color {
        status.isReady ? .green : (status.isInstalled ? .orange : .secondary)
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint ?? .primary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(tint.map { $0.opacity(0.07) } ?? Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.map { $0.opacity(0.22) } ?? Color(nsColor: .separatorColor).opacity(0.6)))
    }

    private func browserRuntimeOption<Content: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color,
        isSelected: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : systemImage)
                    .font(.title3)
                    .foregroundStyle(isSelected ? color : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(isSelected ? "Selected" : "Optional")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill((isSelected ? color : Color.secondary).opacity(0.14)))
                    .foregroundStyle(isSelected ? color : .secondary)
            }

            content()
                .padding(.leading, 36)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill((isSelected ? color : Color.secondary).opacity(isSelected ? 0.08 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke((isSelected ? color : Color.secondary).opacity(isSelected ? 0.24 : 0.12)))
    }

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func infoLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
        }
        .font(.caption)
    }

    private func installCommandRow(title: String, command: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                copyToPasteboard(command)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
    }
}

private struct PluginsSettingsPane: View {
    let onConfigurationChanged: () -> Void

    private let service = GrokCLIService()
    @State private var plugins: [GrokPluginInfo] = []
    @State private var installSource = ""
    @State private var trustInstall = false
    @State private var selectedDetails: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                settingsPaneHeader(
                    "Plugins",
                    subtitle: "Manage installed Grok plugins and manually add trusted plugin sources.",
                    systemImage: "shippingbox",
                    color: .indigo
                )
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            HStack {
                TextField("GitHub repo, Git URL, or local path", text: $installSource)
                Toggle("Trust", isOn: $trustInstall)
                Button("Install") {
                    Task { await installPlugin() }
                }
                .disabled(installSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            List {
                ForEach(plugins) { plugin in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plugin.name)
                                    .font(.headline)
                                Text([plugin.version, plugin.scope, plugin.source].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(plugin.isEnabled ? "Enabled" : "Disabled")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(plugin.isEnabled ? .green : .secondary)
                        }

                        if !plugin.description.isEmpty {
                            Text(plugin.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !plugin.componentSummary.isEmpty {
                            Text(plugin.componentSummary)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        HStack {
                            Button(plugin.isEnabled ? "Disable" : "Enable") {
                                Task { await setPlugin(plugin, enabled: !plugin.isEnabled) }
                            }
                            Button("Details") {
                                Task { await loadDetails(plugin) }
                            }
                            Button("Update") {
                                Task { await updatePlugin(plugin) }
                            }
                            Button("Uninstall", role: .destructive) {
                                Task { await uninstallPlugin(plugin) }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlay {
                if plugins.isEmpty && !isLoading {
                    ContentUnavailableView("No Plugins", systemImage: "shippingbox", description: Text("Install a plugin manually or from Marketplace."))
                }
            }

            if let selectedDetails {
                Divider()
                Text("Details")
                    .font(.headline)
                ScrollView {
                    Text(selectedDetails)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 180)
            }
        }
        .overlay(alignment: .bottom) {
            statusOverlay
        }
        .task { await refresh() }
        .toolbar {
            Button("Refresh") {
                Task { await refresh() }
            }
        }
    }

    private var statusOverlay: some View {
        VStack {
            if isLoading {
                ProgressView()
                    .padding(8)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func header(_ text: String, systemImage: String) -> some View {
        HStack {
            Label(text, systemImage: systemImage)
                .font(.headline)
            Spacer()
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
    }

    private func refresh() async {
        await perform {
            plugins = try await service.listPlugins()
        }
    }

    private func installPlugin() async {
        let source = installSource.trimmingCharacters(in: .whitespacesAndNewlines)
        await perform {
            try await service.installPlugin(source: source, trust: trustInstall)
            installSource = ""
            try await refreshAfterMutation()
        }
    }

    private func uninstallPlugin(_ plugin: GrokPluginInfo) async {
        await perform {
            try await service.uninstallPlugin(name: plugin.name, keepData: false)
            try await refreshAfterMutation()
        }
    }

    private func setPlugin(_ plugin: GrokPluginInfo, enabled: Bool) async {
        await perform {
            try await service.setPlugin(name: plugin.name, enabled: enabled)
            try await refreshAfterMutation()
        }
    }

    private func updatePlugin(_ plugin: GrokPluginInfo) async {
        await perform {
            try await service.updatePlugin(name: plugin.name)
            try await refreshAfterMutation()
        }
    }

    private func loadDetails(_ plugin: GrokPluginInfo) async {
        await perform {
            selectedDetails = try await service.pluginDetails(name: plugin.name)
        }
    }

    private func refreshAfterMutation() async throws {
        plugins = try await service.listPlugins()
        onConfigurationChanged()
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct HooksSettingsPane: View {
    let workspace: Workspace?

    private let service = GrokCLIService()
    @State private var hooks: [GrokHookInfo] = []
    @State private var filter = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filteredHooks: [GrokHookInfo] {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return hooks }
        return hooks.filter {
            $0.event.localizedCaseInsensitiveContains(trimmed) ||
            $0.target.localizedCaseInsensitiveContains(trimmed) ||
            $0.sourceType.localizedCaseInsensitiveContains(trimmed) ||
            $0.sourcePath.localizedCaseInsensitiveContains(trimmed) ||
            $0.pluginName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                settingsPaneHeader(
                    "Hooks",
                    subtitle: "Inspect automation hooks discovered from Grok, Cursor, Claude, projects, and plugins.",
                    systemImage: "curlybraces",
                    color: .mint
                )
                Button("Refresh") {
                    Task { await refresh() }
                }
            }

            TextField("Search hooks", text: $filter)
                .textFieldStyle(.roundedBorder)

            List {
                ForEach(filteredHooks) { hook in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(hook.event.isEmpty ? "Unknown event" : hook.event)
                                .font(.headline)
                            if !hook.matcher.isEmpty {
                                Text(hook.matcher)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(sourceLabel(for: hook))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        Text([hook.hookType, hook.vendor].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(hook.target)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        if !hook.sourcePath.isEmpty {
                            HStack {
                                Text(hook.sourcePath)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("Open Source") {
                                    openPath(hook.sourcePath)
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlay {
                if hooks.isEmpty && !isLoading {
                    ContentUnavailableView("No Hooks", systemImage: "curlybraces", description: Text("Grok did not report any hooks for this project."))
                }
            }

            if isLoading { ProgressView() }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Text("Hooks are discovered from Grok, Cursor, Claude, project, and plugin sources via `grok inspect --json`.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            hooks = try await service.listHooks(cwd: workspace?.path)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func sourceLabel(for hook: GrokHookInfo) -> String {
        if !hook.pluginName.isEmpty { return "plugin: \(hook.pluginName)" }
        return hook.sourceType.isEmpty ? "unknown" : hook.sourceType
    }
}

private struct MarketplaceSettingsPane: View {
    let onConfigurationChanged: () -> Void

    private let service = GrokCLIService()
    @State private var availablePlugins: [GrokPluginInfo] = []
    @State private var marketplaceSources: [GrokMarketplaceSource] = []
    @State private var marketplaceSource = ""
    @State private var availableFilter = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filteredAvailablePlugins: [GrokPluginInfo] {
        let filter = availableFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty else { return availablePlugins }
        return availablePlugins.filter {
            $0.name.localizedCaseInsensitiveContains(filter) ||
            $0.description.localizedCaseInsensitiveContains(filter) ||
            $0.marketplace.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                settingsPaneHeader(
                    "Marketplace",
                    subtitle: "Browse available plugins and manage marketplace sources.",
                    systemImage: "storefront",
                    color: .orange
                )
                Button("Refresh") {
                    Task { await refresh() }
                }
            }

            HStack {
                TextField("Marketplace Git URL or owner/repo", text: $marketplaceSource)
                Button("Add Source") {
                    Task { await addMarketplace() }
                }
                .disabled(marketplaceSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextField("Search available plugins", text: $availableFilter)
                .textFieldStyle(.roundedBorder)

            HSplitView {
                List {
                    ForEach(filteredAvailablePlugins) { plugin in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(plugin.name)
                                        .font(.headline)
                                    Text([plugin.marketplace, plugin.componentSummary].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Install") {
                                    Task { await installAvailablePlugin(plugin) }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }

                            if !plugin.description.isEmpty {
                                Text(plugin.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .overlay {
                    if availablePlugins.isEmpty && !isLoading {
                        ContentUnavailableView("No Available Plugins", systemImage: "storefront", description: Text("Refresh marketplace sources or add a source above."))
                    }
                }

                List {
                    Section("Sources") {
                        ForEach(marketplaceSources) { source in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(source.name)
                                            .font(.headline)
                                        Text(source.location)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                    Button("Remove", role: .destructive) {
                                        Task { await removeMarketplace(source) }
                                    }
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }

            if isLoading { ProgressView() }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        await perform {
            let allPlugins = try await service.listPlugins(includeAvailable: true)
            async let sources = service.listMarketplaceSources()
            availablePlugins = allPlugins.filter { $0.status == "available" }
            marketplaceSources = try await sources
        }
    }

    private func installAvailablePlugin(_ plugin: GrokPluginInfo) async {
        await perform {
            try await service.installPlugin(source: plugin.name, trust: true)
            try await refreshAfterMutation()
        }
    }

    private func addMarketplace() async {
        let source = marketplaceSource.trimmingCharacters(in: .whitespacesAndNewlines)
        await perform {
            try await service.addMarketplaceSource(source)
            marketplaceSource = ""
            try await refreshAfterMutation()
        }
    }

    private func removeMarketplace(_ source: GrokMarketplaceSource) async {
        await perform {
            try await service.removeMarketplaceSource(source.location)
            try await refreshAfterMutation()
        }
    }

    private func refreshAfterMutation() async throws {
        let allPlugins = try await service.listPlugins(includeAvailable: true)
        availablePlugins = allPlugins.filter { $0.status == "available" }
        marketplaceSources = try await service.listMarketplaceSources()
        onConfigurationChanged()
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct SkillsSettingsPane: View {
    let workspace: Workspace?

    private let service = GrokCLIService()
    @State private var skills: [GrokSkillInfo] = []
    @State private var filter = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filteredSkills: [GrokSkillInfo] {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return skills }
        return skills.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.description.localizedCaseInsensitiveContains(trimmed) ||
            $0.sourceType.localizedCaseInsensitiveContains(trimmed) ||
            $0.sourcePath.localizedCaseInsensitiveContains(trimmed) ||
            $0.pluginName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                settingsPaneHeader(
                    "Skills",
                    subtitle: "View user, project, compatibility, and plugin skills available to Grok.",
                    systemImage: "wand.and.stars",
                    color: .pink
                )
                Button("Refresh") {
                    Task { await refresh() }
                }
            }

            TextField("Search skills", text: $filter)
                .textFieldStyle(.roundedBorder)

            List {
                ForEach(filteredSkills) { skill in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(skill.name)
                                .font(.headline)
                            if skill.userInvocable {
                                Text("/\(skill.name)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(sourceLabel(for: skill))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        if !skill.description.isEmpty {
                            Text(skill.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }

                        if !skill.sourcePath.isEmpty {
                            HStack {
                                Text(skill.sourcePath)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("Open SKILL.md") {
                                    openPath(skill.sourcePath)
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlay {
                if skills.isEmpty && !isLoading {
                    ContentUnavailableView("No Skills", systemImage: "wand.and.stars", description: Text("Grok did not report any skills for this project."))
                }
            }

            if isLoading { ProgressView() }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Text("Skills are discovered from user, project, compatibility, and plugin locations via `grok inspect --json`.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            skills = try await service.listSkills(cwd: workspace?.path)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func sourceLabel(for skill: GrokSkillInfo) -> String {
        if !skill.pluginName.isEmpty { return "plugin: \(skill.pluginName)" }
        return skill.sourceType.isEmpty ? "unknown" : skill.sourceType
    }
}

private struct ComputerUseSettingsPane: View {
    let onConfigurationChanged: () -> Void

    @AppStorage(ComputerUseSettingsKeys.enabled) private var enabled = ComputerUseSettings.defaults.enabled
    @AppStorage(ComputerUseSettingsKeys.backend) private var backend = ComputerUseSettings.defaults.backend.rawValue
    @AppStorage(ComputerUseSettingsKeys.permissionPolicy) private var permissionPolicy = ComputerUseSettings.defaults.permissionPolicy.rawValue
    @AppStorage(ComputerUseSettingsKeys.maxSteps) private var maxSteps = ComputerUseSettings.defaults.maxSteps
    @AppStorage(ComputerUseSettingsKeys.commandTimeoutSeconds) private var commandTimeoutSeconds = ComputerUseSettings.defaults.commandTimeoutSeconds
    @AppStorage(ComputerUseSettingsKeys.screenshotMode) private var screenshotMode = ComputerUseSettings.defaults.screenshotMode.rawValue
    @AppStorage(ComputerUseSettingsKeys.includeScreenshots) private var includeScreenshots = ComputerUseSettings.defaults.includeScreenshots
    @AppStorage(ComputerUseSettingsKeys.allowPhysicalMouse) private var allowPhysicalMouse = ComputerUseSettings.defaults.allowPhysicalMouse
    @AppStorage(ComputerUseSettingsKeys.sessionName) private var sessionName = ComputerUseSettings.defaults.sessionName
    @AppStorage(ComputerUseSettingsKeys.cursorIntegrationEnabled) private var cursorIntegrationEnabled = false
    @AppStorage(ComputerUseSettingsKeys.appliedCursorIntegrationEnabled) private var appliedCursorIntegrationEnabled = false

    @State private var backendStatus = ComputerUseBackendStatus.unavailable
    @State private var cursorInstallStatus = ComputerUseCursorInstallStatus.unavailable
    @State private var permissionStatus = ComputerUsePermissionStatus.unavailable
    @State private var appliedSettings = ComputerUseSettingsStore.loadApplied()
    @State private var isChecking = false
    @State private var isRequestingPermissions = false
    @State private var permissionOutput: String?
    @State private var showDiagnosticsLog = false
    @State private var showPermissionDiagnostics = false
    @State private var showAdvancedOptions = false
    @State private var isInstallingForCursor = false
    @State private var isRemovingCursorIntegration = false
    @State private var cursorInstallOutput: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                enableCard
                statusCard
                permissionsCard
                safetyCard
                cursorIntegrationCard
                applyCard
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            appliedSettings = ComputerUseSettingsStore.loadApplied()
            await refreshStatus()
            syncCursorConfiguration(showErrorsOnly: true)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text("Computer Use")
                    .font(.title3.weight(.semibold))
                Text("Expose local macOS desktop-control tools to Grok sessions through the app-managed MCP helper and agent-desktop.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
        }
    }

    private var enableCard: some View {
        computerSettingsCard(title: "1. Enable Computer Use", systemImage: "wrench.and.screwdriver") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Computer Use tools for Grok sessions")
                            .font(.headline)
                        Text("When enabled, GrokBuild injects `computer_*` MCP tools into new and resumed Grok sessions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: enabled) { _, newValue in
                    guard newValue != appliedSettings.enabled else { return }
                    Task { await applyEnabledChange(to: newValue) }
                }

                Divider()

                settingRow("Backend") {
                    Text(ComputerUseBackendID(rawValue: backend)?.displayName ?? backend)
                        .foregroundStyle(.secondary)
                        .frame(width: 190, alignment: .leading)
                }

                Text("agent-desktop ships inside GrokBuild, so there's nothing to install. Grant Accessibility permission below, then click Apply after enabling tools. GrokBuild will also install a small Computer Use skill into your Grok skills folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusCard: some View {
        computerSettingsCard(title: backendStatus.isInstalled ? "2. agent-desktop Ready" : "2. agent-desktop Unavailable", systemImage: backendStatus.isInstalled ? "checkmark.circle" : "exclamationmark.triangle", tint: installCardTint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label(backendStatusTitle, systemImage: backendStatusIcon)
                        .foregroundStyle(backendStatusColor)
                        .font(.headline)
                    Spacer()
                    Button(isChecking ? "Checking..." : "Run Diagnostics") {
                        Task { await refreshStatus() }
                    }
                    .disabled(isChecking)
                }

                if backendStatus.isInstalled {
                    Text("agent-desktop ships inside GrokBuild and shares the app's permissions. Grant macOS permissions below, then enable and apply Computer Use.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("agent-desktop is bundled with GrokBuild, so this is unexpected. Reinstalling the app from the latest release should restore it.")
                        .foregroundStyle(.secondary)
                }

                if let path = backendStatus.executablePath {
                    infoLine("Path", path)
                }
                if let version = backendStatus.version, !version.isEmpty {
                    infoLine("Version", version)
                }

                DisclosureGroup(isExpanded: $showDiagnosticsLog) {
                    Text(backendStatus.diagnostic.isEmpty ? "No diagnostics yet." : backendStatus.diagnostic)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                } label: {
                    Label(showDiagnosticsLog ? "Hide diagnostics log" : "Show diagnostics log", systemImage: "doc.text.magnifyingglass")
                        .font(.callout.weight(.medium))
                }

                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/lahfir/agent-desktop")!)
                } label: {
                    Label("Open agent-desktop Docs", systemImage: "safari")
                }
            }
        }
    }

    private var permissionsCard: some View {
        computerSettingsCard(title: "3. macOS Permissions", systemImage: permissionStatus.isReady ? "lock.open.fill" : "lock.shield.fill", tint: permissionsTint) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Computer Use cannot be enabled from the chat until required permissions are ready.")
                    .foregroundStyle(.secondary)

                permissionRow(
                    title: "Accessibility",
                    state: permissionStatus.accessibility,
                    help: "Required for snapshots and UI actions."
                )
                permissionRow(
                    title: "Screen Recording",
                    state: permissionStatus.screenRecording,
                    help: "Required only when screenshot tools are enabled."
                )

                if ComputerUseService.usesBundledAgentDesktop(settings: currentSettings) {
                    Text("agent-desktop is bundled inside this app and uses the same Accessibility permission as GrokBuild.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let agentDesktopPath = ComputerUseService.executableURL(settings: currentSettings)?.path {
                    Text("Also enable agent-desktop in Accessibility: \(agentDesktopPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let guidance = permissionStatus.guidance {
                    Text(guidance)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button("Open Accessibility Settings") {
                            Task { @MainActor in
                                ComputerUseService.openAccessibilitySettings()
                            }
                        }
                        Button("Show App in Finder") {
                            ComputerUseService.revealAppInFinder()
                        }
                    }
                }

                HStack {
                    Button(isRequestingPermissions ? "Requesting..." : "Request Permissions") {
                        Task { await requestPermissions() }
                    }
                    .disabled(!backendStatus.isInstalled || isRequestingPermissions)

                    Button("Refresh") {
                        Task { await refreshStatus() }
                    }
                    .disabled(isChecking)

                    Button(showPermissionDiagnostics ? "Hide Diagnostics" : "Show Diagnostics") {
                        showPermissionDiagnostics.toggle()
                    }
                    Spacer()
                }

                if showPermissionDiagnostics {
                    Text(permissionDiagnosticsText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var safetyCard: some View {
        computerSettingsCard(title: "4. Safety and Session Options", systemImage: "hand.raised.fill", tint: .blue) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Keep desktop automation conservative. Grok still asks for permission for high-risk actions through the normal permission flow.")
                    .foregroundStyle(.secondary)

                settingRow("Action policy") {
                    Picker("", selection: $permissionPolicy) {
                        ForEach(ComputerUsePermissionPolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    .onChange(of: permissionPolicy) { _, _ in
                        syncCursorConfiguration()
                    }
                }

                Toggle(isOn: $includeScreenshots) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow screenshot tool")
                            .font(.callout.weight(.medium))
                        Text("Use screenshots only when Accessibility snapshots are not enough.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: includeScreenshots) { _, _ in
                    syncCursorConfiguration()
                }

                Toggle(isOn: $allowPhysicalMouse) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow physical mouse actions")
                            .font(.callout.weight(.medium))
                        Text("Disabled by default. Prefer accessibility actions unless you explicitly need real pointer movement.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: allowPhysicalMouse) { _, _ in
                    syncCursorConfiguration()
                }

                DisclosureGroup(isExpanded: $showAdvancedOptions) {
                    VStack(alignment: .leading, spacing: 10) {
                        settingRow("Screenshot mode") {
                            Picker("", selection: $screenshotMode) {
                                ForEach(ComputerUseScreenshotMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode.rawValue)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                        }
                        Stepper("Max steps per request: \(maxSteps)", value: $maxSteps, in: 1...100)
                            .onChange(of: maxSteps) { _, _ in
                                syncCursorConfiguration()
                            }
                        Stepper("Command timeout: \(commandTimeoutSeconds)s", value: $commandTimeoutSeconds, in: 5...180, step: 5)
                            .onChange(of: commandTimeoutSeconds) { _, _ in
                                syncCursorConfiguration()
                            }
                        settingRow("Session name") {
                            TextField("Optional Computer Use session name", text: $sessionName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    syncCursorConfiguration()
                                }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Advanced: Computer Use session state", systemImage: "slider.horizontal.3")
                        .font(.callout.weight(.medium))
                }
            }
        }
    }

    private var cursorIntegrationCard: some View {
        computerSettingsCard(
            title: cursorInstallStatus.isInstalled ? "5. Cursor Integration Ready" : "5. Install for Cursor",
            systemImage: cursorInstallStatus.isInstalled ? "cursorarrow.rays" : "cursorarrow",
            tint: cursorInstallStatus.isInstalled ? .green : .secondary
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $cursorIntegrationEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Computer Use in Cursor globally")
                            .font(.headline)
                        Text("Copies the MCP helper and agent-desktop into `~/.grokbuild/computer-use/` and adds `grokbuild-computer-use` to `~/.cursor/mcp.json`.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if cursorInstallStatus.isInstalled {
                    Label("Cursor can use `computer_*` tools in any workspace after MCP reload.", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Text("Install once to expose the same desktop-control tools to Cursor Agent mode across all projects.")
                        .foregroundStyle(.secondary)
                }

                if let helperPath = cursorInstallStatus.helperPath {
                    infoLine("Helper", helperPath)
                }
                if let agentDesktopPath = cursorInstallStatus.agentDesktopPath {
                    infoLine("agent-desktop", agentDesktopPath)
                }
                infoLine("MCP config", cursorInstallStatus.mcpConfigPath)

                HStack {
                    Button(isInstallingForCursor ? "Installing..." : (cursorInstallStatus.isInstalled ? "Update for Cursor" : "Install for Cursor")) {
                        Task { await installForCursor() }
                    }
                    .disabled(!backendStatus.isInstalled || isInstallingForCursor || isRemovingCursorIntegration)

                    if cursorInstallStatus.isInstalled {
                        Button(isRemovingCursorIntegration ? "Removing..." : "Remove from Cursor", role: .destructive) {
                            Task { await removeCursorIntegration() }
                        }
                        .disabled(isInstallingForCursor || isRemovingCursorIntegration)
                    }

                    Button("Reveal MCP Config") {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            URL(fileURLWithPath: cursorInstallStatus.mcpConfigPath)
                        ])
                    }
                }

                if let cursorInstallOutput, !cursorInstallOutput.isEmpty {
                    Text(cursorInstallOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var applyCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Apply changes")
                    .font(.headline)
                Text(hasPendingChanges
                    ? "Restart the Grok connection so Computer Use MCP tools are injected into the active session."
                    : "Computer Use settings are already applied to the active configuration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Apply and Restart Grok") {
                apply()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasPendingChanges)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(applyTint.opacity(hasPendingChanges ? 0.08 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(applyTint.opacity(hasPendingChanges ? 0.18 : 0.10)))
    }

    private var currentSettings: ComputerUseSettings {
        ComputerUseSettings(
            enabled: enabled,
            backend: ComputerUseBackendID(rawValue: backend) ?? ComputerUseSettings.defaults.backend,
            agentDesktopPath: "",
            permissionPolicy: ComputerUsePermissionPolicy(rawValue: permissionPolicy)
                ?? ComputerUseSettings.defaults.permissionPolicy,
            maxSteps: maxSteps,
            commandTimeoutSeconds: commandTimeoutSeconds,
            screenshotMode: ComputerUseScreenshotMode(rawValue: screenshotMode)
                ?? ComputerUseSettings.defaults.screenshotMode,
            includeScreenshots: includeScreenshots,
            allowPhysicalMouse: allowPhysicalMouse,
            sessionName: sessionName
        )
    }

    private var hasPendingChanges: Bool {
        currentSettings != appliedSettings || cursorIntegrationEnabled != appliedCursorIntegrationEnabled
    }

    private var statusBadge: some View {
        let isEnabled = appliedSettings.enabled
        let text = isEnabled ? (permissionStatus.isReady ? "Ready" : "Setup needed") : "Disabled"
        let color: Color = isEnabled ? (permissionStatus.isReady ? .green : .orange) : .secondary
        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color)
    }

    private var backendStatusTitle: String {
        if backendStatus.isInstalled {
            return backendStatus.version.map { "agent-desktop ready (\($0))" } ?? "agent-desktop ready"
        }
        return "agent-desktop not installed"
    }

    private var backendStatusIcon: String {
        backendStatus.isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var backendStatusColor: Color {
        backendStatus.isInstalled ? .green : .red
    }

    private var installCardTint: Color {
        backendStatus.isInstalled ? .green : .secondary
    }

    private var permissionsTint: Color {
        permissionStatus.isReady ? .green : .orange
    }

    private var applyTint: Color {
        hasPendingChanges ? .accentColor : .secondary
    }

    private var permissionDiagnosticsText: String {
        var parts: [String] = []
        if let guidance = permissionStatus.guidance {
            parts.append(guidance)
        }
        parts.append(
            permissionStatus.diagnostic.isEmpty
                ? "No permission diagnostics yet."
                : permissionStatus.diagnostic
        )
        if let permissionOutput, !permissionOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Last request:\n\(permissionOutput)")
        }
        return parts.joined(separator: "\n\n")
    }

    private func apply() {
        let settings = currentSettings
        let shouldInstallCursor = cursorIntegrationEnabled
        let shouldUninstallCursor = appliedCursorIntegrationEnabled && !cursorIntegrationEnabled

        ComputerUseSettingsStore.save(settings)
        ComputerUseSettingsStore.saveApplied(settings)
        appliedSettings = settings
        appliedCursorIntegrationEnabled = cursorIntegrationEnabled
        syncCursorConfiguration(showErrorsOnly: true)

        if shouldInstallCursor {
            Task {
                await installForCursor(showErrorsOnly: false)
                onConfigurationChanged()
            }
        } else if shouldUninstallCursor {
            Task {
                await removeCursorIntegration()
                onConfigurationChanged()
            }
        } else {
            onConfigurationChanged()
        }
    }

    private func applyEnabledChange(to newValue: Bool) async {
        let result = await ComputerUseService.applyEnabled(newValue, settings: currentSettings) {
            onConfigurationChanged()
        }
        if case .needsSetup = result {
            enabled = appliedSettings.enabled
        } else {
            appliedSettings = ComputerUseSettingsStore.loadApplied()
            await refreshStatus()
        }
    }

    private func syncCursorConfiguration(showErrorsOnly: Bool = false) {
        guard cursorInstallStatus.isInstalled else { return }
        do {
            if let message = try ComputerUseService.syncCursorIntegrationIfInstalled(settings: currentSettings) {
                if !showErrorsOnly {
                    cursorInstallOutput = message
                }
            }
            appliedSettings = ComputerUseSettingsStore.loadApplied()
            cursorInstallStatus = ComputerUseCursorInstaller.status()
        } catch {
            if !showErrorsOnly {
                cursorInstallOutput = error.localizedDescription
            }
        }
    }

    private func refreshStatus() async {
        isChecking = true
        defer { isChecking = false }
        let settings = currentSettings
        async let status = ComputerUseService.status(settings: settings)
        async let permissions = ComputerUseService.permissionStatus(settings: settings)
        backendStatus = await status
        permissionStatus = await permissions
        cursorInstallStatus = ComputerUseCursorInstaller.status()
    }

    private func installForCursor(showErrorsOnly: Bool = true) async {
        isInstallingForCursor = true
        if !showErrorsOnly {
            cursorInstallOutput = "Installing Computer Use for Cursor..."
        }
        defer { isInstallingForCursor = false }

        do {
            cursorInstallOutput = try ComputerUseCursorInstaller.install(settings: currentSettings)
            cursorInstallStatus = ComputerUseCursorInstaller.status()
        } catch {
            cursorInstallOutput = error.localizedDescription
        }
    }

    private func removeCursorIntegration() async {
        isRemovingCursorIntegration = true
        cursorInstallOutput = "Removing Computer Use from Cursor..."
        defer { isRemovingCursorIntegration = false }

        do {
            cursorInstallOutput = try ComputerUseCursorInstaller.uninstall()
            cursorIntegrationEnabled = false
            appliedCursorIntegrationEnabled = false
            cursorInstallStatus = ComputerUseCursorInstaller.status()
        } catch {
            cursorInstallOutput = error.localizedDescription
        }
    }

    private func requestPermissions() async {
        isRequestingPermissions = true
        permissionOutput = "Requesting Accessibility permission for GrokBuild..."
        defer { isRequestingPermissions = false }

        do {
            permissionOutput = try await ComputerUseService.requestPermissions(settings: currentSettings)
            await refreshStatus()
        } catch {
            permissionOutput = error.localizedDescription
        }
    }

    private func permissionRow(title: String, state: String, help: String) -> some View {
        let normalized = state.lowercased()
        let isGranted = normalized == "granted"
        let isNeutral = normalized == "unknown" || normalized == "not reported"
        let color: Color = isGranted ? .green : (isNeutral ? .secondary : .orange)
        let icon = isGranted
            ? "checkmark.circle.fill"
            : (isNeutral ? "minus.circle" : "exclamationmark.triangle.fill")
        let label = normalized == "not reported" ? "Not reported" : state.capitalized
        return HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .frame(width: 120, alignment: .leading)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func infoLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func installCommandRow(title: String, command: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
            Spacer()
            Button {
                copyToPasteboard(command)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
    }

    private func computerSettingsCard<Content: View>(
        title: String,
        systemImage: String,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint ?? .primary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(tint.map { $0.opacity(0.07) } ?? Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.map { $0.opacity(0.22) } ?? Color(nsColor: .separatorColor).opacity(0.6)))
    }
}

private struct CustomModelsSettingsPane: View {
    let onConfigurationChanged: () -> Void

    @AppStorage(GrokSettingsKeys.reasoningEffort) private var reasoningEffort = GrokPermissionSettings.defaults.reasoningEffort
    @State private var providers: [Provider] = []
    @State private var models: [CustomModel] = []
    @State private var editingID: String?
    @State private var draft = CustomModel(id: "", model: "", baseURL: "")
    @State private var revealKey = false
    @State private var editingProviderID: String?
    @State private var providerDraft = Provider(id: "", name: "", baseURL: "")
    @State private var revealProviderKey = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    // Fetched-model state, keyed by the provider id the models were fetched for.
    @State private var fetchedModels: [String: [FetchedModel]] = [:]
    @State private var fetchingProviderID: String?
    @State private var fetchErrorProviderID: String?
    @State private var fetchErrorMessage: String?

    // Drives programmatic scrolling to an editor when a card opens it.
    @State private var scrollTarget: String?
    // True while the provider editor holds a not-yet-saved template (so we lock the id and
    // prompt for the key). Cleared once the provider is saved or the draft is reset.
    @State private var providerDraftFromPreset = false
    // The editor cards are hidden until the user explicitly opens them via Install / Add /
    // Edit, keeping the default view a clean list.
    @State private var showingProviderEditor = false
    @State private var showingModelEditor = false
    // The provider-template catalog is collapsed by default so "Add Provider" stays compact.
    @State private var showingProviderTemplates = false
    @State private var showModelRemovalConfirmation = false
    @State private var modelPendingRemoval: CustomModel?
    @State private var showProviderRemovalConfirmation = false
    @State private var providerPendingRemoval: Provider?

    private var isEditing: Bool { editingID != nil }
    private var isEditingProvider: Bool { editingProviderID != nil }
    /// While any editor (provider or model) is open we lock the list cards so the user
    /// finishes or cancels the current edit before starting another action.
    private var isAnyEditorOpen: Bool { showingProviderEditor || showingModelEditor }
    private var isAtModelLimit: Bool { models.count >= CustomModelStore.maxModels }

    /// True when a provider has a non-empty fetched-model list ready for "Add model".
    private func hasFetchedModels(for provider: Provider) -> Bool {
        !(fetchedModels[provider.id]?.isEmpty ?? true)
    }

    private func addModelDisabledReason(for provider: Provider) -> String? {
        if isAtModelLimit {
            return "Maximum of \(CustomModelStore.maxModels) custom models reached. Remove a model first."
        }
        if !hasFetchedModels(for: provider) {
            return "Fetch models from this provider first."
        }
        return nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    reasoningEffortCard
                    providerTemplatesCard
                    if showingProviderEditor {
                        providerEditorCard
                            .id(providerEditorAnchor)
                            .padding(.horizontal, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    yourProvidersCard
                    if showingModelEditor {
                        editorCard
                            .id(modelEditorAnchor)
                            .padding(.horizontal, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    modelListCard
                }
                .animation(.easeInOut(duration: 0.2), value: showingProviderEditor)
                .animation(.easeInOut(duration: 0.2), value: showingModelEditor)
                .animation(.easeInOut(duration: 0.2), value: showingProviderTemplates)
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: .top)
                }
                scrollTarget = nil
            }
        }
        .task { reload() }
        .alert("Remove Model?", isPresented: $showModelRemovalConfirmation) {
            Button("Cancel", role: .cancel) {
                modelPendingRemoval = nil
            }
            Button("Remove", role: .destructive) {
                if let model = modelPendingRemoval {
                    remove(model)
                }
                modelPendingRemoval = nil
            }
        } message: {
            if let model = modelPendingRemoval {
                let label = model.name.isEmpty ? model.id : model.name
                Text("Remove \(label) from ~/.grok/config.toml? You won't be able to use /model \(model.id) until you add it again.")
            }
        }
        .alert("Remove Provider?", isPresented: $showProviderRemovalConfirmation) {
            Button("Cancel", role: .cancel) {
                providerPendingRemoval = nil
            }
            Button("Remove", role: .destructive) {
                if let provider = providerPendingRemoval {
                    removeProvider(provider)
                }
                providerPendingRemoval = nil
            }
        } message: {
            if let provider = providerPendingRemoval {
                Text("Remove \(provider.name) from your providers? This cannot be undone.")
            }
        }
    }

    private let providerEditorAnchor = "provider-editor"
    private let modelEditorAnchor = "model-editor"

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "cpu")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text("Custom Models")
                    .font(.title3.weight(.semibold))
                Text("Install a provider (endpoint + API key) once, then add one or more OpenAI-compatible models per provider to ~/.grok/config.toml. Use them with /model <id> in chat.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var reasoningEffortCard: some View {
        settingsCard(title: "Reasoning Effort", systemImage: "brain.head.profile", tint: .purple) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Controls how much “thinking” reasoning models use — higher effort can be slower and use more tokens. In chat, model and effort are saved per project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    Picker("Reasoning effort", selection: $reasoningEffort) {
                        ForEach(ReasoningEffortLevel.menuCases) { level in
                            Text(level.displayName).tag(level.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)

                    Spacer()

                    Button("Apply to Session") {
                        onConfigurationChanged()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Provider templates (catalog)

    /// `true` when a preset has already been installed as one of `providers`.
    private func isPresetInstalled(_ preset: ProviderPreset) -> Bool {
        providers.contains { $0.id == preset.provider.id }
    }

    private var providerTemplatesCard: some View {
        settingsCard(title: "1. Add Provider", systemImage: "square.grid.2x2", tint: .purple) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingProviderTemplates.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showingProviderTemplates ? 90 : 0))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Provider Templates")
                                .font(.subheadline.weight(.semibold))
                            Text("Popular OpenAI-compatible providers. Install one to add it to “Your Providers”, then enter its API key.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Group {
                    if showingProviderTemplates {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 220), spacing: 10, alignment: .top)],
                            alignment: .leading,
                            spacing: 10
                        ) {
                            ForEach(ProviderPreset.allCases) { preset in
                                providerTemplateTile(preset)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Divider()

                    Button {
                        beginNewProvider()
                    } label: {
                        Label("Create custom provider…", systemImage: "plus")
                    }
                    .controlSize(.small)
                }
                .disabled(isAnyEditorOpen)
                .opacity(isAnyEditorOpen ? 0.45 : 1)
            }
        }
    }

    private func providerTemplateTile(_ preset: ProviderPreset) -> some View {
        let template = preset.provider
        let installed = isPresetInstalled(preset)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(preset.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if installed {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                }
            }
            Text(template.baseURL)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            if !template.suggestedModel.isEmpty {
                Text("e.g. \(template.suggestedModel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button(installed ? "Configure" : "Install") { addProviderPreset(preset) }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .tint(installed ? .secondary : .purple)
                .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(installed ? Color.green.opacity(0.4) : Color(nsColor: .separatorColor).opacity(0.6))
        )
    }

    // MARK: - Your providers (installed)

    private var yourProvidersCard: some View {
        settingsCard(title: "2. Your Providers", systemImage: "server.rack", tint: .purple) {
            VStack(alignment: .leading, spacing: 12) {
                if providers.isEmpty {
                    Text("No providers installed yet. Install one from a template above, or create a custom provider.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("A provider holds a base URL and a shared API key. Multiple models can reuse the same provider.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(providers) { provider in
                        providerRow(provider)
                        if provider.id != providers.last?.id { Divider() }
                    }
                }
            }
            .disabled(isAnyEditorOpen)
            .opacity(isAnyEditorOpen ? 0.45 : 1)
        }
    }

    private func providerRow(_ provider: Provider) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(provider.name)
                        .font(.headline)
                    providerKeyBadge(for: provider)
                    let count = models.filter { $0.providerID == provider.id }.count
                    if count > 0 {
                        Text("\(count) model\(count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let fetched = fetchedModels[provider.id] {
                        if fetched.isEmpty {
                            Text("0 available")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else {
                            Text("\(fetched.count) available")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }
                Text(provider.baseURL)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if fetchErrorProviderID == provider.id, let message = fetchErrorMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    let addModelDisabled = addModelDisabledReason(for: provider) != nil
                    Button("Add model") { beginNewModel(forProvider: provider) }
                        .controlSize(.small)
                        .disabled(addModelDisabled)
                        .help(addModelDisabledReason(for: provider) ?? "Add a model from the fetched list.")
                    Button("Edit") { beginEditingProvider(provider) }
                        .controlSize(.small)
                    let inUse = modelsUsing(provider).count
                    Button("Remove", role: .destructive) {
                        providerPendingRemoval = provider
                        showProviderRemovalConfirmation = true
                    }
                        .controlSize(.small)
                        .disabled(inUse > 0)
                        .help(inUse > 0
                            ? "Remove its \(inUse) model\(inUse == 1 ? "" : "s") first before removing this provider."
                            : "Remove this provider.")
                }
                let canFetchProvider = canFetch(baseURL: provider.baseURL, apiKey: provider.apiKey)
                let highlightFetch = !hasFetchedModels(for: provider) && canFetchProvider
                Group {
                    if highlightFetch {
                        Button {
                            fetchModels(for: provider)
                        } label: {
                            if fetchingProviderID == provider.id {
                                HStack(spacing: 5) {
                                    ProgressView().controlSize(.small)
                                    Text("Fetching…")
                                }
                            } else {
                                Label("Fetch models", systemImage: "arrow.down.circle.fill")
                            }
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    } else {
                        Button {
                            fetchModels(for: provider)
                        } label: {
                            if fetchingProviderID == provider.id {
                                HStack(spacing: 5) {
                                    ProgressView().controlSize(.small)
                                    Text("Fetching…")
                                }
                            } else {
                                Label("Fetch models", systemImage: "arrow.down.circle")
                            }
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                    }
                }
                .disabled(
                    fetchingProviderID == provider.id
                    || !canFetchProvider
                )
                .help(highlightFetch
                    ? "Fetch the provider's model list before adding a model."
                    : "Refresh the provider's model list.")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func providerKeyBadge(for provider: Provider) -> some View {
        if provider.hasInlineKey {
            badge("Key saved", color: .green, systemImage: "key.fill")
        } else if provider.isLocalEndpoint {
            badge("Local", color: .blue, systemImage: "desktopcomputer")
        } else {
            badge("No key", color: .orange, systemImage: "exclamationmark.triangle")
        }
    }

    private var providerEditorTitle: String {
        if isEditingProvider { return "Edit Provider" }
        if providerDraftFromPreset { return "Install \(providerDraft.name)" }
        return "Add New Provider"
    }

    /// True when the provider needs a key but none is set yet (drives the "enter your key" prompt).
    private var providerNeedsKey: Bool {
        !providerDraft.isLocalEndpoint
            && providerDraft.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var providerEditorCard: some View {
        settingsCard(title: providerEditorTitle, systemImage: "plus.square.on.square", tint: .purple) {
            VStack(alignment: .leading, spacing: 12) {
                if providerDraftFromPreset && providerNeedsKey {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.orange)
                        Text("Enter your \(providerDraft.name) API key, then tap **Add Provider** to install it. Nothing is saved until you do.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
                }

                settingRow("Provider id") {
                    TextField("openai", text: $providerDraft.id)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isEditingProvider || providerDraftFromPreset)
                        .frame(maxWidth: 280)
                }
                settingRow("Name") {
                    TextField("ChatGPT (OpenAI)", text: $providerDraft.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }
                settingRow("Base URL") {
                    TextField("https://api.openai.com/v1", text: $providerDraft.baseURL)
                        .textFieldStyle(.roundedBorder)
                }
                settingRow("API key") {
                    HStack(spacing: 8) {
                        Group {
                            if revealProviderKey {
                                TextField("sk-… (leave empty for local servers)", text: $providerDraft.apiKey)
                            } else {
                                SecureField("sk-… (leave empty for local servers)", text: $providerDraft.apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        Button {
                            revealProviderKey.toggle()
                        } label: {
                            Image(systemName: revealProviderKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Text("The API key is shared by every model using this provider and is written into each model's config.toml table (plain text on disk). Local/open servers don't need a key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                providerFetchRow

                HStack(spacing: 10) {
                    Button(isEditingProvider ? "Save Provider" : "Add Provider") { saveProviderDraft() }
                        .buttonStyle(.borderedProminent)
                        .disabled(providerDraft.validationError != nil)
                    Button("Cancel") { resetProviderDraft() }
                    Spacer()
                    if let error = providerDraft.validationError, !providerDraft.id.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    /// "Fetch models" control + result/error summary inside the provider editor.
    @ViewBuilder
    private var providerFetchRow: some View {
        let draftKey = providerDraft.id.isEmpty ? "__draft__" : providerDraft.id
        let isFetching = fetchingProviderID == draftKey
        let fetched = fetchedModels[draftKey] ?? []
        let canFetchNow = canFetch(
            baseURL: providerDraft.baseURL,
            apiKey: providerDraft.apiKey
        )

        Divider()

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    fetchModelsForDraft()
                } label: {
                    if isFetching {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Fetching…")
                        }
                    } else {
                        Label("Fetch models", systemImage: "arrow.down.circle")
                    }
                }
                .controlSize(.small)
                .disabled(!canFetchNow || isFetching)

                if !fetched.isEmpty {
                    Text("\(fetched.count) model\(fetched.count == 1 ? "" : "s") available")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Text("Queries \(ProviderModelFetcher.modelsURL(for: providerDraft.baseURL)?.absoluteString ?? "the provider")/… to list available models. Enter the API key first (local servers need none).")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if fetchErrorProviderID == draftKey, let message = fetchErrorMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            if !fetched.isEmpty {
                Text("Tip: Save this provider, then use “Add model” to pick from the fetched list.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Model list

    private var modelListCard: some View {
        settingsCard(title: "3. Models", systemImage: "list.bullet.rectangle", tint: .purple) {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(models.count)/\(CustomModelStore.maxModels) custom models")
                    .font(.caption)
                    .foregroundStyle(isAtModelLimit ? .orange : .secondary)

                Group {
                    if models.isEmpty {
                        Text("No models yet. Use “Add model” on a provider above.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(models) { model in
                            modelRow(model)
                            if model.id != models.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .disabled(isAnyEditorOpen)
                .opacity(isAnyEditorOpen ? 0.45 : 1)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func modelRow(_ model: CustomModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name.isEmpty ? model.id : model.name)
                    .font(.headline)
                Text("/model \(model.id)  ·  \(model.model)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(model.baseURL)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 6) {
                Button("Edit") { beginEditing(model) }
                    .controlSize(.small)
                Button("Remove", role: .destructive) {
                    modelPendingRemoval = model
                    showModelRemovalConfirmation = true
                }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func badge(_ text: String, color: Color, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }

    // MARK: - Editor

    private var editorCard: some View {
        settingsCard(title: isEditing ? "Edit Model" : "Add Model", systemImage: "plus.rectangle.on.rectangle", tint: .purple) {
            VStack(alignment: .leading, spacing: 12) {
                settingRow("Provider") {
                    Picker("", selection: providerSelection) {
                        Text("None (enter endpoint manually)").tag("")
                        ForEach(providers) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                    .disabled(providers.isEmpty)
                }

                if let provider = providers.first(where: { $0.id == draft.providerID }) {
                    settingRow("") {
                        HStack(spacing: 8) {
                            Button {
                                fetchModels(for: provider)
                            } label: {
                                if fetchingProviderID == provider.id {
                                    HStack(spacing: 5) {
                                        ProgressView().controlSize(.small)
                                        Text("Fetching…")
                                    }
                                } else {
                                    Label("Fetch models from \(provider.name)", systemImage: "arrow.down.circle")
                                }
                            }
                            .controlSize(.small)
                            .disabled(
                                fetchingProviderID == provider.id
                                || !canFetch(baseURL: provider.baseURL, apiKey: provider.apiKey)
                            )
                            if fetchErrorProviderID == provider.id, let message = fetchErrorMessage {
                                Text(message)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    settingRow("Choose model") {
                        HStack(spacing: 8) {
                            Picker("", selection: fetchedModelSelection) {
                                Text(fetchedModelsForDraft.isEmpty ? "Fetch models first…" : "Pick a fetched model…").tag("")
                                ForEach(fetchedModelsForDraft) { fetched in
                                    Text(fetched.id).tag(fetched.id)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 280)
                            .disabled(fetchedModelsForDraft.isEmpty)
                            if !fetchedModelsForDraft.isEmpty {
                                Text("\(fetchedModelsForDraft.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                settingRow("Model id") {
                    TextField(modelIDPlaceholder, text: $draft.id)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                        .frame(maxWidth: 280)
                }
                settingRow("Model") {
                    TextField(modelNamePlaceholder, text: $draft.model)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .onChange(of: draft.model) { _, newValue in
                            guard !isEditing else { return }
                            syncModelID(from: newValue)
                        }
                }
                settingRow("Display name") {
                    TextField(displayNamePlaceholder, text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }

                if draft.providerID == nil {
                    // Manual endpoint + credential when not linked to a provider.
                    settingRow("Base URL") {
                        TextField("https://api.example.com/v1", text: $draft.baseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    settingRow("API key") {
                        HStack(spacing: 8) {
                            Group {
                                if revealKey {
                                    TextField("sk-… (leave empty for local servers)", text: $draft.apiKey)
                                } else {
                                    SecureField("sk-… (leave empty for local servers)", text: $draft.apiKey)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                            Button {
                                revealKey.toggle()
                            } label: {
                                Image(systemName: revealKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .help(revealKey ? "Hide API key" : "Show API key")
                        }
                    }
                    Text("Stored as api_key in ~/.grok/config.toml (plain text on disk). Local/open servers don't need a key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let provider = providers.first(where: { $0.id == draft.providerID }) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                        Text("Endpoint and key come from \(provider.name) (\(provider.baseURL)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                HStack(spacing: 10) {
                    Button(isEditing ? "Save Changes" : "Add Model") { saveDraft() }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftSaveBlockedReason != nil)
                    Button("Cancel") { resetDraft() }
                    Spacer()
                    if let error = draftSaveBlockedReason, !draft.model.isEmpty || !draft.id.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    /// The draft with provider endpoint/credentials applied, used for validation and preview.
    private var resolvedDraft: CustomModel {
        draft.resolved(using: providers)
    }

    /// Binding for the fetched-model picker. Selecting an id fills the model name and derives
    /// the config.toml model id from it.
    private var fetchedModelSelection: Binding<String> {
        Binding(
            get: {
                let current = draft.model.trimmingCharacters(in: .whitespaces)
                return fetchedModelsForDraft.contains(where: { $0.id == current }) ? current : ""
            },
            set: { newValue in
                guard !isEditing else {
                    if !newValue.isEmpty { draft.model = newValue }
                    return
                }
                if newValue.isEmpty {
                    draft.model = ""
                    draft.id = ""
                    draft.name = ""
                    return
                }
                draft.model = newValue
                syncModelID(from: newValue)
            }
        )
    }

    /// Derives `draft.id` from a provider model name, uniquifying against existing models.
    private func syncModelID(from modelName: String) {
        let base = CustomModel.suggestedID(from: modelName)
        draft.id = uniquifiedModelID(base)
    }

    /// Returns a model id that does not collide with an existing entry (unless editing that entry).
    private func uniquifiedModelID(_ base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        var candidate = trimmed
        var suffix = 2
        while models.contains(where: { $0.id == candidate && $0.id != editingID }) {
            candidate = "\(trimmed)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    /// Validation for the save button, including duplicate-id checks when adding a new model.
    private var draftSaveBlockedReason: String? {
        if let error = resolvedDraft.validationError { return error }
        if !isEditing, models.count >= CustomModelStore.maxModels {
            return "GrokBuild supports up to \(CustomModelStore.maxModels) custom models."
        }
        if !isEditing, models.contains(where: { $0.id == draft.id }) {
            return "A model with this id already exists."
        }
        return nil
    }

    /// Binding that maps the model's optional providerID to the picker's string tag.
    private var providerSelection: Binding<String> {
        Binding(
            get: { draft.providerID ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    draft.providerID = nil
                } else {
                    draft.providerID = newValue
                    if !isEditing {
                        draft.model = ""
                        draft.id = ""
                        draft.name = ""
                    }
                }
            }
        )
    }

    // MARK: - Actions

    private func reload() {
        providers = ProviderStore.load()
        let snapshot = CustomModelStore.load()
        // Re-attach providerID to parsed models by matching their base_url to a known provider,
        // since config.toml itself doesn't store the provider link. Then re-resolve the
        // endpoint/credential from the provider so a model reflects a key added to its provider
        // even if its own config.toml table predates that key.
        models = snapshot.models.map { model in
            var m = model
            if m.providerID == nil,
               let match = providers.first(where: { $0.baseURL == model.baseURL }) {
                m.providerID = match.id
            }
            return m.resolved(using: providers)
        }
    }

    // MARK: - Provider actions

    /// Installing a template stages it in the editor (key empty) instead of persisting it
    /// immediately — the provider is only saved once the user enters a key and taps Save.
    /// If the preset is already installed, jump to editing the existing one.
    private func addProviderPreset(_ preset: ProviderPreset) {
        if let existing = providers.first(where: { $0.id == preset.provider.id }) {
            beginEditingProvider(existing)
            return
        }
        providerDraft = preset.provider
        editingProviderID = nil
        providerDraftFromPreset = true
        revealProviderKey = false
        showingProviderEditor = true
        showingModelEditor = false
        scrollTarget = providerEditorAnchor
    }

    private func beginNewProvider() {
        providerDraft = Provider(id: "", name: "", baseURL: "")
        editingProviderID = nil
        providerDraftFromPreset = false
        revealProviderKey = false
        showingProviderEditor = true
        showingModelEditor = false
        scrollTarget = providerEditorAnchor
    }

    private func beginEditingProvider(_ provider: Provider) {
        providerDraft = provider
        editingProviderID = provider.id
        providerDraftFromPreset = false
        revealProviderKey = false
        showingProviderEditor = true
        showingModelEditor = false
        scrollTarget = providerEditorAnchor
    }

    private func resetProviderDraft() {
        providerDraft = Provider(id: "", name: "", baseURL: "")
        editingProviderID = nil
        providerDraftFromPreset = false
        revealProviderKey = false
        showingProviderEditor = false
    }

    private func saveProviderDraft() {
        guard providerDraft.validationError == nil else { return }
        if let editingProviderID, let index = providers.firstIndex(where: { $0.id == editingProviderID }) {
            providers[index] = providerDraft
            // Propagate endpoint/credential changes to models linked to this provider.
            models = models.map { $0.providerID == editingProviderID ? $0.resolved(using: providers) : $0 }
        } else if let index = providers.firstIndex(where: { $0.id == providerDraft.id }) {
            providers[index] = providerDraft
        } else {
            providers.append(providerDraft)
        }
        ProviderStore.save(providers)
        resetProviderDraft()
        persist()
    }

    /// Models currently attached to (in use by) the given provider.
    private func modelsUsing(_ provider: Provider) -> [CustomModel] {
        models.filter { $0.providerID == provider.id }
    }

    private func removeProvider(_ provider: Provider) {
        // A provider can only be removed once none of its models reference it, so the
        // user explicitly removes the models first and we never orphan config.toml tables.
        guard modelsUsing(provider).isEmpty else { return }
        providers.removeAll { $0.id == provider.id }
        ProviderStore.save(providers)
        if editingProviderID == provider.id { resetProviderDraft() }
        fetchedModels[provider.id] = nil
        persist()
    }

    // MARK: - Fetch models

    /// Fetches the model catalog for the provider draft currently being edited/created.
    private func fetchModelsForDraft() {
        let draftSnapshot = providerDraft
        guard !draftSnapshot.baseURL.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        fetchModels(
            forProviderID: draftSnapshot.id,
            baseURL: draftSnapshot.baseURL,
            apiKey: draftSnapshot.apiKey
        )
    }

    /// Fetches the model catalog for an already-installed provider.
    private func fetchModels(for provider: Provider) {
        fetchModels(
            forProviderID: provider.id,
            baseURL: provider.baseURL,
            apiKey: provider.apiKey
        )
    }

    private func fetchModels(forProviderID id: String, baseURL: String, apiKey: String) {
        let key = id.isEmpty ? "__draft__" : id
        fetchingProviderID = key
        fetchErrorProviderID = nil
        fetchErrorMessage = nil
        Task {
            do {
                let result = try await ProviderModelFetcher.fetch(baseURL: baseURL, apiKey: apiKey)
                await MainActor.run {
                    fetchedModels[key] = result
                    fetchingProviderID = nil
                }
            } catch {
                await MainActor.run {
                    fetchingProviderID = nil
                    fetchErrorProviderID = key
                    fetchErrorMessage = (error as? ProviderModelFetcher.FetchError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }

    /// Models fetched for the provider linked to the current model draft, if any.
    private var fetchedModelsForDraft: [FetchedModel] {
        guard let id = draft.providerID else { return [] }
        return fetchedModels[id] ?? []
    }

    private func canFetch(baseURL: String, apiKey: String) -> Bool {
        guard ProviderModelFetcher.modelsURL(for: baseURL) != nil else { return false }
        let isLocal = Provider(id: "", name: "", baseURL: baseURL).isLocalEndpoint
        // Local servers accept no key; remote ones need an inline key.
        if isLocal { return true }
        return ProviderModelFetcher.resolveKey(apiKey: apiKey) != nil
    }

    // MARK: - Model actions

    private func beginNewModel(forProvider provider: Provider) {
        guard addModelDisabledReason(for: provider) == nil else { return }
        draft = CustomModel(
            id: "",
            model: "",
            baseURL: "",
            providerID: provider.id
        )
        editingID = nil
        revealKey = false
        errorMessage = nil
        showingModelEditor = true
        showingProviderEditor = false
        scrollTarget = modelEditorAnchor
    }

    /// Opens the model editor for a brand-new manual model (no provider preselected).
    private func beginNewModel() {
        draft = freshModelDraft()
        editingID = nil
        revealKey = false
        errorMessage = nil
        showingModelEditor = true
        showingProviderEditor = false
        scrollTarget = modelEditorAnchor
    }

    private func beginEditing(_ model: CustomModel) {
        draft = model
        editingID = model.id
        revealKey = false
        errorMessage = nil
        showingModelEditor = true
        showingProviderEditor = false
        scrollTarget = modelEditorAnchor
    }

    private func resetDraft() {
        draft = freshModelDraft()
        editingID = nil
        revealKey = false
        showingModelEditor = false
    }

    /// A blank model draft that defaults to the first provider (if any) so the endpoint is
    /// inherited and the manual base_url/key fields stay hidden. Prefills the provider's
    /// suggested starting model.
    private func freshModelDraft() -> CustomModel {
        if let provider = providers.first {
            return CustomModel(
                id: "",
                model: "",
                baseURL: "",
                providerID: provider.id
            )
        }
        return CustomModel(id: "", model: "", baseURL: "")
    }

    /// The provider currently linked to the model draft, if any.
    private var draftProvider: Provider? {
        guard let id = draft.providerID else { return nil }
        return providers.first { $0.id == id }
    }

    private var modelIDPlaceholder: String {
        let trimmed = draft.model.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return CustomModel.suggestedID(from: trimmed)
        }
        return "my-model-id"
    }

    private var modelNamePlaceholder: String {
        if draftProvider != nil {
            return "Pick a model above"
        }
        return "provider-model-name"
    }

    private var displayNamePlaceholder: String {
        let trimmed = draft.model.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return "\(trimmed) (optional)"
        }
        return "Display name (optional)"
    }

    private func saveDraft() {
        guard draftSaveBlockedReason == nil else { return }
        var updated = models
        if let editingID, let index = updated.firstIndex(where: { $0.id == editingID }) {
            updated[index] = draft
        } else {
            updated.append(draft)
        }
        models = updated
        resetDraft()
        persist()
    }

    private func remove(_ model: CustomModel) {
        models.removeAll { $0.id == model.id }
        if editingID == model.id { resetDraft() }
        persist()
    }

    private func persist() {
        do {
            let resolvedModels = models.map { $0.resolved(using: providers) }
            // The default model is owned by grok itself (it rewrites [models].default
            // when you switch models in a session), so we never set it here — we just
            // preserve whatever is already in config.toml.
            let snapshot = CustomModelStore.load()
            try CustomModelStore.save(models: resolvedModels, defaultModelID: snapshot.defaultModelID)
            statusMessage = "Saved to ~/.grok/config.toml."
            errorMessage = nil
            onConfigurationChanged()
        } catch {
            errorMessage = "Failed to save config.toml: \(error.localizedDescription)"
            statusMessage = nil
        }
    }

    // MARK: - Card / row helpers

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint ?? .primary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(tint.map { $0.opacity(0.07) } ?? Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.map { $0.opacity(0.22) } ?? Color(nsColor: .separatorColor).opacity(0.6)))
    }

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct MCPSettingsPane: View {
    let onConfigurationChanged: () -> Void

    private let service = GrokCLIService()
    @State private var servers: [GrokMCPServerInfo] = []
    @State private var doctorReport: GrokMCPDoctorReport?
    @State private var name = ""
    @State private var transport = "stdio"
    @State private var target = ""
    @State private var scope = "user"
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                settingsPaneHeader(
                    "MCP Servers",
                    subtitle: "Configure external Model Context Protocol servers and run health checks.",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    color: .teal
                )
                Button("Run Doctor") {
                    Task { await runDoctor() }
                }
                Button("Refresh") {
                    Task { await refresh() }
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    TextField("Name", text: $name)
                    Picker("Transport", selection: $transport) {
                        Text("stdio").tag("stdio")
                        Text("http").tag("http")
                        Text("sse").tag("sse")
                    }
                    .labelsHidden()
                    Picker("Scope", selection: $scope) {
                        Text("User").tag("user")
                        Text("Project").tag("project")
                    }
                    .labelsHidden()
                }
                GridRow {
                    TextField(transport == "stdio" ? "Command and args" : "URL", text: $target)
                        .gridCellColumns(2)
                    Button("Add / Update") {
                        Task { await addServer() }
                    }
                    .disabled(name.isEmpty || target.isEmpty)
                }
            }

            List {
                ForEach(servers) { server in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(server.name)
                                .font(.headline)
                            Text([server.transport, server.source].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !server.target.isEmpty {
                                Text(server.target)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer()
                        Button("Doctor") {
                            Task { await runDoctor(name: server.name) }
                        }
                        Button("Remove", role: .destructive) {
                            Task { await removeServer(server) }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .overlay {
                if servers.isEmpty && !isLoading {
                    ContentUnavailableView("No User MCP Servers", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Doctor can still show managed, Claude, Cursor, and project MCP servers."))
                }
            }

            if let doctorReport {
                Divider()
                Text("Doctor: \(doctorReport.healthyCount) healthy, \(doctorReport.failingCount) failing")
                    .font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(doctorReport.servers) { server in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Circle()
                                        .fill(server.healthy ? .green : .red)
                                        .frame(width: 8, height: 8)
                                    Text(server.name)
                                        .font(.headline)
                                    Spacer()
                                    Text(server.source)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(server.checks, id: \.self) { check in
                                    HStack(alignment: .top) {
                                        Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(check.passed ? .green : .red)
                                        VStack(alignment: .leading) {
                                            Text(check.label)
                                            if !check.detail.isEmpty {
                                                Text(check.detail)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if !check.hint.isEmpty {
                                                Text(check.hint)
                                                    .font(.caption)
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            if isLoading { ProgressView() }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .task { await refresh() }
    }

    private func header(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
    }

    private func refresh() async {
        await perform {
            servers = try await service.listMCPServers()
        }
    }

    private func runDoctor(name: String? = nil) async {
        await perform {
            doctorReport = try await service.mcpDoctor(name: name)
        }
    }

    private func addServer() async {
        await perform {
            try await service.addMCPServer(name: name, transport: transport, target: target, scope: scope)
            name = ""
            target = ""
            servers = try await service.listMCPServers()
            onConfigurationChanged()
        }
    }

    private func removeServer(_ server: GrokMCPServerInfo) async {
        await perform {
            try await service.removeMCPServer(name: server.name)
            servers = try await service.listMCPServers()
            onConfigurationChanged()
        }
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct PermissionsSettingsPane: View {
    let onConfigurationChanged: () -> Void

    @AppStorage(GrokSettingsKeys.permissionMode) private var permissionMode = GrokPermissionSettings.defaults.permissionMode
    @AppStorage(GrokSettingsKeys.sandboxProfile) private var sandboxProfile = GrokPermissionSettings.defaults.sandboxProfile
    @AppStorage(GrokSettingsKeys.reasoningEffort) private var reasoningEffort = GrokPermissionSettings.defaults.reasoningEffort
    @AppStorage(GrokSettingsKeys.noMemory) private var noMemory = GrokPermissionSettings.defaults.noMemory
    @AppStorage(GrokSettingsKeys.disableWebSearch) private var disableWebSearch = GrokPermissionSettings.defaults.disableWebSearch
    @AppStorage(GrokSettingsKeys.noSubagents) private var noSubagents = GrokPermissionSettings.defaults.noSubagents
    @AppStorage(GrokSettingsKeys.allowRules) private var allowRules = GrokPermissionSettings.defaults.allowRules
    @AppStorage(GrokSettingsKeys.denyRules) private var denyRules = GrokPermissionSettings.defaults.denyRules

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                launchFlagsCard
                safetyTogglesCard
                permissionRulesCard
                applyCard
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text("Permissions")
                    .font(.title3.weight(.semibold))
                Text("Tune Grok launch flags, sandbox behavior, and explicit allow/deny rules for tool use.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(permissionModeLabel)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.purple.opacity(0.14)))
                .foregroundStyle(.purple)
        }
    }

    private var launchFlagsCard: some View {
        settingsCard(title: "Launch Behavior", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 14) {
                settingRow("Permission mode", description: "Controls how often Grok asks before running tools.") {
                    Picker("", selection: $permissionMode) {
                        Text("Default").tag("default")
                        Text("Accept edits").tag("acceptEdits")
                        Text("Auto").tag("auto")
                        Text("Don't ask").tag("dontAsk")
                        Text("Bypass permissions").tag("bypassPermissions")
                        Text("Plan").tag("plan")
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                settingRow("Sandbox", description: "Limits file system and command access for Grok.") {
                    Picker("", selection: $sandboxProfile) {
                        Text("Default").tag("")
                        Text("Workspace").tag("workspace")
                        Text("Read-only").tag("read-only")
                        Text("Strict").tag("strict")
                        Text("Devbox").tag("devbox")
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                settingRow("Reasoning effort", description: "Chooses the reasoning budget passed to `grok agent`.") {
                    Picker("", selection: $reasoningEffort) {
                        ForEach(ReasoningEffortLevel.menuCases) { level in
                            Text(level.displayName).tag(level.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }
        }
    }

    private var safetyTogglesCard: some View {
        settingsCard(title: "Session Capabilities", systemImage: "switch.2") {
            VStack(alignment: .leading, spacing: 12) {
                permissionToggle("Disable memory for new sessions", subtitle: "Start new sessions without using saved Grok memory.", isOn: $noMemory)
                Divider()
                permissionToggle("Disable web search tools", subtitle: "Prevent Grok from using web search in new sessions.", isOn: $disableWebSearch)
                Divider()
                permissionToggle("Disable subagents", subtitle: "Keep work inside the main Grok agent only.", isOn: $noSubagents)
            }
        }
    }

    private var permissionRulesCard: some View {
        settingsCard(title: "Permission Rules", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Enter one `--allow` or `--deny` rule per line, for example `Bash(npm*)` or `Edit(/etc/**)`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 14) {
                    ruleEditor(title: "Allow Rules", text: $allowRules, tint: .green)
                    ruleEditor(title: "Deny Rules", text: $denyRules, tint: .red)
                }
            }
        }
    }

    private var applyCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Apply changes")
                    .font(.headline)
                Text("Restart the Grok connection so permission flags and rules are used by the active session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Apply and Restart Grok") {
                onConfigurationChanged()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.purple.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.purple.opacity(0.18)))
    }

    private var permissionModeLabel: String {
        switch permissionMode {
        case "acceptEdits": return "Accept edits"
        case "auto": return "Auto"
        case "dontAsk": return "Don't ask"
        case "bypassPermissions": return "Bypass"
        case "plan": return "Plan"
        default: return "Default"
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(nsColor: .separatorColor).opacity(0.6)))
    }

    private func settingRow<Content: View>(
        _ title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 330, alignment: .leading)

            Spacer()
            content()
        }
    }

    private func permissionToggle(_ title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    private func ruleEditor(title: String, text: Binding<String>, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.callout.weight(.medium))
            }
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 130)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.25)))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AppUpdatesSettingsPane: View {
    private var autoCheckBinding: Binding<Bool> {
        Binding(
            get: { UpdateSettingsStore.autoCheckEnabled },
            set: { UpdateSettingsStore.autoCheckEnabled = $0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsPaneHeader(
                    title: "App Updates",
                    subtitle: "GrokBuild checks GitHub releases for signed builds and can install updates in one click.",
                    systemImage: "arrow.triangle.2.circlepath",
                    color: .blue
                )

                updatesCard(title: "Installed Version", systemImage: "info.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppVersion.display)
                            .font(.body.monospaced())
                        if let lastCheck = UpdateSettingsStore.lastCheckDate {
                            Text("Last checked \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not checked yet this session.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                updatesCard(title: "Automatic Checks", systemImage: "clock.arrow.circlepath") {
                    Toggle(isOn: autoCheckBinding) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Automatically check for updates")
                                .font(.callout.weight(.medium))
                            Text("Checks on launch and about once per day while GrokBuild is running.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                updatesCard(title: "grok CLI", systemImage: "terminal") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let cli = UpdateScheduler.cachedCLIStatus {
                            switch cli.state {
                            case .upToDate(let info), .updateAvailable(let info):
                                Text("Installed: \(info.current)")
                                    .font(.body.monospaced())
                                Text("Latest: \(info.latest)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let channel = info.channel, !channel.isEmpty {
                                    Text("Channel: \(channel)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            case .notInstalled:
                                Text("Not installed")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            case .checkFailed(let message):
                                Text("Could not check: \(message)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Not checked yet this session.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if UpdateScheduler.hasActionableCLIUpdate,
                           let latest = UpdateScheduler.cachedCLIStatus?.latestVersion {
                            Text("grok CLI \(latest) is ready to update.")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                updatesCard(title: "Manual Check", systemImage: "arrow.down.circle") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("When updates are available, use the main-window banner or Check for Updates… in the menu bar, then click Updates Available to review GrokBuild and grok CLI versions.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if UpdateScheduler.hasActionableAppUpdate,
                           let release = UpdateScheduler.cachedAppRelease {
                            Text("GrokBuild \(release.latestVersion) is ready to install.")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func updatesCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(nsColor: .separatorColor).opacity(0.6)))
    }
}
