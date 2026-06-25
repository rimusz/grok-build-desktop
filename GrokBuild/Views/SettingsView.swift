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
    case permissions
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
                    .tabItem {
                        Label("Hooks", systemImage: "curlybraces")
                    }
                    .tag(SettingsTab.hooks)

                PluginsSettingsPane {
                    Task { await store.reloadConfiguration() }
                }
                .tabItem {
                    Label("Plugins", systemImage: "shippingbox")
                }
                .tag(SettingsTab.plugins)

                MarketplaceSettingsPane {
                    Task { await store.reloadConfiguration() }
                }
                .tabItem {
                    Label("Marketplace", systemImage: "storefront")
                }
                .tag(SettingsTab.marketplace)

                SkillsSettingsPane(workspace: store.currentWorkspace)
                    .tabItem {
                        Label("Skills", systemImage: "wand.and.stars")
                    }
                    .tag(SettingsTab.skills)

                MCPSettingsPane {
                    Task { await store.reloadConfiguration() }
                }
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
                    Label("Computer Use", systemImage: "display")
                }
                .tag(SettingsTab.computerUse)

                PermissionsSettingsPane {
                    Task { await store.reloadConfiguration() }
                }
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
                .tag(SettingsTab.permissions)
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
                installCard
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
                    Picker("", selection: $backend) {
                        ForEach(BrowserBackendID.allCases) { backend in
                            Text(backend.displayName).tag(backend.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }

                Text("For the normal setup, leave the browser runtime choice below on Managed Runtime and click Apply after enabling tools. GrokBuild will also install a small browser-control skill into your Grok skills folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusCard: some View {
        settingsCard(title: "Backend Status", systemImage: "checkmark.seal", tint: browserStatusColor) {
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

    private var installCard: some View {
        settingsCard(title: status.isReady ? "2. agent-browser Ready" : "2. Install agent-browser CLI", systemImage: status.isReady ? "checkmark.circle" : "arrow.down.circle", tint: installCardTint) {
            VStack(alignment: .leading, spacing: 12) {
                if status.isReady {
                    Label("agent-browser is installed and diagnostics passed.", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)

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

                Text("GrokBuild never installs this silently. Use these buttons only when you want to set up browser automation on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
    @AppStorage(ComputerUseSettingsKeys.agentDesktopPath) private var agentDesktopPath = ComputerUseSettings.defaults.agentDesktopPath
    @AppStorage(ComputerUseSettingsKeys.permissionPolicy) private var permissionPolicy = ComputerUseSettings.defaults.permissionPolicy.rawValue
    @AppStorage(ComputerUseSettingsKeys.maxSteps) private var maxSteps = ComputerUseSettings.defaults.maxSteps
    @AppStorage(ComputerUseSettingsKeys.commandTimeoutSeconds) private var commandTimeoutSeconds = ComputerUseSettings.defaults.commandTimeoutSeconds
    @AppStorage(ComputerUseSettingsKeys.screenshotMode) private var screenshotMode = ComputerUseSettings.defaults.screenshotMode.rawValue
    @AppStorage(ComputerUseSettingsKeys.includeScreenshots) private var includeScreenshots = ComputerUseSettings.defaults.includeScreenshots
    @AppStorage(ComputerUseSettingsKeys.allowPhysicalMouse) private var allowPhysicalMouse = ComputerUseSettings.defaults.allowPhysicalMouse
    @AppStorage(ComputerUseSettingsKeys.sessionName) private var sessionName = ComputerUseSettings.defaults.sessionName

    @State private var backendStatus = ComputerUseBackendStatus.unavailable
    @State private var permissionStatus = ComputerUsePermissionStatus.unavailable
    @State private var appliedSettings = ComputerUseSettingsStore.loadApplied()
    @State private var isChecking = false
    @State private var isInstalling = false
    @State private var isRequestingPermissions = false
    @State private var installOutput: String?
    @State private var permissionOutput: String?
    @State private var showDiagnosticsLog = false
    @State private var showPermissionDiagnostics = false
    @State private var showAdvancedOptions = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                enableCard
                statusCard
                installCard
                permissionsCard
                safetyCard
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
        }
        .onChange(of: agentDesktopPath) { _, _ in
            Task { await refreshStatus() }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "display.badge.checkmark")
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

                Divider()

                settingRow("Backend") {
                    Picker("", selection: $backend) {
                        ForEach(ComputerUseBackendID.allCases) { backend in
                            Text(backend.displayName).tag(backend.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }

                Text("For the normal setup, install agent-desktop, grant Accessibility permission, then click Apply after enabling tools. GrokBuild will also install a small Computer Use skill into your Grok skills folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusCard: some View {
        computerSettingsCard(title: "Backend Status", systemImage: "checkmark.seal", tint: backendStatusColor) {
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

    private var installCard: some View {
        computerSettingsCard(title: backendStatus.isInstalled ? "2. agent-desktop Ready" : "2. Install agent-desktop CLI", systemImage: backendStatus.isInstalled ? "checkmark.circle" : "arrow.down.circle", tint: installCardTint) {
            VStack(alignment: .leading, spacing: 12) {
                if backendStatus.isInstalled {
                    Label("agent-desktop is installed and available.", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)

                    Text("The required local CLI is available. Grant macOS permissions below, then enable and apply Computer Use.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("GrokBuild needs the local `agent-desktop` CLI to expose desktop-control tools. It is never installed silently.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        installCommandRow(title: "npm", command: "npm install -g agent-desktop")
                    }
                }

                HStack {
                    Button(isInstalling ? "Installing..." : (backendStatus.isInstalled ? "Reinstall / Repair CLI" : "Install agent-desktop")) {
                        Task { await installAgentDesktop() }
                    }
                    .disabled(isInstalling)

                    Button("Copy Install Command") {
                        copyToPasteboard("npm install -g agent-desktop")
                    }

                    if !agentDesktopPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Clear Custom Path") {
                            agentDesktopPath = ""
                        }
                    }
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

                settingRow("Custom path") {
                    HStack {
                        TextField("Optional path to agent-desktop", text: $agentDesktopPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose...") { chooseAgentDesktop() }
                    }
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
                        Stepper("Command timeout: \(commandTimeoutSeconds)s", value: $commandTimeoutSeconds, in: 5...180, step: 5)
                        settingRow("Session name") {
                            TextField("Optional Computer Use session name", text: $sessionName)
                                .textFieldStyle(.roundedBorder)
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

    private var applyCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Apply changes")
                    .font(.headline)
                Text(hasPendingChanges ? "Restart the Grok connection so Computer Use MCP tools are injected into the active session." : "Computer Use settings are already applied to the active configuration.")
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
            agentDesktopPath: agentDesktopPath,
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
        currentSettings != appliedSettings
    }

    private var statusBadge: some View {
        let text = enabled ? (permissionStatus.isReady ? "Ready" : "Setup needed") : "Disabled"
        let color: Color = enabled ? (permissionStatus.isReady ? .green : .orange) : .secondary
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
        ComputerUseSettingsStore.save(settings)
        ComputerUseSettingsStore.saveApplied(settings)
        appliedSettings = settings
        onConfigurationChanged()
    }

    private func refreshStatus() async {
        isChecking = true
        defer { isChecking = false }
        let settings = currentSettings
        async let status = ComputerUseService.status(settings: settings)
        async let permissions = ComputerUseService.permissionStatus(settings: settings)
        backendStatus = await status
        permissionStatus = await permissions
    }

    private func installAgentDesktop() async {
        isInstalling = true
        installOutput = "Running `npm install -g agent-desktop`..."
        defer { isInstalling = false }

        do {
            let output = try await ComputerUseService.installAgentDesktop()
            installOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            await refreshStatus()
        } catch {
            installOutput = error.localizedDescription
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

    private func chooseAgentDesktop() {
        let panel = NSOpenPanel()
        panel.title = "Choose agent-desktop"
        panel.message = "Choose the agent-desktop executable."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            agentDesktopPath = url.path
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
                        Text("Default").tag("")
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                        Text("XHigh").tag("xhigh")
                        Text("Max").tag("max")
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
