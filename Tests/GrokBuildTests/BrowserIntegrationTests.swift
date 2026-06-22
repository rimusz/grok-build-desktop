import XCTest
@testable import GrokBuild

final class BrowserIntegrationTests: XCTestCase {
    private var savedEnabled: Any?
    private var savedBackend: Any?
    private var savedRuntimeMode: Any?
    private var savedCDPURL: Any?
    private var savedProfileName: Any?
    private var savedShowBrowserWindow: Any?
    private var savedExternalBrowserAppID: Any?
    private var savedExternalBrowserAppPath: Any?
    private var savedAutoStartExternalBrowser: Any?
    private var savedAppliedEnabled: Any?
    private var savedAppliedBackend: Any?
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
        savedBackend = defaults.object(forKey: BrowserSettingsKeys.backend)
        savedRuntimeMode = defaults.object(forKey: BrowserSettingsKeys.runtimeMode)
        savedCDPURL = defaults.object(forKey: BrowserSettingsKeys.cdpURL)
        savedProfileName = defaults.object(forKey: BrowserSettingsKeys.profileName)
        savedShowBrowserWindow = defaults.object(forKey: BrowserSettingsKeys.showBrowserWindow)
        savedExternalBrowserAppID = defaults.object(forKey: BrowserSettingsKeys.externalBrowserAppID)
        savedExternalBrowserAppPath = defaults.object(forKey: BrowserSettingsKeys.externalBrowserAppPath)
        savedAutoStartExternalBrowser = defaults.object(forKey: BrowserSettingsKeys.autoStartExternalBrowser)
        savedAppliedEnabled = defaults.object(forKey: BrowserSettingsKeys.appliedEnabled)
        savedAppliedBackend = defaults.object(forKey: BrowserSettingsKeys.appliedBackend)
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
        restore(savedBackend, forKey: BrowserSettingsKeys.backend)
        restore(savedRuntimeMode, forKey: BrowserSettingsKeys.runtimeMode)
        restore(savedCDPURL, forKey: BrowserSettingsKeys.cdpURL)
        restore(savedProfileName, forKey: BrowserSettingsKeys.profileName)
        restore(savedShowBrowserWindow, forKey: BrowserSettingsKeys.showBrowserWindow)
        restore(savedExternalBrowserAppID, forKey: BrowserSettingsKeys.externalBrowserAppID)
        restore(savedExternalBrowserAppPath, forKey: BrowserSettingsKeys.externalBrowserAppPath)
        restore(savedAutoStartExternalBrowser, forKey: BrowserSettingsKeys.autoStartExternalBrowser)
        restore(savedAppliedEnabled, forKey: BrowserSettingsKeys.appliedEnabled)
        restore(savedAppliedBackend, forKey: BrowserSettingsKeys.appliedBackend)
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
            backend: .agentBrowser,
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
            backend: .agentBrowser,
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
            backend: .agentBrowser,
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

    func testBrowserMCPConfigIncludesHeadedEnvironmentWhenEnabled() throws {
        let settings = BrowserSettings(
            enabled: true,
            backend: .agentBrowser,
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
            backend: .agentBrowser,
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
            backend: .agentBrowser,
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
            backend: .agentBrowser,
            cdpURL: "",
            profileName: "",
            showBrowserWindow: false
        )

        try BrowserSkillInstaller.installIfNeeded(settings: settings, skillsRoot: skillsRoot)

        let installedSkill = BrowserSkillInstaller.skillURL(inSkillsRoot: skillsRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedSkill.path))
        let contents = try String(contentsOf: installedSkill, encoding: .utf8)
        XCTAssertTrue(contents.contains("GrokBuild Browser Control"))
    }

    func testBrowserSkillInstallerDoesNothingWhenDisabled() throws {
        let skillsRoot = temporarySkillsRootURL()
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        let settings = BrowserSettings(
            enabled: false,
            backend: .agentBrowser,
            cdpURL: "",
            profileName: "",
            showBrowserWindow: false
        )

        try BrowserSkillInstaller.installIfNeeded(settings: settings, skillsRoot: skillsRoot)

        XCTAssertFalse(FileManager.default.fileExists(atPath: BrowserSkillInstaller.skillURL(inSkillsRoot: skillsRoot).path))
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
}

