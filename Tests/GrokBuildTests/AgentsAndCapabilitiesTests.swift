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

    // MARK: - SubagentRole validation

    func testSubagentRoleValidationRules() {
        XCTAssertNotNil(SubagentRole(name: "", instruction: "do work").validationError)
        XCTAssertNotNil(SubagentRole(name: "bad name", instruction: "x").validationError)
        XCTAssertNotNil(SubagentRole(name: "explore", instruction: "x").validationError,
                        "reserved built-in names must be rejected")
        XCTAssertNotNil(SubagentRole(name: "researcher", instruction: "   ").validationError,
                        "instruction is required")
        XCTAssertNil(SubagentRole(name: "researcher", model: "grok-build", instruction: "Research deeply.").validationError)
    }

    func testSubagentRoleSuggestedName() {
        XCTAssertEqual(SubagentRole.suggestedName(from: "Security Review!"), "security-review")
        XCTAssertEqual(SubagentRole.suggestedName(from: "  test_writer  "), "test_writer")
    }

    // MARK: - SubagentRoleStore parsing

    func testRoleStoreParsesFieldsAndReadsInstructionFromPromptFile() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("grokbuild-role-\(UUID().uuidString).md")
        try "Research the codebase thoroughly.".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let toml = """
        [subagents.roles.researcher]
        description = "Deep research agent"
        model = "grok-build"
        prompt_file = "\(tmp.path)"
        """

        let roles = SubagentRoleStore.parse(toml)
        XCTAssertEqual(roles.count, 1)
        let role = try XCTUnwrap(roles.first)
        XCTAssertEqual(role.name, "researcher")
        XCTAssertEqual(role.model, "grok-build")
        XCTAssertEqual(role.description, "Deep research agent")
        XCTAssertEqual(role.instruction, "Research the codebase thoroughly.")
    }

    func testRoleStoreParsesRelativePromptFileFromHomeBase() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("grokbuild-role-root-\(UUID().uuidString)", isDirectory: true)
        let prompt = root.appendingPathComponent(".grok/prompts/researcher.md")
        try FileManager.default.createDirectory(
            at: prompt.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "Use relative prompt files.".write(to: prompt, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let toml = """
        [subagents.roles.researcher]
        prompt_file = ".grok/prompts/researcher.md"
        """

        let roles = SubagentRoleStore.parse(toml, relativePromptBaseURL: root)
        XCTAssertEqual(roles.first?.instruction, "Use relative prompt files.")
    }

    // MARK: - SubagentRoleStore rewrite

    func testRoleStoreRewritePreservesOtherContentAndReplacesRoles() {
        let existing = """
        [models]
        default = "grok-build"

        [model.zai-glm]
        model = "glm-5.2"
        base_url = "https://api.z.ai/v1"

        [subagents.roles.stale]
        model = "grok-build"
        prompt_file = "/old/path.md"
        """

        let updated = SubagentRoleStore.rewrite(existing, roles: [
            SubagentRole(name: "reviewer", model: "grok-build", instruction: "Review.", description: "Reviewer")
        ])

        // Unrelated content is preserved.
        XCTAssertTrue(updated.contains("[model.zai-glm]"))
        XCTAssertTrue(updated.contains("default = \"grok-build\""))
        // Old role table is dropped, new one added.
        XCTAssertFalse(updated.contains("[subagents.roles.stale]"))
        XCTAssertTrue(updated.contains("[subagents.roles.reviewer]"))
        XCTAssertTrue(updated.contains("description = \"Reviewer\""))
        XCTAssertTrue(updated.contains(".grok/prompts/reviewer.md"))
    }

    func testRoleStoreRewritePreservesUnknownRoleFields() {
        let updated = SubagentRoleStore.rewrite("", roles: [
            SubagentRole(
                name: "researcher",
                model: "grok-build",
                instruction: "Research.",
                extraFields: ["default_capability_mode": "\"read-only\""]
            )
        ])

        XCTAssertTrue(updated.contains("default_capability_mode = \"read-only\""))
    }

    func testRoleStoreRewriteOmitsModelWhenInherited() {
        let updated = SubagentRoleStore.rewrite("", roles: [
            SubagentRole(name: "helper", model: "", instruction: "Help.")
        ])
        XCTAssertTrue(updated.contains("[subagents.roles.helper]"))
        XCTAssertFalse(updated.contains("model ="), "empty model must be omitted so the role inherits the session model")
    }
}
