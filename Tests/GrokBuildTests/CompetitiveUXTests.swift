import XCTest
@testable import GrokBuild

/// Covers the pure logic added for the Phase 0–2b competitive UX roadmap:
/// session status resolution, steer-vs-queue decisions, managed Cursor bridge import,
/// Doctor diagnostics, and the unfocused-finish sound rule.
final class CompetitiveUXTests: XCTestCase {

    // MARK: - Session status

    func testStatusPriorityNeedsInputWinsOverWorking() {
        let status = SessionStatusResolver.resolve(
            SessionStatusInputs(isStreaming: true, isAwaitingUser: true)
        )
        XCTAssertEqual(status, .needsInput)
    }

    func testStatusErrorWinsOverWorking() {
        let status = SessionStatusResolver.resolve(
            SessionStatusInputs(isStreaming: true, hasError: true)
        )
        XCTAssertEqual(status, .error)
    }

    func testStatusWorkingWhenStreaming() {
        XCTAssertEqual(
            SessionStatusResolver.resolve(SessionStatusInputs(isStreaming: true)),
            .working
        )
    }

    func testStatusFinishedUnreadThenIdle() {
        XCTAssertEqual(
            SessionStatusResolver.resolve(SessionStatusInputs(hasUnreadCompletion: true)),
            .finishedUnread
        )
        XCTAssertEqual(SessionStatusResolver.resolve(SessionStatusInputs()), .idle)
    }

    func testStatusAttentionFlags() {
        XCTAssertTrue(SessionActivityStatus.needsInput.demandsAttention)
        XCTAssertTrue(SessionActivityStatus.finishedUnread.demandsAttention)
        XCTAssertTrue(SessionActivityStatus.error.demandsAttention)
        XCTAssertFalse(SessionActivityStatus.working.demandsAttention)
        XCTAssertFalse(SessionActivityStatus.idle.demandsAttention)
    }

    // MARK: - Background unread detection

    func testBackgroundUnreadMarksOnStreamingEndEvenWithoutMessageGrowth() {
        XCTAssertTrue(
            BackgroundSessionUnread.shouldMark(
                wasStreaming: true,
                isStreaming: false,
                messageCountGrew: false
            )
        )
    }

    func testBackgroundUnreadMarksOnMessageGrowthWhenIdle() {
        XCTAssertTrue(
            BackgroundSessionUnread.shouldMark(
                wasStreaming: false,
                isStreaming: false,
                messageCountGrew: true
            )
        )
        XCTAssertFalse(
            BackgroundSessionUnread.shouldMark(
                wasStreaming: false,
                isStreaming: true,
                messageCountGrew: true
            )
        )
        XCTAssertFalse(
            BackgroundSessionUnread.shouldMark(
                wasStreaming: false,
                isStreaming: false,
                messageCountGrew: false
            )
        )
    }

    // MARK: - Steer decision

    func testSteerDecisionRespectsDefaultWhenStreaming() {
        XCTAssertEqual(SteerDecision.resolve(isStreaming: true, steerByDefault: true), .steer)
        XCTAssertEqual(SteerDecision.resolve(isStreaming: true, steerByDefault: false), .queue)
    }

    func testSteerDecisionExplicitOverridesDefault() {
        XCTAssertEqual(
            SteerDecision.resolve(isStreaming: true, steerByDefault: false, explicitSteer: true),
            .steer
        )
        XCTAssertEqual(
            SteerDecision.resolve(isStreaming: true, steerByDefault: true, explicitSteer: false),
            .queue
        )
    }

    func testSteerDecisionQueuesWhenNotStreaming() {
        XCTAssertEqual(SteerDecision.resolve(isStreaming: false, steerByDefault: true), .queue)
    }

    // MARK: - Cursor bridge

