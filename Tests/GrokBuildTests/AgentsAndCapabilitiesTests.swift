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

    func testSubagentDeleteConfirmationCopy() {
        XCTAssertEqual(SubagentDeleteCopy.title(for: "scout"), "Delete scout?")
        XCTAssertEqual(SubagentDeleteCopy.title(for: "  "), "Delete subagent?")
        XCTAssertEqual(
            SubagentDeleteCopy.message,
            "This removes the custom subagent role and its instruction file. Existing sessions stay."
        )
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
            "Instructions are required."
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
            lastSessionID: sessionID,
            isPinned: true
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
        XCTAssertFalse(agent.isPinned)
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

    // MARK: - Specialist agent role linkage + starter crew

    func testRoleSyncUpsertsFromAgentAndPreservesUnmanagedRole() {
        let existing = [
            SubagentRole(
                name: "researcher",
                model: "grok-build",
                instruction: "Keep researching.",
                description: "Keep me",
                extraFields: ["default_capability_mode": "\"read-only\""]
            )
        ]
        let updated = SpecialistAgentRoleSync.upsertRoles(
            from: [
                SpecialistAgent(
                    name: "Chief",
                    mission: "Route work, keep scope, synthesize final answer",
                    roleName: "chief"
                )
            ],
            existing: existing
        )
        XCTAssertEqual(updated.count, 2)
        let researcher = updated.first { $0.name == "researcher" }
        XCTAssertEqual(researcher?.instruction, "Keep researching.")
        XCTAssertEqual(researcher?.extraFields["default_capability_mode"], "\"read-only\"")
        let chief = updated.first { $0.name == "chief" }
        XCTAssertEqual(chief?.description, "Route work, keep scope, synthesize final answer")
        XCTAssertTrue(chief?.instruction.contains("Instructions: Route work") == true)
        XCTAssertTrue(chief?.instruction.contains("You are Chief.") == true)
    }

    func testRoleSyncUpdatesExistingRoleInstructionAndKeepsExtraFields() {
        let existing = [
            SubagentRole(
                name: "chief",
                model: "grok-4",
                instruction: "Old mission.",
                extraFields: ["default_capability_mode": "\"workspace-write\""]
            )
        ]
        let updated = SpecialistAgentRoleSync.upsertRoles(
            from: [
                SpecialistAgent(name: "Chief", mission: "New mission", roleName: "chief")
            ],
            existing: existing
        )
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].model, "grok-4", "inherit/empty defaultModel must not wipe a custom role model")
        XCTAssertEqual(updated[0].instruction, SpecialistAgentRoleSync.promptInstruction(
            for: SpecialistAgent(name: "Chief", mission: "New mission", roleName: "chief")
        ))
        XCTAssertEqual(updated[0].extraFields["default_capability_mode"], "\"workspace-write\"")
    }

    func testRoleSyncAppliesDefaultModelWhenSet() {
        let updated = SpecialistAgentRoleSync.upsertRoles(
            from: [
                SpecialistAgent(
                    name: "Builder",
                    mission: "Implement",
                    roleName: "builder",
                    defaultModel: "grok-build"
                )
            ],
            existing: [SubagentRole(name: "builder", model: "", instruction: "old")]
        )
        XCTAssertEqual(updated.first?.model, "grok-build")
    }

    func testRoleSyncSkipsReservedRoleNames() {
        let updated = SpecialistAgentRoleSync.upsertRoles(
            from: [SpecialistAgent(name: "Explorer", mission: "Look around", roleName: "explore")],
            existing: []
        )
        XCTAssertTrue(updated.isEmpty)
    }

    func testStarterCrewTemplatesCoverTheFiveNamedAgents() {
        XCTAssertEqual(SpecialistAgentStarterCrew.names, ["Chief", "Scout", "Builder", "Verifier", "Operator"])
        XCTAssertEqual(SpecialistAgentStarterCrew.templates.count, 5)
        XCTAssertTrue(SpecialistAgentStarterCrew.templates.allSatisfy { $0.validationError == nil })
        XCTAssertEqual(SpecialistAgentStarterCrew.templates.first { $0.name == "Scout" }?.permissionProfile, .readOnly)
        XCTAssertEqual(SpecialistAgentStarterCrew.templates.first { $0.name == "Chief" }?.permissionProfile, .workspaceWrite)
        XCTAssertEqual(SpecialistAgentStarterCrew.templates.first { $0.name == "Operator" }?.computerUseEnabled, true)
    }

    @MainActor
    func testInstallStarterCrewWritesAgentsAndRoleFilesWithoutClobberingTOML() throws {
        let urls = Self.temporaryRoleHarness()
        defer { Self.removeStore(at: urls.agents); Self.removeRoleHarness(urls) }

        try FileManager.default.createDirectory(at: urls.prompts, withIntermediateDirectories: true)
        try "Keep researching.".write(
            to: urls.prompts.appendingPathComponent("researcher.md"),
            atomically: true,
            encoding: .utf8
        )
        let existing = """
        [models]
        default = "grok-build"

        [subagents.roles.researcher]
        description = "Keep me"
        model = "grok-build"
        default_capability_mode = "read-only"
        prompt_file = "\(urls.prompts.appendingPathComponent("researcher.md").path)"
        """
        try existing.write(to: urls.config, atomically: true, encoding: .utf8)

        let store = SpecialistAgentStore(storageURL: urls.agents)
        let created = try store.installStarterCrew(configURL: urls.config, promptsDirectory: urls.prompts)
        XCTAssertEqual(created.map(\.name), SpecialistAgentStarterCrew.names)
        XCTAssertTrue(store.hasStarterCrew)

        let toml = try String(contentsOf: urls.config, encoding: .utf8)
        XCTAssertTrue(toml.contains("[models]"))
        XCTAssertTrue(toml.contains("default = \"grok-build\""))
        XCTAssertTrue(toml.contains("[subagents.roles.researcher]"))
        XCTAssertTrue(toml.contains("default_capability_mode = \"read-only\""))
        XCTAssertTrue(toml.contains("[subagents.roles.chief]"))
        XCTAssertTrue(toml.contains("[subagents.roles.scout]"))
        XCTAssertTrue(toml.contains("[subagents.roles.builder]"))
        XCTAssertTrue(toml.contains("[subagents.roles.verifier]"))
        XCTAssertTrue(toml.contains("[subagents.roles.operator]"))

        let roles = SubagentRoleStore.parse(toml)
        XCTAssertEqual(roles.first { $0.name == "researcher" }?.instruction, "Keep researching.")
        let chief = try XCTUnwrap(roles.first { $0.name == "chief" })
        XCTAssertTrue(chief.instruction.contains("Instructions: Route work, keep scope, synthesize final answer"))
        XCTAssertEqual(
            try String(contentsOf: urls.prompts.appendingPathComponent("chief.md"), encoding: .utf8),
            chief.instruction
        )
    }

    @MainActor
    func testInstallStarterCrewIsIdempotent() throws {
        let urls = Self.temporaryRoleHarness()
        defer { Self.removeStore(at: urls.agents); Self.removeRoleHarness(urls) }

        let store = SpecialistAgentStore(storageURL: urls.agents)
        let first = try store.installStarterCrew(configURL: urls.config, promptsDirectory: urls.prompts)
        let second = try store.installStarterCrew(configURL: urls.config, promptsDirectory: urls.prompts)
        XCTAssertEqual(first.count, 5)
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(store.agents.count, 5)
        XCTAssertEqual(SpecialistAgentStore(storageURL: urls.agents).agents.count, 5)
    }

    @MainActor
    func testInstallStarterCrewRollsBackAgentsWhenRoleWriteFails() throws {
        let urls = Self.temporaryRoleHarness()
        defer { Self.removeStore(at: urls.agents); Self.removeRoleHarness(urls) }

        try FileManager.default.createDirectory(
            at: urls.root.appendingPathComponent("blocked-parent", isDirectory: true),
            withIntermediateDirectories: true
        )
        let blockedConfigParent = urls.root.appendingPathComponent("blocked-config", isDirectory: false)
        try Data("not-a-directory".utf8).write(to: blockedConfigParent)
        let blockedConfig = blockedConfigParent.appendingPathComponent("config.toml")

        let store = SpecialistAgentStore(storageURL: urls.agents)
        XCTAssertThrowsError(
            try store.installStarterCrew(configURL: blockedConfig, promptsDirectory: urls.prompts)
        )
        XCTAssertTrue(store.agents.isEmpty)
        XCTAssertTrue(SpecialistAgentStore(storageURL: urls.agents).agents.isEmpty)
    }

    // MARK: - Specialist agent roster matching

    func testRosterSessionTitleAndLaunchSelection() {
        let agent = SpecialistAgent(name: "  Chief  ", mission: "Route work", roleName: "chief")
        XCTAssertEqual(SpecialistAgentRoster.sessionTitle(for: agent), "Chief")
        XCTAssertEqual(SpecialistAgentRoster.launchAgentSelection(for: agent), "chief")
        XCTAssertEqual(
            SpecialistAgentRoster.launchAgentSelection(
                for: SpecialistAgent(name: "Night Watch", mission: "Watch")
            ),
            "night-watch"
        )
    }

    func testRosterLiveBindingPrefersLastSessionInCurrentProject() {
        let last = UUID()
        let other = UUID()
        let workspace = UUID()
        let agent = SpecialistAgent(name: "Chief", mission: "Route", roleName: "chief", lastSessionID: last)
        let binding = SpecialistAgentRoster.liveBinding(
            for: agent,
            sessions: [
                .init(sessionID: last, workspaceID: workspace, agent: "chief", isWorking: true),
                .init(sessionID: other, workspaceID: workspace, agent: "chief", isWorking: false)
            ],
            currentWorkspaceID: workspace
        )
        XCTAssertEqual(binding?.sessionID, last)
        XCTAssertEqual(binding?.isWorking, true)
        XCTAssertNil(
            SpecialistAgentRoster.liveBinding(
                for: agent,
                sessions: [
                    .init(sessionID: last, workspaceID: UUID(), agent: "chief", isWorking: true)
                ],
                currentWorkspaceID: workspace
            )
        )
    }

    func testRosterLiveBindingFallsBackToRoleMatch() {
        let sessionID = UUID()
        let workspace = UUID()
        let agent = SpecialistAgent(name: "Scout", mission: "Research", roleName: "scout")
        let binding = SpecialistAgentRoster.liveBinding(
            for: agent,
            sessions: [
                .init(sessionID: sessionID, workspaceID: workspace, agent: "scout", isWorking: false)
            ],
            currentWorkspaceID: workspace
        )
        XCTAssertEqual(binding?.sessionID, sessionID)
        XCTAssertEqual(SpecialistAgentRoster.statusLabel(isWorking: false), "Idle")
        XCTAssertEqual(SpecialistAgentRoster.statusLabel(isWorking: true), "Working")
    }

    func testRosterLiveBindingPrefersMostRecentlyAccessedExplicitBinding() {
        let older = UUID()
        let newer = UUID()
        let workspace = UUID()
        let agent = SpecialistAgent(name: "Scout", mission: "Research", roleName: "scout")
        let binding = SpecialistAgentRoster.liveBinding(
            for: agent,
            sessions: [
                .init(
                    sessionID: older,
                    workspaceID: workspace,
                    agent: "scout",
                    isWorking: true,
                    specialistAgentID: agent.id,
                    lastAccessed: Date(timeIntervalSince1970: 10)
                ),
                .init(
                    sessionID: newer,
                    workspaceID: workspace,
                    agent: "scout",
                    isWorking: false,
                    specialistAgentID: agent.id,
                    lastAccessed: Date(timeIntervalSince1970: 20)
                )
            ],
            currentWorkspaceID: workspace
        )
        XCTAssertEqual(binding?.sessionID, newer)
        XCTAssertEqual(binding?.isWorking, true)
        XCTAssertTrue(
            SpecialistAgentRoster.isWorking(
                for: agent,
                sessions: [
                    .init(
                        sessionID: older,
                        workspaceID: workspace,
                        agent: "scout",
                        isWorking: true,
                        specialistAgentID: agent.id,
                        lastAccessed: Date(timeIntervalSince1970: 10)
                    ),
                    .init(
                        sessionID: newer,
                        workspaceID: workspace,
                        agent: "scout",
                        isWorking: false,
                        specialistAgentID: agent.id,
                        lastAccessed: Date(timeIntervalSince1970: 20)
                    )
                ],
                currentWorkspaceID: workspace
            )
        )
    }

    func testRosterLastBoundSessionFallsBackToMostRecentExplicitBinding() {
        let older = UUID()
        let newer = UUID()
        let agent = SpecialistAgent(name: "Scout", mission: "Research", roleName: "scout")
        XCTAssertEqual(
            SpecialistAgentRoster.lastBoundSessionID(
                for: agent,
                sessions: [
                    .init(
                        sessionID: older,
                        workspaceID: UUID(),
                        agent: "scout",
                        isWorking: false,
                        specialistAgentID: agent.id,
                        lastAccessed: Date(timeIntervalSince1970: 1)
                    ),
                    .init(
                        sessionID: newer,
                        workspaceID: UUID(),
                        agent: "scout",
                        isWorking: false,
                        specialistAgentID: agent.id,
                        lastAccessed: Date(timeIntervalSince1970: 2)
                    )
                ]
            ),
            newer
        )
        var remembered = agent
        remembered.lastSessionID = older
        XCTAssertEqual(
            SpecialistAgentRoster.lastBoundSessionID(
                for: remembered,
                sessions: [
                    .init(sessionID: older, workspaceID: UUID(), agent: "scout", isWorking: false),
                    .init(sessionID: newer, workspaceID: UUID(), agent: "scout", isWorking: false)
                ]
            ),
            older
        )
    }

    func testRosterSpecialistBindingFromAgentSelectionAndDelete() {
        let scout = SpecialistAgent(name: "Scout", mission: "Research", roleName: "scout")
        let builder = SpecialistAgent(name: "Builder", mission: "Ship", roleName: "builder")
        XCTAssertEqual(
            SpecialistAgentRoster.specialistID(matchingAgentSelection: "scout", in: [scout, builder]),
            scout.id
        )
        XCTAssertEqual(
            SpecialistAgentRoster.specialistID(matchingAgentSelection: "builder", in: [scout, builder]),
            builder.id
        )
        XCTAssertNil(SpecialistAgentRoster.specialistID(matchingAgentSelection: "explore", in: [scout, builder]))
        XCTAssertNil(SpecialistAgentRoster.specialistID(matchingAgentSelection: "", in: [scout, builder]))

        XCTAssertEqual(
            SpecialistAgentRoster.identity(for: scout.id, specialists: [scout, builder])?.name,
            "Scout"
        )
        XCTAssertNil(SpecialistAgentRoster.identity(for: scout.id, specialists: [builder]))
        XCTAssertNil(
            SpecialistAgentRoster.clearedSpecialistID(scout.id, deleted: scout.id)
        )
        XCTAssertEqual(
            SpecialistAgentRoster.clearedSpecialistID(builder.id, deleted: scout.id),
            builder.id
        )
    }

    func testRosterDuplicateNameAvoidsCollisions() {
        XCTAssertEqual(
            SpecialistAgentRoster.duplicateName(of: "Chief", existing: ["Chief"]),
            "Chief (copy)"
        )
        XCTAssertEqual(
            SpecialistAgentRoster.duplicateName(of: "Chief", existing: ["Chief", "Chief (copy)"]),
            "Chief (copy) 2"
        )
    }

    func testRosterFilterMatchesNameMissionAndRole() {
        let agent = SpecialistAgent(name: "Scout", mission: "Research briefs", roleName: "scout")
        XCTAssertTrue(SpecialistAgentRoster.matchesFilter("brief", agent: agent))
        XCTAssertTrue(SpecialistAgentRoster.matchesFilter("SCOUT", agent: agent))
        XCTAssertFalse(SpecialistAgentRoster.matchesFilter("builder", agent: agent))
    }

    func testSessionRoleMenuCopyDistinguishesRolesFromSpawnedSubagents() {
        XCTAssertEqual(SessionRoleMenu.header, "Run this session as")
        XCTAssertEqual(SessionRoleMenu.customRolesHeader, "Custom roles")
        XCTAssertEqual(
            SessionRoleMenu.customRolesExplanation,
            "Runs the whole session; does not spawn a subagent"
        )
        XCTAssertEqual(SessionRoleMenu.manageCustomRoles, "Manage custom roles…")
    }

    func testSessionRoleMenuResolvesRosterLinkedRoleIdentity() {
        let operatorAgent = SpecialistAgent(
            name: "Operator",
            mission: "Operate tools",
            glyph: "desktopcomputer",
            roleName: "operator"
        )
        let scout = SpecialistAgent(name: "Scout", mission: "Research", roleName: "scout")

        XCTAssertEqual(
            SessionRoleMenu.specialist(forRole: "operator", in: [scout, operatorAgent]),
            operatorAgent
        )
        XCTAssertNil(SessionRoleMenu.specialist(forRole: "reviewer", in: [scout, operatorAgent]))
    }

    func testRosterActiveIsPinnedOrLiveBound() {
        let pinned = SpecialistAgent(name: "Chief", mission: "Route", isPinned: true)
        let idle = SpecialistAgent(name: "Scout", mission: "Research")
        XCTAssertTrue(SpecialistAgentRoster.isActive(pinned, hasLiveSession: false))
        XCTAssertTrue(SpecialistAgentRoster.isActive(idle, hasLiveSession: true))
        XCTAssertFalse(SpecialistAgentRoster.isActive(idle, hasLiveSession: false))
    }

    func testRosterDisplayedDefaultsToActiveAndShowAllRevealsTheRest() {
        let pinned = SpecialistAgent(name: "Chief", mission: "Route", isPinned: true)
        let live = SpecialistAgent(name: "Scout", mission: "Research")
        let idle = SpecialistAgent(name: "Builder", mission: "Implement")
        let liveBoundIDs: Set<UUID> = [live.id]

        XCTAssertEqual(
            SpecialistAgentRoster.displayed(
                agents: [pinned, live, idle],
                showAll: false,
                liveBoundIDs: liveBoundIDs,
                query: ""
            ).map(\.name),
            ["Chief", "Scout"]
        )
        XCTAssertEqual(
            SpecialistAgentRoster.displayed(
                agents: [pinned, live, idle],
                showAll: true,
                liveBoundIDs: liveBoundIDs,
                query: ""
            ).map(\.name),
            ["Chief", "Scout", "Builder"]
        )
        XCTAssertEqual(
            SpecialistAgentRoster.displayed(
                agents: [pinned, live, idle],
                showAll: true,
                liveBoundIDs: liveBoundIDs,
                query: "build"
            ).map(\.name),
            ["Builder"]
        )
        XCTAssertTrue(
            SpecialistAgentRoster.showsEmptyActiveState(
                agents: [idle],
                showAll: false,
                liveBoundIDs: []
            )
        )
        XCTAssertFalse(
            SpecialistAgentRoster.showsEmptyActiveState(
                agents: [idle],
                showAll: true,
                liveBoundIDs: []
            )
        )
        XCTAssertFalse(
            SpecialistAgentRoster.showsEmptyActiveState(
                agents: [],
                showAll: false,
                liveBoundIDs: []
            )
        )
    }

    private static func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-agents-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("agents.v1.json", isDirectory: false)
    }

    private static func removeStore(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private static func temporaryRoleHarness() -> (root: URL, agents: URL, config: URL, prompts: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-roles-\(UUID().uuidString)", isDirectory: true)
        let agents = root.appendingPathComponent("agents.v1.json")
        let config = root.appendingPathComponent("config.toml")
        let prompts = root.appendingPathComponent("prompts", isDirectory: true)
        return (root, agents, config, prompts)
    }

    private static func removeRoleHarness(_ urls: (root: URL, agents: URL, config: URL, prompts: URL)) {
        try? FileManager.default.removeItem(at: urls.root)
    }
}
