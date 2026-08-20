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

    // MARK: - SpecialistAgent validation

    func testSpecialistAgentValidationRequiresNameMissionGlyphAndColor() {
        XCTAssertEqual(
            SpecialistAgent(name: "  ", mission: "Route work", glyph: "crown").validationError,
            "Name is required."
        )
        XCTAssertEqual(
            SpecialistAgent(name: "Chief", mission: "   ", glyph: "crown").validationError,
            "Mission is required."
        )
        XCTAssertEqual(
            SpecialistAgent(name: "Chief", mission: "Route work", glyph: " ").validationError,
            "Glyph is required."
        )
        XCTAssertEqual(
            SpecialistAgent(name: "Chief", mission: "Route work", glyph: "crown", color: "blue").validationError,
            "Color must be a hex value such as #RRGGBB."
        )
        XCTAssertNil(
            SpecialistAgent(name: "Chief", mission: "Route work", glyph: "crown", color: "#5e5ce6").validationError
        )
    }

    func testSpecialistAgentColorCanonicalizesHex() {
        XCTAssertEqual(SpecialistAgent.canonicalizeColor("  #5e5ce6  "), "#5E5CE6")
        XCTAssertEqual(SpecialistAgent.canonicalizeColor("aabbcc"), "#AABBCC")
        XCTAssertEqual(SpecialistAgent.canonicalizeColor("#abc"), "#AABBCC")
        XCTAssertNil(SpecialistAgent.canonicalizeColor("blue"))
        XCTAssertNil(SpecialistAgent.canonicalizeColor("#GGG"))
    }

    func testSpecialistAgentRoleNameRejectsInvalidAndReservedNames() {
        XCTAssertNotNil(
            SpecialistAgent(name: "Scout", mission: "Research", roleName: "bad name").validationError
        )
        XCTAssertEqual(
            SpecialistAgent(name: "Scout", mission: "Research", roleName: "explore").validationError,
            "\"explore\" is reserved by a built-in subagent."
        )
        XCTAssertNil(
            SpecialistAgent(name: "Scout", mission: "Research", roleName: "researcher").validationError
        )
    }

    func testSpecialistAgentNormalizeTrimsOptionalsAndDedupesSkills() {
        let agent = SpecialistAgent(
            name: "  Builder  ",
            mission: " Implement code ",
            glyph: " hammer ",
            color: "#abc",
            roleName: "  ",
            defaultModel: "  grok-build  ",
            preferredSkills: [" /review ", "", "/review", " /design "]
        ).normalized()

        XCTAssertEqual(agent.name, "Builder")
        XCTAssertEqual(agent.mission, "Implement code")
        XCTAssertEqual(agent.glyph, "hammer")
        XCTAssertEqual(agent.color, "#AABBCC")
        XCTAssertNil(agent.roleName)
        XCTAssertEqual(agent.defaultModel, "grok-build")
        XCTAssertEqual(agent.preferredSkills, ["/review", "/design"])
    }

    func testSpecialistAgentCodableRoundTripPreservesAllFields() throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let sessionID = UUID()
        let original = SpecialistAgent(
            name: "Verifier",
            mission: "Independent review",
            glyph: "checkmark.shield",
            color: "#34C759",
            roleName: "verifier-role",
            defaultModel: "grok-build",
            permissionProfile: .readOnly,
            browserEnabled: true,
            computerUseEnabled: false,
            preferredSkills: ["/review"],
            createdAt: created,
            updatedAt: created,
            lastSessionID: sessionID
        )
        let data = try SpecialistAgentStore.encode([original])
        let decoded = try SpecialistAgentStore.decode(data)
        XCTAssertEqual(decoded, [original])
    }

    func testSpecialistAgentDecodeFillsMissingOptionalFields() throws {
        let json = """
        [
          {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "Chief",
            "mission": "Route work",
            "glyph": "crown",
            "color": "#5E5CE6",
            "createdAt": "2023-11-14T22:13:20Z",
            "updatedAt": "2023-11-14T22:13:20Z"
          }
        ]
        """
        let decoded = try SpecialistAgentStore.decode(Data(json.utf8))
        let agent = try XCTUnwrap(decoded.first)
        XCTAssertEqual(agent.name, "Chief")
        XCTAssertNil(agent.roleName)
        XCTAssertNil(agent.defaultModel)
        XCTAssertEqual(agent.permissionProfile, .inherit)
        XCTAssertFalse(agent.browserEnabled)
        XCTAssertFalse(agent.computerUseEnabled)
        XCTAssertEqual(agent.preferredSkills, [])
        XCTAssertNil(agent.lastSessionID)
    }

    func testSpecialistAgentDefaultStorageURLIsVersionedApplicationSupportFile() {
        let url = SpecialistAgentStore.defaultStorageURL
        XCTAssertTrue(url.path.contains("Application Support/GrokBuild"))
        XCTAssertEqual(url.lastPathComponent, "agents.v1.json")
    }

    // MARK: - SpecialistAgentStore persistence

    @MainActor
    func testSpecialistAgentStoreMissingFileLoadsEmptyRoster() {
        let url = Self.temporaryStoreURL()
        defer { Self.removeStore(at: url) }

        let store = SpecialistAgentStore(storageURL: url)
        XCTAssertTrue(store.agents.isEmpty)
        XCTAssertNil(store.loadError)
    }

    @MainActor
    func testSpecialistAgentStoreCreateUpdateDeleteRoundTrip() throws {
        let url = Self.temporaryStoreURL()
        defer { Self.removeStore(at: url) }
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = SpecialistAgentStore(storageURL: url, now: { now })

        let created = try store.create(SpecialistAgent(
            name: "  Chief  ",
            mission: " Route work ",
            glyph: "crown",
            color: "#5e5ce6",
            roleName: "chief",
            permissionProfile: .workspaceWrite
        ))
        XCTAssertEqual(created.name, "Chief")
        XCTAssertEqual(created.color, "#5E5CE6")
        XCTAssertEqual(created.createdAt, now)
        XCTAssertEqual(created.updatedAt, now)
        XCTAssertEqual(store.agents.count, 1)

        let reloaded = SpecialistAgentStore(storageURL: url)
        XCTAssertEqual(reloaded.agents, store.agents)

        now = now.addingTimeInterval(60)
        let updated = try store.update(SpecialistAgent(
            id: created.id,
            name: "Chief",
            mission: "Keep scope tight",
            glyph: "crown.fill",
            color: "#5E5CE6",
            roleName: "chief",
            permissionProfile: .workspaceWrite,
            createdAt: Date(timeIntervalSince1970: 0),
            lastSessionID: UUID()
        ))
        XCTAssertEqual(updated.id, created.id)
        XCTAssertEqual(updated.createdAt, created.createdAt)
        XCTAssertEqual(updated.updatedAt, now)
        XCTAssertEqual(updated.mission, "Keep scope tight")
        XCTAssertEqual(updated.glyph, "crown.fill")
        XCTAssertNotNil(updated.lastSessionID)

        try store.delete(id: created.id)
        XCTAssertTrue(store.agents.isEmpty)
        XCTAssertTrue(SpecialistAgentStore(storageURL: url).agents.isEmpty)
    }

    @MainActor
    func testSpecialistAgentStoreRejectsDuplicateNames() throws {
        let url = Self.temporaryStoreURL()
        defer { Self.removeStore(at: url) }
        let store = SpecialistAgentStore(storageURL: url)

        try store.create(SpecialistAgent(name: "Builder", mission: "Implement"))
        XCTAssertThrowsError(
            try store.create(SpecialistAgent(name: "builder", mission: "Also implement"))
        ) { error in
            XCTAssertEqual(error as? SpecialistAgentStoreError, .duplicateName("builder"))
        }
        XCTAssertEqual(store.agents.count, 1)

        let first = try XCTUnwrap(store.agents.first)
        try store.create(SpecialistAgent(name: "Scout", mission: "Research"))
        XCTAssertThrowsError(
            try store.update(SpecialistAgent(id: first.id, name: "scout", mission: "Implement"))
        ) { error in
            XCTAssertEqual(error as? SpecialistAgentStoreError, .duplicateName("scout"))
        }
        XCTAssertEqual(store.agent(id: first.id)?.name, "Builder")
    }

    @MainActor
    func testSpecialistAgentStoreRejectsInvalidAndReservedRoleOnCreate() {
        let url = Self.temporaryStoreURL()
        defer { Self.removeStore(at: url) }
        let store = SpecialistAgentStore(storageURL: url)

        XCTAssertThrowsError(
            try store.create(SpecialistAgent(name: "Scout", mission: "Research", roleName: "explore"))
        ) { error in
            XCTAssertEqual(
                error as? SpecialistAgentStoreError,
                .invalidAgent("\"explore\" is reserved by a built-in subagent.")
            )
        }
        XCTAssertThrowsError(
            try store.create(SpecialistAgent(name: "Scout", mission: "Research", roleName: "bad name"))
        )
        XCTAssertTrue(store.agents.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testSpecialistAgentStoreMalformedJSONSetsLoadErrorWithoutRewrite() throws {
        let url = Self.temporaryStoreURL()
        defer { Self.removeStore(at: url) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = Data("{not-json".utf8)
        try payload.write(to: url)

        let store = SpecialistAgentStore(storageURL: url)
        XCTAssertTrue(store.agents.isEmpty)
        XCTAssertEqual(store.loadError, .loadFailed)
        XCTAssertEqual(try Data(contentsOf: url), payload)

        store.reload()
        XCTAssertEqual(store.loadError, .loadFailed)
        XCTAssertEqual(try Data(contentsOf: url), payload)
    }

    @MainActor
    func testSpecialistAgentStoreFailedWriteRollsBackInMemoryMutation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-agents-\(UUID().uuidString)", isDirectory: true)
        let blockedParent = root.appendingPathComponent("blocked", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not-a-directory".utf8).write(to: blockedParent)
        let url = blockedParent.appendingPathComponent("agents.v1.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SpecialistAgentStore(storageURL: url)
        XCTAssertThrowsError(try store.create(SpecialistAgent(name: "Chief", mission: "Route"))) { error in
            XCTAssertEqual(error as? SpecialistAgentStoreError, .persistFailed)
        }
        XCTAssertTrue(store.agents.isEmpty)
    }

    @MainActor
    func testSpecialistAgentStoreUpdateAndDeleteUnknownIDFail() {
        let url = Self.temporaryStoreURL()
        defer { Self.removeStore(at: url) }
        let store = SpecialistAgentStore(storageURL: url)

        XCTAssertThrowsError(
            try store.update(SpecialistAgent(name: "Ghost", mission: "Missing"))
        ) { error in
            XCTAssertEqual(error as? SpecialistAgentStoreError, .agentNotFound)
        }
        XCTAssertThrowsError(try store.delete(id: UUID())) { error in
            XCTAssertEqual(error as? SpecialistAgentStoreError, .agentNotFound)
        }
    }

    private static func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-agents-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("agents.v1.json", isDirectory: false)
    }

    private static func removeStore(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