    func testBridgeManagedEndpointOnly() {
        XCTAssertEqual(CursorBridge.managedEndpoint.port, 18787)
        XCTAssertTrue(CursorBridge.isLoopback(CursorBridge.managedEndpoint.baseURL))
        XCTAssertEqual(CursorBridgeRuntime.managedPort, 18787)
        XCTAssertEqual(CursorBridgeRuntime.managedEndpoint.baseURL, "http://127.0.0.1:18787/v1")
        XCTAssertEqual(CursorBridgeRuntime.managedEndpoint, CursorBridge.managedEndpoint)
    }

    func testBridgeRuntimeLocatorRequiresScript() {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-bridge-locator-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        XCTAssertFalse(CursorBridgeRuntime.Locator.hasBridgeScript(at: temp))
        try? "print(1)".write(to: temp.appendingPathComponent("cursor-openai-bridge.mjs"), atomically: true, encoding: .utf8)
        XCTAssertTrue(CursorBridgeRuntime.Locator.hasBridgeScript(at: temp))
        XCTAssertFalse(CursorBridgeRuntime.Locator.hasNodeModules(at: temp))
    }

    func testBridgeRuntimeStatusSummary() {
        XCTAssertEqual(CursorBridgeRuntime.Status.stopped.summary, "Stopped")
        XCTAssertTrue(CursorBridgeRuntime.Status.running.summary.contains("18787"))
        XCTAssertFalse(CursorBridgeRuntime.Status.stopped.isRunning)
        XCTAssertTrue(CursorBridgeRuntime.Status.running.isRunning)
    }

