import XCTest
@testable import GrokBuild

final class ComputerUseIntegrationTests: XCTestCase {
    private var savedValues: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        for key in allKeys {
            savedValues[key] = UserDefaults.standard.object(forKey: key)
        }
    }

    override func tearDown() {
        for key in allKeys {
            restore(savedValues[key] ?? nil, forKey: key)
        }
        super.tearDown()
    }

    func testComputerUseSettingsRoundTrip() {
        let settings = ComputerUseSettings(
            enabled: true,
            backend: .agentDesktop,
            agentDesktopPath: "/opt/homebrew/bin/agent-desktop",
            permissionPolicy: .auto,
            maxSteps: 42,
            commandTimeoutSeconds: 90,
            screenshotMode: .screenshotsAllowed,
            includeScreenshots: true,
            allowPhysicalMouse: true,
            sessionName: "project-a"
        )

        ComputerUseSettingsStore.save(settings)

        XCTAssertEqual(ComputerUseSettingsStore.load(), settings)
    }

    func testAppliedComputerUseSettingsRoundTripSeparately() {
        let current = ComputerUseSettings(
            enabled: true,
            backend: .agentDesktop,
            agentDesktopPath: "/tmp/current-agent-desktop",
            permissionPolicy: .ask,
            maxSteps: 12,
            commandTimeoutSeconds: 30,
            screenshotMode: .accessibilityFirst,
            includeScreenshots: false,
            allowPhysicalMouse: false,
            sessionName: "current"
        )
        let applied = ComputerUseSettings(
            enabled: false,
            backend: .agentDesktop,
            agentDesktopPath: "/tmp/applied-agent-desktop",
            permissionPolicy: .deny,
            maxSteps: 4,
            commandTimeoutSeconds: 15,
            screenshotMode: .screenshotsAllowed,
            includeScreenshots: true,
            allowPhysicalMouse: true,
            sessionName: "applied"
        )

        ComputerUseSettingsStore.save(current)
        ComputerUseSettingsStore.saveApplied(applied)

        XCTAssertEqual(ComputerUseSettingsStore.load(), current)
        XCTAssertEqual(ComputerUseSettingsStore.loadApplied(), applied)
    }

    func testComputerUseMCPConfigSerializesForACP() throws {
        let helper = URL(fileURLWithPath: "/tmp/GrokBuildComputerUseMCP")
        let agentDesktop = URL(fileURLWithPath: "/opt/homebrew/bin/agent-desktop")
        let settings = ComputerUseSettings(
            enabled: true,
            backend: .agentDesktop,
            agentDesktopPath: "",
            permissionPolicy: .auto,
            maxSteps: 10,
            commandTimeoutSeconds: 25,
            screenshotMode: .accessibilityFirst,
            includeScreenshots: true,
            allowPhysicalMouse: false,
            sessionName: "test-session"
        )

        let config = try XCTUnwrap(ComputerUseService.computerUseMCPConfig(
            settings: settings,
            helperOverride: helper,
            agentDesktopOverride: agentDesktop
        ))
        let json = config.jsonObject

        XCTAssertEqual(json["name"] as? String, "grokbuild-computer-use")
        XCTAssertNil(json["type"])
        XCTAssertNil(json["transport"])
        XCTAssertEqual(json["command"] as? String, helper.path)
        XCTAssertEqual(json["args"] as? [String], [])

        let env = try XCTUnwrap(json["env"] as? [[String: String]])
        XCTAssertTrue(env.contains { $0["name"] == "AGENT_DESKTOP_PATH" && $0["value"] == agentDesktop.path })
        XCTAssertTrue(env.contains { $0["name"] == "GROKBUILD_COMPUTER_USE_POLICY" && $0["value"] == "auto" })
        XCTAssertTrue(env.contains { $0["name"] == "GROKBUILD_COMPUTER_USE_SCREENSHOTS" && $0["value"] == "true" })
    }

    func testComputerUseMCPConfigDisabledReturnsNil() {
        let settings = ComputerUseSettings.defaults

        XCTAssertNil(ComputerUseService.computerUseMCPConfig(
            settings: settings,
            helperOverride: URL(fileURLWithPath: "/tmp/GrokBuildComputerUseMCP")
        ))
    }

    func testAgentDesktopDiscoveryUsesConfiguredExecutablePath() throws {
        let executable = temporaryExecutableURL()
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: executable.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        var settings = ComputerUseSettings.defaults
        settings.agentDesktopPath = executable.path

        XCTAssertEqual(ComputerUseService.executableURL(settings: settings), executable)
    }

    func testPermissionDiagnosticsParseStructuredJSON() {
        let status = ComputerUseService.parsePermissions("""
        {"accessibility":{"state":"granted"},"screen_recording":{"state":"denied"}}
        """)

        XCTAssertEqual(status.accessibility, "granted")
        XCTAssertEqual(status.screenRecording, "denied")
        XCTAssertTrue(status.isReady)
    }

    func testPermissionDiagnosticsParseAgentDesktopEnvelope() {
        let status = ComputerUseService.parsePermissions("""
        {"command":"permissions","data":{"accessibility":{"state":"granted"},"screen_recording":{"state":"denied"}},"ok":true,"version":"2.0"}
        """)

        XCTAssertEqual(status.accessibility, "granted")
        XCTAssertEqual(status.screenRecording, "denied")
        XCTAssertTrue(status.isReady)
    }

    func testVersionParserUsesAgentDesktopDataVersion() {
        let version = ComputerUseService.parseVersion("""
        {"command":"version","data":{"os":"macos","target":"aarch64","version":"0.3.1"},"ok":true,"version":"2.0"}
        """)

        XCTAssertEqual(version, "0.3.1")
    }

    func testComputerUseSkillInstallerCopiesBundledSkillWhenEnabled() throws {
        let skillsRoot = temporarySkillsRootURL()
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        var settings = ComputerUseSettings.defaults
        settings.enabled = true

        try ComputerUseSkillInstaller.installIfNeeded(settings: settings, skillsRoot: skillsRoot)

        let installedSkill = ComputerUseSkillInstaller.skillURL(inSkillsRoot: skillsRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedSkill.path))
        let contents = try String(contentsOf: installedSkill, encoding: .utf8)
        XCTAssertTrue(contents.contains("GrokBuild Computer Use"))
    }

    func testComputerUseSkillInstallerDoesNothingWhenDisabled() throws {
        let skillsRoot = temporarySkillsRootURL()
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        try ComputerUseSkillInstaller.installIfNeeded(settings: .defaults, skillsRoot: skillsRoot)

        XCTAssertFalse(FileManager.default.fileExists(atPath: ComputerUseSkillInstaller.skillURL(inSkillsRoot: skillsRoot).path))
    }

    private var allKeys: [String] {
        [
            ComputerUseSettingsKeys.enabled,
            ComputerUseSettingsKeys.backend,
            ComputerUseSettingsKeys.agentDesktopPath,
            ComputerUseSettingsKeys.permissionPolicy,
            ComputerUseSettingsKeys.maxSteps,
            ComputerUseSettingsKeys.commandTimeoutSeconds,
            ComputerUseSettingsKeys.screenshotMode,
            ComputerUseSettingsKeys.includeScreenshots,
            ComputerUseSettingsKeys.allowPhysicalMouse,
            ComputerUseSettingsKeys.sessionName,
            ComputerUseSettingsKeys.appliedEnabled,
            ComputerUseSettingsKeys.appliedBackend,
            ComputerUseSettingsKeys.appliedAgentDesktopPath,
            ComputerUseSettingsKeys.appliedPermissionPolicy,
            ComputerUseSettingsKeys.appliedMaxSteps,
            ComputerUseSettingsKeys.appliedCommandTimeoutSeconds,
            ComputerUseSettingsKeys.appliedScreenshotMode,
            ComputerUseSettingsKeys.appliedIncludeScreenshots,
            ComputerUseSettingsKeys.appliedAllowPhysicalMouse,
            ComputerUseSettingsKeys.appliedSessionName
        ]
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func temporaryExecutableURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokBuildTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("agent-desktop")
    }

    private func temporarySkillsRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokBuildTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(".grok")
            .appendingPathComponent("skills")
    }
}
