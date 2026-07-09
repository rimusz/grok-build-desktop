import XCTest
@testable import GrokBuild

final class AgentsAndCapabilitiesTests: XCTestCase {

    // MARK: - GrokCapabilities version parsing

    func testParsesVersionFromRealVersionOutput() {
        let version = GrokCapabilities.parseVersion("grok 0.2.93 (f00f96316d4b) [stable]")
        XCTAssertEqual(version, GrokCapabilities.Version(major: 0, minor: 2, patch: 93))
    }

    func testParsesBareVersion() {
        XCTAssertEqual(GrokCapabilities.parseVersion("1.10.4"),
                       GrokCapabilities.Version(major: 1, minor: 10, patch: 4))
    }

    func testUnparseableVersionReturnsNil() {
        XCTAssertNil(GrokCapabilities.parseVersion("grok (unknown build)"))
    }

    func testVersionOrdering() {
        XCTAssertLessThan(GrokCapabilities.Version(major: 0, minor: 2, patch: 89),
                          GrokCapabilities.Version(major: 0, minor: 2, patch: 90))
        XCTAssertLessThan(GrokCapabilities.Version(major: 0, minor: 2, patch: 99),
                          GrokCapabilities.Version(major: 0, minor: 3, patch: 0))
    }

    func testNativeBrowserSupportGatesOnVersionFloor() {
        XCTAssertTrue(GrokCapabilities.supportsNativeBrowserTools(versionOutput: "grok 0.2.93 (abc) [stable]"))
        XCTAssertTrue(GrokCapabilities.supportsNativeBrowserTools(versionOutput: "grok 0.3.0"))
        XCTAssertFalse(GrokCapabilities.supportsNativeBrowserTools(versionOutput: "grok 0.2.80"))
        // Fail closed on garbage so the app keeps using agent-browser.
        XCTAssertFalse(GrokCapabilities.supportsNativeBrowserTools(versionOutput: "n/a"))
    }

    // MARK: - GrokAgentProfiles

    func testDefaultSelectionOmitsAgentFlag() {
        XCTAssertNil(GrokAgentProfiles.launchArgument(for: ""))
        XCTAssertNil(GrokAgentProfiles.launchArgument(for: "   "))
    }

    func testWebProfileResolvesToBundledPathOrName() {
        let arg = GrokAgentProfiles.launchArgument(for: GrokAgentProfiles.webProfileID)
        XCTAssertNotNil(arg)
        // Either the bundled absolute path (…/grokbuild-web.md) or the sentinel name fallback.
        XCTAssertTrue(arg == GrokAgentProfiles.webProfileID || arg?.hasSuffix("grokbuild-web.md") == true)
    }

    func testArbitraryAgentNamePassesThrough() {
        XCTAssertEqual(GrokAgentProfiles.launchArgument(for: "explore"), "explore")
    }

    // MARK: - GrokAgentInfo parsing

    func testAgentInfoParsesBuiltinAndPluginSources() {
        let builtin = GrokAgentInfo(dictionary: [
            "name": "explore",
            "description": "Fast agent specialized for exploring codebases.",
            "source": ["type": "builtin"]
        ])
        XCTAssertEqual(builtin.name, "explore")
        XCTAssertEqual(builtin.sourceType, "builtin")
        XCTAssertTrue(builtin.pluginName.isEmpty)

        let plugin = GrokAgentInfo(dictionary: [
            "name": "code-simplifier:code-simplifier",
            "description": "Simplifies code.",
            "source": ["type": "plugin", "plugin_name": "code-simplifier", "path": "/tmp/agents/x.md"]
        ])
        XCTAssertEqual(plugin.pluginName, "code-simplifier")
        XCTAssertEqual(plugin.sourcePath, "/tmp/agents/x.md")
    }

    // MARK: - GrokPermissionSettings

    func testPermissionSettingsDefaultsToEmptyAgent() {
        XCTAssertEqual(GrokPermissionSettings.defaults.selectedAgent, "")
    }
}