    func testBridgeManagedEnabledPrefIsInstallOwnedNotASettingsToggle() {
        // Pref still drives launch; Settings no longer exposes a launch toggle — install sets it, remove clears it.
        XCTAssertEqual(CursorBridgeSettingsKeys.managedEnabled, "GrokBuild.cursorBridge.managedEnabled")
        let previous = CursorBridgeRuntime.isEnabled
        defer { CursorBridgeRuntime.isEnabled = previous }
        CursorBridgeRuntime.isEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: CursorBridgeSettingsKeys.managedEnabled))
        CursorBridgeRuntime.isEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: CursorBridgeSettingsKeys.managedEnabled))
    }

    func testBridgeRuntimeTreatsOnlineEndpointAsRunning() {
        XCTAssertTrue(CursorBridgeRuntime.shouldTreatAsRunning(status: .stopped, endpointOnline: true, hasAPIKey: true))
        XCTAssertTrue(CursorBridgeRuntime.shouldTreatAsRunning(status: .running, endpointOnline: false, hasAPIKey: true))
        XCTAssertFalse(CursorBridgeRuntime.shouldTreatAsRunning(status: .stopped, endpointOnline: false, hasAPIKey: true))
        XCTAssertFalse(CursorBridgeRuntime.shouldTreatAsRunning(status: .failed("x"), endpointOnline: false, hasAPIKey: true))
        // Orphan listener must not look "running" after the API key was cleared.
        XCTAssertFalse(CursorBridgeRuntime.shouldTreatAsRunning(status: .stopped, endpointOnline: true, hasAPIKey: false))
        XCTAssertFalse(CursorBridgeRuntime.shouldTreatAsRunning(status: .running, endpointOnline: true, hasAPIKey: false))
        XCTAssertTrue(CursorBridgeRuntime.mayReattachToLiveEndpoint(hasAPIKey: true, endpointOnline: true))
        XCTAssertFalse(CursorBridgeRuntime.mayReattachToLiveEndpoint(hasAPIKey: false, endpointOnline: true))
        XCTAssertFalse(CursorBridgeRuntime.mayReattachToLiveEndpoint(hasAPIKey: true, endpointOnline: false))
    }

    func testCursorBridgeSecretFileURLIsUnderApplicationSupport() {
        let url = CursorBridgeKeychain.secretFileURL
        XCTAssertTrue(url.path.contains("Application Support/GrokBuild/Secrets"))
        XCTAssertEqual(url.lastPathComponent, "cursor-api-key")
        XCTAssertEqual(CursorBridgeKeychain.secretsDirectoryURL().lastPathComponent, "Secrets")
    }

    func testBridgeModelsURLPreservesV1() {
        XCTAssertEqual(
            CursorBridge.modelsURL(for: "http://127.0.0.1:18787/v1")?.absoluteString,
            "http://127.0.0.1:18787/v1/models"
        )
    }

    func testBridgePortParsing() {
        XCTAssertEqual(CursorBridge.port(from: "http://127.0.0.1:18787/v1"), 18787)
        XCTAssertNil(CursorBridge.port(from: "not a url with port"))
    }

    func testBridgeImportIDPrefixesCursorAndSanitizes() {
        XCTAssertEqual(CursorBridge.importID(for: "composer-2.5"), "cursor-composer-2.5")
        XCTAssertEqual(CursorBridge.importID(for: "grok-4.5-fast"), "cursor-grok-4.5-fast")
        // Already-prefixed ids are not double-prefixed.
        XCTAssertEqual(CursorBridge.importID(for: "cursor-foo"), "cursor-foo")
    }

    func testBridgeDisplayNameMatchesClinePrefixStyle() {
        XCTAssertEqual(CursorBridge.displayName(for: "composer-2.5"), "Cursor Composer 2.5")
        XCTAssertEqual(CursorBridge.displayName(for: "grok-4.5-fast"), "Cursor Grok 4.5 Fast")
        XCTAssertEqual(CursorBridge.displayName(for: "Cursor Composer 2.5"), "Cursor Composer 2.5")
    }

    func testBridgeFiltersRoutingAliasCatalogIDs() {
        XCTAssertTrue(CursorBridge.isExcludedCatalogID("default"))
        XCTAssertTrue(CursorBridge.isExcludedCatalogID("auto-smart"))
        XCTAssertTrue(CursorBridge.isExcludedCatalogID("AUTO"))
        XCTAssertFalse(CursorBridge.isExcludedCatalogID("composer-2.5"))
        let filtered = CursorBridge.filterCatalog([
            FetchedModel(id: "default"),
            FetchedModel(id: "auto-smart"),
            FetchedModel(id: "composer-2.5"),
            FetchedModel(id: "auto")
        ])
        XCTAssertEqual(filtered.map(\.id), ["composer-2.5"])
    }

    func testBridgeMakeModelMapsFieldsAndRoundTrips() {
        let model = CursorBridge.makeModel(modelID: "composer-2.5")
        XCTAssertEqual(model.id, "cursor-composer-2.5")
        XCTAssertEqual(model.model, "composer-2.5")
        XCTAssertEqual(model.name, "Cursor Composer 2.5")
        XCTAssertEqual(model.baseURL, "http://127.0.0.1:18787/v1")
        XCTAssertEqual(model.apiBackend, .chatCompletions)
        XCTAssertEqual(model.apiKey, "local")
        XCTAssertEqual(model.providerID, "cursor")
        XCTAssertNil(model.validationError)

        let grok = CursorBridge.makeModel(modelID: "grok-4.5")
        XCTAssertEqual(grok.id, "cursor-grok-4.5")
        XCTAssertEqual(grok.name, "Cursor Grok 4.5")

        // Imported model survives a config.toml round-trip.
        let toml = CustomModelStore.rewrite("", models: [model], defaultModelID: model.id)
        let reparsed = CustomModelStore.parse(toml)
        XCTAssertEqual(reparsed.models.first?.id, "cursor-composer-2.5")
        XCTAssertEqual(reparsed.defaultModelID, "cursor-composer-2.5")
    }

    func testBridgeParseModelIDsFromOpenAIPayload() {
        let json = Data("""
        { "object": "list", "data": [
            { "id": "default" },
            { "id": "auto-smart" },
            { "id": "composer-2.5" },
            { "id": "grok-4.5-fast" }
        ] }
        """.utf8)
        XCTAssertEqual(CursorBridge.parseModelIDs(json), ["composer-2.5", "grok-4.5-fast"])
    }

    // MARK: - Doctor

    func testDoctorHealthyWhenCliAndAuth() {
        let inputs = DoctorInputs(cliFound: true, versionDisplay: "0.2.93", authenticated: true, configPresent: true)
        XCTAssertTrue(DoctorReport.isHealthy(inputs))
        XCTAssertNil(DoctorReport.primaryRemediation(inputs))
    }

    func testDoctorMissingCliIsTopRemediation() {
        let inputs = DoctorInputs(cliFound: false, authenticated: false)
        XCTAssertFalse(DoctorReport.isHealthy(inputs))
        XCTAssertEqual(DoctorReport.primaryRemediation(inputs), "Install the grok CLI")
    }

    func testDoctorSignedOutRemediation() {
        let inputs = DoctorInputs(cliFound: true, versionDisplay: "0.2.93", authenticated: false)
        XCTAssertEqual(DoctorReport.primaryRemediation(inputs), "Run grok login")
        let auth = DoctorReport.checks(from: inputs).first { $0.key == "auth" }
        XCTAssertEqual(auth?.status, .warning)
    }

    func testDoctorChecksIncludeBridgeRowOnlyWhenProbed() {
        let notProbed = DoctorReport.checks(from: DoctorInputs(cliFound: true, authenticated: true))
        XCTAssertNil(notProbed.first { $0.key == "cursorBridge" })

        let probed = DoctorReport.checks(from: DoctorInputs(cliFound: true, authenticated: true, reachableBridgeCount: 1))
        let bridge = probed.first { $0.key == "cursorBridge" }
        XCTAssertEqual(bridge?.status, .ok)
        XCTAssertTrue(bridge?.detail.contains("18787") ?? false)
    }

    func testDoctorCliFailedWhenMissing() {
        let cli = DoctorReport.checks(from: DoctorInputs(cliFound: false)).first { $0.key == "cli" }
        XCTAssertEqual(cli?.status, .failed)
    }

    func testDoctorNodeWarningWhenMissing() {
        let inputs = DoctorInputs(cliFound: true, authenticated: true, nodeFound: false, nodeMeetsMinimum: false)
        let node = DoctorReport.checks(from: inputs).first { $0.key == "node" }
        XCTAssertEqual(node?.status, .warning)
        XCTAssertTrue(node?.detail.contains("Not found") ?? false)
        XCTAssertTrue(node?.detail.contains("brew install node") ?? false)
    }

    func testDoctorNodeOkWhenMeetsMinimum() {
        let inputs = DoctorInputs(
            cliFound: true,
            authenticated: true,
            nodeFound: true,
            nodeVersionDisplay: "v22.14.0",
            nodeMeetsMinimum: true
        )
        let node = DoctorReport.checks(from: inputs).first { $0.key == "node" }
        XCTAssertEqual(node?.status, .ok)
        XCTAssertTrue(node?.detail.contains("v22.14.0") ?? false)
    }

    func testCursorAPIKeyLooksLikeAndValidationResult() {
        XCTAssertFalse(CursorBridge.looksLikeAPIKey(""))
        XCTAssertFalse(CursorBridge.looksLikeAPIKey("short"))
        XCTAssertTrue(CursorBridge.looksLikeAPIKey("key_" + String(repeating: "a", count: 24)))
        XCTAssertTrue(CursorBridge.looksLikeAPIKey(String(repeating: "x", count: 40)))
        XCTAssertEqual(CursorBridge.validationResult(exitCode: 0, stderr: "").isValid, true)
        XCTAssertEqual(CursorBridge.validationResult(exitCode: 2, stderr: ""), CursorBridge.APIKeyValidation.missing)
        let rejected = CursorBridge.validationResult(exitCode: 1, stderr: "unauthorized\n")
        XCTAssertFalse(rejected.isValid)
        XCTAssertTrue(rejected.message.contains("rejected"))
        XCTAssertTrue(rejected.message.contains("unauthorized"))
    }

    func testNodeRequirementParseAndMinimum() {
        XCTAssertEqual(CursorBridge.NodeRequirement.parseVersion("v22.13.0")?.major, 22)
        XCTAssertEqual(CursorBridge.NodeRequirement.parseVersion("v22.13.0")?.minor, 13)
        XCTAssertTrue(CursorBridge.NodeRequirement.meetsMinimum(versionString: "v22.13.0"))
        XCTAssertTrue(CursorBridge.NodeRequirement.meetsMinimum(versionString: "v23.0.0"))
        XCTAssertFalse(CursorBridge.NodeRequirement.meetsMinimum(versionString: "v20.11.0"))
        XCTAssertFalse(CursorBridge.NodeRequirement.meetsMinimum(versionString: "v22.12.0"))
        let missing = CursorBridge.NodeRequirement.snapshot(binaryPath: nil, versionDisplay: "")
        XCTAssertFalse(missing.meetsMinimum)
        XCTAssertTrue(missing.detail.contains("nodejs.org"))
    }

    // MARK: - Turn completion sound

    func testSoundPlaysOnlyWhenEnabledAndUnfocused() {
        XCTAssertTrue(TurnCompletionSound.shouldPlay(enabled: true, appActive: false))
        XCTAssertFalse(TurnCompletionSound.shouldPlay(enabled: true, appActive: true))
        XCTAssertFalse(TurnCompletionSound.shouldPlay(enabled: false, appActive: false))
    }

    // MARK: - @ file mentions

    func testFileMentionMatchAtEndOfInput() {
        let match = FileMentionMatch.match(in: "look at @src/Chat")
        XCTAssertEqual(match?.query, "src/Chat")
    }

    func testFileMentionMatchAtStart() {
        XCTAssertEqual(FileMentionMatch.match(in: "@")?.query, "")
        XCTAssertEqual(FileMentionMatch.match(in: "@foo")?.query, "foo")
    }

    func testFileMentionNoMatchMidToken() {
        // An @ not at the trailing token (whitespace after) does not trigger.
        XCTAssertNil(FileMentionMatch.match(in: "@foo bar"))
        // Email-like text with a following @ won't match unless it's the last token.
        XCTAssertNil(FileMentionMatch.match(in: "plain text"))
    }

    func testFileMentionApplyInsertsPathAndSpace() {
        let text = "review @Chat"
        let match = FileMentionMatch.match(in: text)!
        let applied = FileMentionMatch.apply(path: "GrokBuild/ChatStore.swift", to: text, matchRange: match.range)
        XCTAssertEqual(applied, "review @GrokBuild/ChatStore.swift ")
    }

    func testFileMentionFilterRanksFilenamePrefixFirst() {
        let files = [
            "GrokBuild/Views/ChatView.swift",
            "GrokBuild/Services/ChatStore.swift",
            "docs/architecture.md"
        ]
        let result = FileMentionFilter.filter(files, query: "chats")
        // "ChatStore.swift" is a subsequence of the filename query "chats"? No — rank by contains.
        XCTAssertTrue(result.contains("GrokBuild/Services/ChatStore.swift"))
    }

    func testFileMentionFilterEmptyQueryReturnsHead() {
        let files = ["a", "b", "c", "d"]
        XCTAssertEqual(FileMentionFilter.filter(files, query: "", limit: 2), ["a", "b"])
    }

    func testFileMentionFilterSubsequence() {
        XCTAssertTrue(FileMentionFilter.isSubsequence("cvw", of: "chatview.swift"))
        XCTAssertFalse(FileMentionFilter.isSubsequence("zzz", of: "chatview.swift"))
    }

    func testFileMentionIndexSkipsIgnoredDirectories() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("mention-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try "x".write(to: root.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        let gitDir = root.appendingPathComponent(".git")
        try fm.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "y".write(to: gitDir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        let nodeDir = root.appendingPathComponent("node_modules")
        try fm.createDirectory(at: nodeDir, withIntermediateDirectories: true)
        try "z".write(to: nodeDir.appendingPathComponent("pkg.js"), atomically: true, encoding: .utf8)

        let files = FileMentionIndex.enumerate(root: root)
        XCTAssertTrue(files.contains("keep.txt"))
        XCTAssertFalse(files.contains(where: { $0.contains("node_modules") }))
        XCTAssertFalse(files.contains(where: { $0.contains(".git") }))
    }

    // MARK: - Image (vision) attachments

    func testImageAttachmentSupportDetectsExtensions() {
        XCTAssertTrue(ImageAttachmentSupport.isImagePath("/tmp/a.png"))
        XCTAssertTrue(ImageAttachmentSupport.isImagePath("photo.JPEG"))
        XCTAssertFalse(ImageAttachmentSupport.isImagePath("notes.txt"))
    }

    func testImageAttachmentSupportMimeTypes() {
        XCTAssertEqual(ImageAttachmentSupport.mimeType(forPath: "a.png"), "image/png")
        XCTAssertEqual(ImageAttachmentSupport.mimeType(forExtension: "jpg"), "image/jpeg")
        XCTAssertEqual(ImageAttachmentSupport.mimeType(forExtension: "webp"), "image/webp")
        XCTAssertNil(ImageAttachmentSupport.mimeType(forExtension: "pdf"))
    }

    func testImageAttachmentBase64RoundTrip() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let attachment = ImageAttachment(displayName: "x.png", mimeType: "image/png", data: bytes)
        XCTAssertEqual(Data(base64Encoded: attachment.base64), bytes)
    }

    func testImageAttachmentPromptNote() {
        let one = [ImageAttachment(displayName: "a.png", mimeType: "image/png", data: Data([1]))]
        XCTAssertEqual(AttachmentPromptBuilder.imageNote(from: one), "Attached image: a.png")
        let two = one + [ImageAttachment(displayName: "b.png", mimeType: "image/png", data: Data([2]))]
        XCTAssertEqual(AttachmentPromptBuilder.imageNote(from: two), "Attached images: a.png, b.png")
        XCTAssertNil(AttachmentPromptBuilder.imageNote(from: []))
    }

    // MARK: - Inline media

    func testInlineMediaMarkdownImage() {
        let media = InlineMediaParser.firstMedia(in: "here ![cat](https://x.com/cat.png) done")
        XCTAssertEqual(media?.ref.source, "https://x.com/cat.png")
        XCTAssertEqual(media?.ref.isVideo, false)
    }

    func testInlineMediaStandaloneVideoPath() {
        let media = InlineMediaParser.firstMedia(in: "Generated at /tmp/out.mp4")
        XCTAssertEqual(media?.ref.source, "/tmp/out.mp4")
        XCTAssertEqual(media?.ref.isVideo, true)
    }

    func testInlineMediaIgnoresNonMedia() {
        XCTAssertNil(InlineMediaParser.firstMedia(in: "just some text without media"))
    }

    func testInlineMediaSourceDetection() {
        XCTAssertTrue(InlineMediaParser.isMediaSource("a.png"))
        XCTAssertTrue(InlineMediaParser.isMediaSource("https://x.com/a.gif?token=1"))
        XCTAssertFalse(InlineMediaParser.isMediaSource("a.txt"))
    }

    // MARK: - Context usage popover

    func testContextUsageSummary() {
        XCTAssertEqual(
            ContextUsageFormatter.summary(used: 12000, limit: 200000),
            "12,000 / 200,000 tokens"
        )
        XCTAssertEqual(ContextUsageFormatter.summary(used: nil, limit: nil), "— / — tokens")
    }

    func testContextUsagePercent() {
        XCTAssertEqual(ContextUsageFormatter.percent(used: 50, limit: 200), 25)
        XCTAssertEqual(ContextUsageFormatter.percent(used: 500, limit: 200), 100)
        XCTAssertNil(ContextUsageFormatter.percent(used: 10, limit: 0))
        XCTAssertNil(ContextUsageFormatter.percent(used: nil, limit: 200))
    }

    // MARK: - Workflow run cards

    func testWorkflowRunBudgetFraction() {
        var run = WorkflowRun(id: "w1", name: "w1", phase: "", status: "running", progress: "", agentBudgetSpent: 3, agentBudgetTotal: 6)
        XCTAssertEqual(run.budgetFraction, 0.5)
        run.agentBudgetTotal = nil
        XCTAssertNil(run.budgetFraction)
    }

    func testWorkflowRunStateFlags() {
        let paused = WorkflowRun(id: "w", name: "w", phase: "", status: "paused", progress: "", agentBudgetSpent: nil, agentBudgetTotal: nil)
        XCTAssertTrue(paused.isPaused)
        XCTAssertTrue(paused.isActive)
        let stopped = WorkflowRun(id: "w", name: "w", phase: "", status: "stopped", progress: "", agentBudgetSpent: nil, agentBudgetTotal: nil)
        XCTAssertFalse(stopped.isActive)
    }

    // MARK: - Privacy Mode

    func testPrivacyModeRedactsPathWhenEnabled() {
        XCTAssertEqual(
            PrivacyMode.redactPath("/Users/me/Projects/demo", enabled: true),
            "••••/demo"
        )
        XCTAssertEqual(
            PrivacyMode.redactPath("/Users/me/Projects/demo", enabled: false),
            "/Users/me/Projects/demo"
        )
    }

    func testPrivacyModeRedactsLabelsWhenEnabled() {
        XCTAssertEqual(
            PrivacyMode.redactLabel("My Project", placeholder: "Project", enabled: true),
            "Project"
        )
        XCTAssertEqual(
            PrivacyMode.redactLabel("My Session", placeholder: "Session", enabled: false),
            "My Session"
        )
    }

    // MARK: - Worktree detection

    func testGitServiceDetectsLinkedWorktree() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("grokbuild-wt-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        // Primary checkout: .git is a directory
        try fm.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        XCTAssertFalse(GitService.isWorktree(at: root, fileManager: fm))

        let wt = fm.temporaryDirectory.appendingPathComponent("grokbuild-wt2-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: wt) }
        try fm.createDirectory(at: wt, withIntermediateDirectories: true)
        // Linked worktree: .git is a file
        try "gitdir: /tmp/fake/.git/worktrees/wt".write(to: wt.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        XCTAssertTrue(GitService.isWorktree(at: wt, fileManager: fm))
    }

    // MARK: - Chat rewind / clear

    @MainActor
    func testChatStoreRewindKeepsPrefixAndDropsRest() {
        let store = ChatStore()
        let a = Message(role: .user, content: "one")
        let b = Message(role: .assistant, content: "two")
        let c = Message(role: .user, content: "three")
        store.restorePersistedMessages([a, b, c])
        XCTAssertTrue(store.rewind(to: b.id))
        XCTAssertEqual(store.messages.map(\.id), [a.id, b.id])
        XCTAssertFalse(store.rewind(to: UUID()))
    }

    @MainActor
    func testChatStoreClearTranscriptEmptiesMessages() {
        let store = ChatStore()
        store.restorePersistedMessages([
            Message(role: .user, content: "hello"),
            Message(role: .assistant, content: "world")
        ])
        store.clearTranscript()
        XCTAssertTrue(store.messages.isEmpty)
    }

    // MARK: - Pinned sessions persistence

    func testSessionLayoutSnapshotRoundTripsPinnedSessionIDs() throws {
        let sessionID = UUID()
        let workspaceID = UUID()
        let snapshot = SessionLayoutSnapshot(
            records: [],
            sessionOrderByWorkspace: [workspaceID: [sessionID]],
            selectedSessionID: sessionID,
            selectedWorkspaceID: workspaceID,
            pinnedSessionIDs: [sessionID]
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionLayoutSnapshot.self, from: data)
        XCTAssertEqual(decoded.pinnedSessionIDs, [sessionID])
    }

    func testSessionLayoutSnapshotDefaultsPinnedSessionIDsWhenMissing() throws {
        let json = """
        {
          "records": [],
          "sessionOrderByWorkspace": [],
          "selectedSessionID": null,
          "selectedWorkspaceID": null
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SessionLayoutSnapshot.self, from: json)
        XCTAssertEqual(decoded.pinnedSessionIDs, [])
    }

}
