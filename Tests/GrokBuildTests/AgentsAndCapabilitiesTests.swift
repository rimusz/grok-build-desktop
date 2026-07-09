import XCTest
@testable import GrokBuild

final class AgentsAndCapabilitiesTests: XCTestCase {

    // MARK: - GrokAgentProfiles

    func testDefaultSelectionOmitsAgentFlag() {
        XCTAssertNil(GrokAgentProfiles.launchArgument(for: ""))
        XCTAssertNil(GrokAgentProfiles.launchArgument(for: "   "))
    }

    func testArbitraryAgentNamePassesThrough() {
        XCTAssertEqual(GrokAgentProfiles.launchArgument(for: "explore"), "explore")
        XCTAssertEqual(GrokAgentProfiles.launchArgument(for: "  explore  "), "explore")
    }

    func testBuiltInOptionsAreDefaultOnly() {
        let ids = GrokAgentProfiles.builtInOptions.map(\.id)
        XCTAssertEqual(ids, [GrokAgentProfiles.defaultID])
    }

    func testDisplayNamePrefersBuiltInTitlesElseRawName() {
        XCTAssertEqual(GrokAgentProfiles.displayName(for: ""), "Default (grok build)")
        XCTAssertEqual(GrokAgentProfiles.displayName(for: "explore"), "explore")
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

    // MARK: - Memory launch flag

    func testMemoryEnabledDefaultsOff() {
        XCTAssertFalse(GrokPermissionSettings.defaults.memoryEnabled)
    }

    func testMemoryFlagMapsEnabledToExperimentalMemory() {
        XCTAssertEqual(
            GrokMemoryFlag.argument(noMemory: false, experimentalMemory: true),
            "--experimental-memory"
        )
    }

    func testMemoryFlagMapsDisabledToNoMemory() {
        XCTAssertEqual(
            GrokMemoryFlag.argument(noMemory: true, experimentalMemory: false),
            "--no-memory"
        )
    }

    func testMemoryFlagNoMemoryTakesPriority() {
        // grok gives `--no-memory` absolute priority; never emit both.
        XCTAssertEqual(
            GrokMemoryFlag.argument(noMemory: true, experimentalMemory: true),
            "--no-memory"
        )
    }

    func testMemoryFlagOmittedWhenNeitherSet() {
        XCTAssertNil(GrokMemoryFlag.argument(noMemory: false, experimentalMemory: false))
    }
}
