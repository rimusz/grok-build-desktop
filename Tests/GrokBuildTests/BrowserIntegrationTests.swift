import XCTest
@testable import GrokBuild

final class BrowserIntegrationTests: XCTestCase {
    private var savedEnabled: Any?
    private var savedRuntimeMode: Any?
    private var savedCDPURL: Any?
    private var savedProfileName: Any?
    private var savedShowBrowserWindow: Any?
    private var savedExternalBrowserAppID: Any?
    private var savedExternalBrowserAppPath: Any?
    private var savedAutoStartExternalBrowser: Any?
    private var savedAppliedEnabled: Any?
    private var savedAppliedRuntimeMode: Any?
    private var savedAppliedCDPURL: Any?
    private var savedAppliedProfileName: Any?
    private var savedAppliedShowBrowserWindow: Any?
    private var savedAppliedExternalBrowserAppID: Any?
    private var savedAppliedExternalBrowserAppPath: Any?
    private var savedAppliedAutoStartExternalBrowser: Any?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        savedEnabled = defaults.object(forKey: BrowserSettingsKeys.enabled)
        savedRuntimeMode = defaults.object(forKey: BrowserSettingsKeys.runtimeMode)
        savedCDPURL = defaults.object(forKey: BrowserSettingsKeys.cdpURL)
        savedProfileName = defaults.object(forKey: BrowserSettingsKeys.profileName)
        savedShowBrowserWindow = defaults.object(forKey: BrowserSettingsKeys.showBrowserWindow)
        savedExternalBrowserAppID = defaults.object(forKey: BrowserSettingsKeys.externalBrowserAppID)
        savedExternalBrowserAppPath = defaults.object(forKey: BrowserSettingsKeys.externalBrowserAppPath)
        savedAutoStartExternalBrowser = defaults.object(forKey: BrowserSettingsKeys.autoStartExternalBrowser)
        savedAppliedEnabled = defaults.object(forKey: BrowserSettingsKeys.appliedEnabled)
        savedAppliedRuntimeMode = defaults.object(forKey: BrowserSettingsKeys.appliedRuntimeMode)
        savedAppliedCDPURL = defaults.object(forKey: BrowserSettingsKeys.appliedCDPURL)
        savedAppliedProfileName = defaults.object(forKey: BrowserSettingsKeys.appliedProfileName)
        savedAppliedShowBrowserWindow = defaults.object(forKey: BrowserSettingsKeys.appliedShowBrowserWindow)
        savedAppliedExternalBrowserAppID = defaults.object(forKey: BrowserSettingsKeys.appliedExternalBrowserAppID)
        savedAppliedExternalBrowserAppPath = defaults.object(forKey: BrowserSettingsKeys.appliedExternalBrowserAppPath)
        savedAppliedAutoStartExternalBrowser = defaults.object(forKey: BrowserSettingsKeys.appliedAutoStartExternalBrowser)
    }

    override func tearDown() {
        restore(savedEnabled, forKey: BrowserSettingsKeys.enabled)
        restore(savedRuntimeMode, forKey: BrowserSettingsKeys.runtimeMode)
        restore(savedCDPURL, forKey: BrowserSettingsKeys.cdpURL)
        restore(savedProfileName, forKey: BrowserSettingsKeys.profileName)
        restore(savedShowBrowserWindow, forKey: BrowserSettingsKeys.showBrowserWindow)
        restore(savedExternalBrowserAppID, forKey: BrowserSettingsKeys.externalBrowserAppID)
        restore(savedExternalBrowserAppPath, forKey: BrowserSettingsKeys.externalBrowserAppPath)
        restore(savedAutoStartExternalBrowser, forKey: BrowserSettingsKeys.autoStartExternalBrowser)
        restore(savedAppliedEnabled, forKey: BrowserSettingsKeys.appliedEnabled)
        restore(savedAppliedRuntimeMode, forKey: BrowserSettingsKeys.appliedRuntimeMode)
        restore(savedAppliedCDPURL, forKey: BrowserSettingsKeys.appliedCDPURL)
        restore(savedAppliedProfileName, forKey: BrowserSettingsKeys.appliedProfileName)
        restore(savedAppliedShowBrowserWindow, forKey: BrowserSettingsKeys.appliedShowBrowserWindow)
        restore(savedAppliedExternalBrowserAppID, forKey: BrowserSettingsKeys.appliedExternalBrowserAppID)
        restore(savedAppliedExternalBrowserAppPath, forKey: BrowserSettingsKeys.appliedExternalBrowserAppPath)
        restore(savedAppliedAutoStartExternalBrowser, forKey: BrowserSettingsKeys.appliedAutoStartExternalBrowser)
        super.tearDown()
    }

    func testBrowserSettingsRoundTrip() {
        let settings = BrowserSettings(
            enabled: true,
            runtimeMode: .external,
            cdpURL: "http://127.0.0.1:9222",
            profileName: "project-a",
            showBrowserWindow: true,
            externalBrowserAppID: .brave,
            externalBrowserAppPath: "/Applications/Brave Browser.app",
            autoStartExternalBrowser: false
        )

        BrowserSettingsStore.save(settings)
        XCTAssertEqual(BrowserSettingsStore.load(), settings)
    }

    func testAppliedBrowserSettingsRoundTripSeparately() {
        let current = BrowserSettings(
            enabled: true,
            runtimeMode: .external,
            cdpURL: "http://127.0.0.1:9222",
            profileName: "current",
            showBrowserWindow: true,
            externalBrowserAppID: .edge,
            externalBrowserAppPath: "/Applications/Microsoft Edge.app",
            autoStartExternalBrowser: true
        )
        let applied = BrowserSettings(
            enabled: false,
            runtimeMode: .managed,
            cdpURL: "",
            profileName: "applied",
            showBrowserWindow: false,
            externalBrowserAppID: .arc,
            externalBrowserAppPath: "/Applications/Arc.app",
            autoStartExternalBrowser: false
        )

        BrowserSettingsStore.save(current)
        BrowserSettingsStore.saveApplied(applied)

        XCTAssertEqual(BrowserSettingsStore.load(), current)
        XCTAssertEqual(BrowserSettingsStore.loadApplied(), applied)
    }

    func testMCPServerConfigSerializesForACP() {
        let config = MCPServerConfig(
            name: "grokbuild-browser",
            command: "/tmp/grokbuild-browser-mcp",
            args: ["--stdio"],
            env: ["AGENT_BROWSER_PATH": "/opt/homebrew/bin/agent-browser"]
        )

        let json = config.jsonObject

        XCTAssertEqual(json["name"] as? String, "grokbuild-browser")
        XCTAssertNil(json["type"])
        XCTAssertNil(json["transport"])
        XCTAssertEqual(json["command"] as? String, "/tmp/grokbuild-browser-mcp")
        XCTAssertEqual(json["args"] as? [String], ["--stdio"])

        let env = json["env"] as? [[String: String]]
        XCTAssertEqual(env?.first?["name"], "AGENT_BROWSER_PATH")
        XCTAssertEqual(env?.first?["value"], "/opt/homebrew/bin/agent-browser")
    }

    func testManagedRuntimeStatusTextUsesRuntimeDirectoryNotCLIDoctor() {
        XCTAssertEqual(
            AgentBrowserService.managedRuntimeStatusText(cliInstalled: true, hasRuntime: true),
            "Managed runtime installed and ready"
        )
        XCTAssertEqual(
            AgentBrowserService.managedRuntimeStatusText(cliInstalled: true, hasRuntime: false),
            "Managed runtime not ready or not installed"
        )
        XCTAssertEqual(
            AgentBrowserService.managedRuntimeStatusText(cliInstalled: false, hasRuntime: false),
            "Install agent-browser CLI first"
        )
        XCTAssertEqual(
            AgentBrowserService.managedRuntimeStatusText(cliInstalled: false, hasRuntime: true),
            "Install agent-browser CLI first"
        )
        XCTAssertTrue(AgentBrowserService.managedRuntimeIsReady(cliInstalled: true, hasRuntime: true))
        XCTAssertFalse(AgentBrowserService.managedRuntimeIsReady(cliInstalled: false, hasRuntime: true))
    }

    @MainActor
    func testApplyEnabledLeavesBrowserOffWhenAlreadyOff() async {
        var settings = BrowserSettings.defaults
        settings.enabled = false
        BrowserSettingsStore.save(settings)
        BrowserSettingsStore.saveApplied(settings)

        let result = await AgentBrowserService.applyEnabled(false, settings: settings)
        XCTAssertEqual(result, .unchanged)
        XCTAssertFalse(BrowserSettingsStore.loadApplied().enabled)
    }

    @MainActor
    func testApplyEnabledTurnsBrowserOffWithoutSetup() async {
        var settings = BrowserSettings.defaults
        settings.enabled = true
        BrowserSettingsStore.save(settings)
        BrowserSettingsStore.saveApplied(settings)

        let result = await AgentBrowserService.applyEnabled(false, settings: settings)
        XCTAssertEqual(result, .applied)
        XCTAssertFalse(BrowserSettingsStore.loadApplied().enabled)
        XCTAssertFalse(BrowserSettingsStore.load().enabled)
    }

    @MainActor
    func testApplyEnabledNeedsSetupWhenManagedRuntimeIsMissing() async {
        guard !AgentBrowserService.hasManagedRuntimeDirectory() else {
            return
        }

        var settings = BrowserSettings.defaults
        settings.enabled = false
        settings.runtimeMode = .managed
        BrowserSettingsStore.save(settings)
        BrowserSettingsStore.saveApplied(settings)

        let result = await AgentBrowserService.applyEnabled(true, settings: settings)
        XCTAssertEqual(result, .needsSetup)
        XCTAssertFalse(BrowserSettingsStore.loadApplied().enabled)
    }

    @MainActor
    func testApplyEnabledPersistsWhenDraftToggleAlreadyMatchesDesired() async {
        var draft = BrowserSettings.defaults
        draft.enabled = true
        draft.runtimeMode = .external
        draft.externalBrowserAppID = .chrome
        guard AgentBrowserService.browserToolsConfigurationIssue(settings: draft) == nil else {
            return
        }

        var applied = draft
        applied.enabled = false
        BrowserSettingsStore.save(draft)
        BrowserSettingsStore.saveApplied(applied)

        let result = await AgentBrowserService.applyEnabled(true, settings: draft)
        XCTAssertEqual(result, .applied)
        XCTAssertTrue(BrowserSettingsStore.loadApplied().enabled)
    }

    @MainActor
    func testApplyEnabledTurnsBrowserOnWhenExternalChromeIsReady() async {
        var settings = BrowserSettings.defaults
        settings.enabled = false
        settings.runtimeMode = .external
        settings.externalBrowserAppID = .chrome
        guard AgentBrowserService.browserToolsConfigurationIssue(settings: settings) == nil else {
            return
        }

        BrowserSettingsStore.save(settings)
        BrowserSettingsStore.saveApplied(settings)

        let result = await AgentBrowserService.applyEnabled(true, settings: settings)
        XCTAssertEqual(result, .applied)
        XCTAssertTrue(BrowserSettingsStore.loadApplied().enabled)
        XCTAssertEqual(BrowserSettingsStore.loadApplied().runtimeMode, .external)
    }

    func testBrowserMCPConfigIncludesHeadedEnvironmentWhenEnabled() throws {
        let settings = BrowserSettings(
            enabled: true,
            cdpURL: "",
            profileName: "",
            showBrowserWindow: true
        )

        let config = try XCTUnwrap(AgentBrowserService.browserMCPConfig(settings: settings))
        let env = try XCTUnwrap(config.jsonObject["env"] as? [[String: String]])

        XCTAssertTrue(env.contains { entry in
            entry["name"] == "AGENT_BROWSER_HEADED" && entry["value"] == "true"
        })
    }

    func testBrowserMCPConfigUsesDefaultCDPURLInExternalMode() throws {
        let settings = BrowserSettings(
            enabled: true,
            runtimeMode: .external,
            cdpURL: "",
            profileName: "",
            showBrowserWindow: false
        )

        let config = try XCTUnwrap(AgentBrowserService.browserMCPConfig(settings: settings))
        let env = try XCTUnwrap(config.jsonObject["env"] as? [[String: String]])

        XCTAssertTrue(env.contains { entry in
            entry["name"] == "GROKBUILD_BROWSER_CDP_URL" && entry["value"] == "http://127.0.0.1:9222"
        })
    }

    func testAgentBrowserCommandPreviewKeepsArguments() {
        let command = AgentBrowserService.commandPreview(["open", "https://example.com"])

        XCTAssertGreaterThanOrEqual(command.count, 3)
        XCTAssertEqual(Array(command.suffix(2)), ["open", "https://example.com"])
    }

    func testExternalBrowserLaunchArgumentsUseCDPPortAndSeparateProfile() {
        let settings = BrowserSettings(
            enabled: true,
            cdpURL: "http://127.0.0.1:9333",
            profileName: "",
            showBrowserWindow: false,
            externalBrowserAppID: .chrome,
            externalBrowserAppPath: "",
            autoStartExternalBrowser: true
        )

        let args = AgentBrowserService.externalBrowserLaunchArguments(settings: settings)

        XCTAssertTrue(args.contains("--remote-debugging-port=9333"))
        XCTAssertTrue(args.contains { $0.hasPrefix("--user-data-dir=") && $0.contains("GrokBuild/BrowserProfiles/chrome") })
        XCTAssertTrue(args.contains("--no-first-run"))
    }

    func testExternalBrowserInstalledChoicesAlwaysIncludeCustom() {
        XCTAssertTrue(ExternalBrowserAppID.installedChoices.contains(.custom))
        XCTAssertFalse(ExternalBrowserAppID.installedChoices.contains { app in
            app != .custom && app.defaultAppURL == nil
        })
    }

    func testBrowserSkillInstallerCopiesBundledSkillWhenEnabled() throws {
        let skillsRoot = temporarySkillsRootURL()
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        let settings = BrowserSettings(
            enabled: true,
            cdpURL: "",
            profileName: "",
            showBrowserWindow: false
        )

        try BrowserSkillInstaller.installIfNeeded(settings: settings, skillsRoot: skillsRoot)

        let installedSkill = BrowserSkillInstaller.skillURL(inSkillsRoot: skillsRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedSkill.path))
        let contents = try String(contentsOf: installedSkill, encoding: .utf8)
        XCTAssertTrue(contents.contains("GrokBuild Browser Control"))
        XCTAssertTrue(contents.contains("browser_tabs"))
        XCTAssertTrue(contents.contains("about:blank"))
    }

    func testBrowserMCPScriptAdvertisesTabAndSnapshotTools() throws {
        let script = try XCTUnwrap(browserMCPScriptURL())
        let source = try String(contentsOf: script, encoding: .utf8)
        for name in [
            "browser_open_url",
            "browser_snapshot",
            "browser_tabs",
            "browser_click_ref",
            "browser_type_ref",
            "browser_screenshot",
            "browser_eval_js",
            "browser_wait_for_load"
        ] {
            XCTAssertTrue(source.contains("\"name\": \"\(name)\""), name)
        }
        XCTAssertTrue(source.contains("\"tab\", \"list\""))
        XCTAssertTrue(source.contains("Blank tab"))
        XCTAssertTrue(source.contains("str(action)"))
        XCTAssertFalse(source.contains("\"\", \"about:blank\""))
    }

    func testBrowserSkillInstallerDoesNothingWhenDisabled() throws {
        let skillsRoot = temporarySkillsRootURL()
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        let settings = BrowserSettings(
            enabled: false,
            cdpURL: "",
            profileName: "",
            showBrowserWindow: false
        )

        try BrowserSkillInstaller.installIfNeeded(settings: settings, skillsRoot: skillsRoot)

        XCTAssertFalse(FileManager.default.fileExists(atPath: BrowserSkillInstaller.skillURL(inSkillsRoot: skillsRoot).path))
    }

    func testBrowserSkillInstallerAlsoInstallsGrokWebSkillWhenEnabled() throws {
        let skillsRoot = temporarySkillsRootURL()
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        let settings = BrowserSettings(
            enabled: true,
            cdpURL: "",
            profileName: "",
            showBrowserWindow: false
        )

        try BrowserSkillInstaller.installIfNeeded(settings: settings, skillsRoot: skillsRoot)

        let grokWebSkill = BrowserSkillInstaller.skillURL(named: "grokbuild-grok-web", inSkillsRoot: skillsRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: grokWebSkill.path))
        let contents = try String(contentsOf: grokWebSkill, encoding: .utf8)
        XCTAssertTrue(contents.contains("grok.com Web"))
    }

    func testGrokComBrowserPresetConfiguresExternalChromeWithDedicatedSessionName() {
        let preset = BrowserPreset.grokCom
        let settings = BrowserSettings(
            enabled: true,
            runtimeMode: .managed,
            cdpURL: "",
            profileName: "",
            showBrowserWindow: false
        )

        let applied = preset.applied(to: settings)

        XCTAssertEqual(applied.runtimeMode, .external)
        XCTAssertEqual(applied.externalBrowserAppID, .chrome)
        XCTAssertEqual(applied.cdpURL, "http://127.0.0.1:9222")
        XCTAssertEqual(applied.profileName, "grok-com")
        XCTAssertTrue(applied.showBrowserWindow)
        XCTAssertTrue(applied.autoStartExternalBrowser)
        // Preset must not flip the user's enable toggle.
        XCTAssertEqual(applied.enabled, settings.enabled)
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func temporarySkillsRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokBuildTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(".grok")
            .appendingPathComponent("skills")
    }

    private func browserMCPScriptURL() -> URL? {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<5 {
            let candidate = directory
                .appendingPathComponent("scripts")
                .appendingPathComponent("grokbuild-browser-mcp")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}
