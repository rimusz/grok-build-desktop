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

    func testNodeTLSKeepsExistingExtraCACerts() {
        let pem = "/tmp/existing-ca.pem"
        let resolved = CursorBridge.NodeTLS.resolvedExtraCACertsPath(
            environment: [CursorBridge.NodeTLS.extraCACertsKey: pem],
            home: "/Users/demo",
            fileExists: { $0 == pem }
        )
        XCTAssertEqual(resolved, pem)
    }

    func testNodeTLSPrefersGrokBuildOverrideThenWellKnownITCert() {
        let override = "/custom/corp.pem"
        let wellKnown = "/Users/demo/IT-Certs/package-route.pem"
        XCTAssertEqual(
            CursorBridge.NodeTLS.resolvedExtraCACertsPath(
                environment: [CursorBridge.NodeTLS.overrideKey: override],
                home: "/Users/demo",
                fileExists: { $0 == override || $0 == wellKnown }
            ),
            override
        )
        XCTAssertEqual(
            CursorBridge.NodeTLS.resolvedExtraCACertsPath(
                environment: [:],
                home: "/Users/demo",
                fileExists: { $0 == wellKnown }
            ),
            wellKnown
        )
        XCTAssertNil(
            CursorBridge.NodeTLS.resolvedExtraCACertsPath(
                environment: [:],
                home: "/Users/demo",
                fileExists: { _ in false }
            )
        )
    }

    func testNodeTLSApplyIsNoOpWithoutPEM() {
        var env = ["PATH": "/usr/bin"]
        CursorBridge.NodeTLS.apply(to: &env, home: "/Users/demo", fileExists: { _ in false })
        XCTAssertNil(env[CursorBridge.NodeTLS.extraCACertsKey])
        let child = CursorBridgeRuntime.nodeChildEnvironment(
            base: env,
            home: "/Users/demo",
            fileExists: { _ in false }
        )
        XCTAssertEqual(child["PATH"], "/usr/bin")
        XCTAssertNil(child[CursorBridge.NodeTLS.extraCACertsKey])
        let injected = CursorBridgeRuntime.nodeChildEnvironment(
            base: [:],
            home: "/Users/demo",
            fileExists: { $0 == "/Users/demo/IT-Certs/package-route.pem" }
        )
        XCTAssertEqual(injected[CursorBridge.NodeTLS.extraCACertsKey], "/Users/demo/IT-Certs/package-route.pem")
    }

    func testNodeTLSRewritesZscalerNetworkFailure() {
        let original = "fetch failed: Network request failed (UND_ERR_CONNECT_TIMEOUT)"
        let message = CursorBridge.NodeTLS.userFacingRejection(original)
        XCTAssertTrue(message.hasPrefix(original))
        XCTAssertTrue(message.contains("Zscaler"))
        XCTAssertTrue(message.contains("IT-Certs/package-route.pem"))
        XCTAssertEqual(CursorBridge.NodeTLS.userFacingRejection("Invalid User API Key"), "Invalid User API Key")
        let result = CursorBridge.validationResult(exitCode: 1, stderr: original)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.message.contains("UND_ERR_CONNECT_TIMEOUT"))
        XCTAssertTrue(result.message.contains("Zscaler"))
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

    func testCachePercentAndCachedLine() {
        XCTAssertEqual(ContextUsageFormatter.cachePercent(cached: 7639, input: 11954), 64)
        XCTAssertEqual(ContextUsageFormatter.cachePercent(cached: 0, input: 100), 0)
        XCTAssertNil(ContextUsageFormatter.cachePercent(cached: 10, input: 0))
        XCTAssertNil(ContextUsageFormatter.cachePercent(cached: nil, input: 100))
        XCTAssertEqual(
            ContextUsageFormatter.cachedLine(cached: 7639, input: 11954),
            "7,639 cached (64%)"
        )
        XCTAssertEqual(ContextUsageFormatter.cachedLine(cached: 0, input: 100), "0 cached (0%)")
        XCTAssertNil(ContextUsageFormatter.cachedLine(cached: nil, input: 100))
        XCTAssertEqual(ContextUsageFormatter.tokenCount(nil), "—")
        XCTAssertEqual(ContextUsageFormatter.tokenCount(12000), "12,000")
    }

    func testTurnUsageParseFromFlatMeta() {
        let result: [String: Any] = [
            "stopReason": "end_turn",
            "_meta": [
                "sessionId": "sess-1",
                "modelId": "grok-composer-2.5-fast",
                "inputTokens": 11954,
                "outputTokens": 36,
                "cachedReadTokens": 7639,
                "reasoningTokens": 0,
                "totalTokens": 11990
            ] as [String: Any]
        ]
        let usage = TurnTokenUsageParser.parse(from: result)
        XCTAssertEqual(usage?.inputTokens, 11954)
        XCTAssertEqual(usage?.outputTokens, 36)
        XCTAssertEqual(usage?.cachedReadTokens, 7639)
        XCTAssertEqual(usage?.reasoningTokens, 0)
        XCTAssertEqual(usage?.totalTokens, 11990)
        XCTAssertTrue(usage?.hasBreakdown == true)
    }

    func testTurnUsageParseFromNestedMetaUsage() {
        let result: [String: Any] = [
            "_meta": [
                "usage": [
                    "inputTokens": 1500,
                    "outputTokens": 200,
                    "cachedReadTokens": 1000,
                    "reasoningTokens": 75
                ] as [String: Any]
            ] as [String: Any]
        ]
        let usage = TurnTokenUsageParser.parse(from: result)
        XCTAssertEqual(usage?.inputTokens, 1500)
        XCTAssertEqual(usage?.cachedReadTokens, 1000)
        XCTAssertEqual(usage?.reasoningTokens, 75)
    }

    func testTurnUsageParsePrefersTopLevelUsage() {
        let result: [String: Any] = [
            "usage": [
                "inputTokens": 10,
                "outputTokens": 2,
                "cachedReadTokens": 4
            ] as [String: Any],
            "_meta": [
                "inputTokens": 999,
                "cachedReadTokens": 1
            ] as [String: Any]
        ]
        let usage = TurnTokenUsageParser.parse(from: result)
        XCTAssertEqual(usage?.inputTokens, 10)
        XCTAssertEqual(usage?.cachedReadTokens, 4)
    }

    func testTurnUsageIgnoresTotalTokensOnly() {
        let update: [String: Any] = [
            "_meta": ["totalTokens": 42_000] as [String: Any]
        ]
        XCTAssertNil(TurnTokenUsageParser.parse(from: update))
        XCTAssertNil(TurnTokenUsageParser.parse(fromSessionUpdate: [
            "update": update
        ]))
    }

    func testTurnUsageZeroCacheIsAMissNotMissing() {
        let result: [String: Any] = [
            "_meta": [
                "inputTokens": 100,
                "outputTokens": 10,
                "cachedReadTokens": 0,
                "reasoningTokens": 0
            ] as [String: Any]
        ]
        let usage = TurnTokenUsageParser.parse(from: result)
        XCTAssertEqual(usage?.cachedReadTokens, 0)
        XCTAssertTrue(usage?.hasBreakdown == true)
        XCTAssertEqual(ContextUsageFormatter.cachedLine(cached: usage?.cachedReadTokens, input: usage?.inputTokens), "0 cached (0%)")
    }

    func testTurnUsageParseNSNumberAndSessionUpdate() {
        let params: [String: Any] = [
            "update": [
                "_meta": [
                    "inputTokens": NSNumber(value: 80),
                    "cachedReadTokens": NSNumber(value: 50),
                    "outputTokens": NSNumber(value: 12)
                ] as [String: Any]
            ] as [String: Any]
        ]
        let usage = TurnTokenUsageParser.parse(fromSessionUpdate: params)
        XCTAssertEqual(usage?.inputTokens, 80)
        XCTAssertEqual(usage?.cachedReadTokens, 50)
        XCTAssertEqual(usage?.outputTokens, 12)
    }

    func testTurnUsageParseLiveGrokPromptResultJSON() throws {
        let raw: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 3,
            "result": [
                "stopReason": "end_turn",
                "_meta": [
                    "sessionId": "sess",
                    "totalTokens": 18150,
                    "modelId": "grok-4.6",
                    "inputTokens": 18107,
                    "outputTokens": 42,
                    "cachedReadTokens": 2944,
                    "reasoningTokens": 37,
                    "usage": [
                        "inputTokens": 18107,
                        "outputTokens": 42,
                        "totalTokens": 18149,
                        "cachedReadTokens": 2944,
                        "reasoningTokens": 37
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ]
        let data = try JSONSerialization.data(withJSONObject: raw)
        let obj = try JSONSerialization.jsonObject(with: data)
        let usage = TurnTokenUsageParser.parse(fromAny: obj)
        XCTAssertEqual(usage?.inputTokens, 18107)
        XCTAssertEqual(usage?.cachedReadTokens, 2944)
        XCTAssertEqual(usage?.outputTokens, 42)
        XCTAssertEqual(usage?.reasoningTokens, 37)
        XCTAssertEqual(
            ContextUsageFormatter.cachedLine(cached: usage?.cachedReadTokens, input: usage?.inputTokens),
            "2,944 cached (16%)"
        )
    }

    func testTurnUsageParseXaiTurnCompletedNotification() {
        let params: [String: Any] = [
            "sessionId": "sess",
            "update": [
                "sessionUpdate": "turn_completed",
                "usage": [
                    "inputTokens": 18107,
                    "outputTokens": 42,
                    "cachedReadTokens": 2944,
                    "reasoningTokens": 37
                ] as [String: Any]
            ] as [String: Any]
        ]
        let usage = TurnTokenUsageParser.parse(fromSessionUpdate: params)
        XCTAssertEqual(usage?.inputTokens, 18107)
        XCTAssertEqual(usage?.cachedReadTokens, 2944)
    }

    func testTurnUsageSnakeCaseUncachedPlusCacheIsFullPrompt() {
        let update: [String: Any] = [
            "sessionUpdate": "response_completed",
            "usage": [
                "input_tokens": 15163,
                "output_tokens": 42,
                "cache_read_input_tokens": 2944,
                "reasoning_tokens": 37
            ] as [String: Any]
        ]
        let usage = TurnTokenUsageParser.parse(from: update)
        XCTAssertEqual(usage?.inputTokens, 18107)
        XCTAssertEqual(usage?.cachedReadTokens, 2944)
        XCTAssertEqual(usage?.outputTokens, 42)
        XCTAssertEqual(
            ContextUsageFormatter.cachePercent(cached: usage?.cachedReadTokens, input: usage?.inputTokens),
            16
        )
    }

    func testTurnUsageParseCacheReadInputTokensAndOpenAIDetails() {
        let cacheRead = TurnTokenUsageParser.parse(from: [
            "usage": [
                "inputTokens": 200,
                "outputTokens": 10,
                "cacheReadInputTokens": 80
            ] as [String: Any]
        ])
        XCTAssertEqual(cacheRead?.cachedReadTokens, 80)

        let openai = TurnTokenUsageParser.parse(from: [
            "usage": [
                "prompt_tokens": 120,
                "completion_tokens": 9,
                "prompt_tokens_details": ["cached_tokens": 40] as [String: Any]
            ] as [String: Any]
        ])
        XCTAssertEqual(openai?.inputTokens, 120)
        XCTAssertEqual(openai?.cachedReadTokens, 40)
        XCTAssertEqual(openai?.outputTokens, 9)
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
    func testChatStoreClearTranscriptEmptiesMessagesAndClearsLastError() {
        let store = ChatStore()
        store.restorePersistedMessages([
            Message(role: .user, content: "hello"),
            Message(role: .assistant, content: "world")
        ])
        store.clearTranscript()
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertNil(store.lastError)
    }

    func testPinnedSessionIDsArePrunedToExistingRecords() {
        let kept = UUID()
        let stale = UUID()
        let recordIDs: Set<UUID> = [kept]
        let pinned = [kept, stale].filter { recordIDs.contains($0) }
        XCTAssertEqual(pinned, [kept])
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

    // MARK: - Dashboard grouping

    func testDashboardNeedsYouWinsOverDirtyAndFailed() {
        XCTAssertEqual(
            DashboardGrouping.group(DashboardGroupingInputs(
                isFailed: true,
                pendingUserCount: 1,
                dirtyCount: 3
            )),
            .needsYou
        )
        XCTAssertEqual(
            DashboardGrouping.group(DashboardGroupingInputs(hasUnreadCompletion: true, dirtyCount: 2)),
            .needsYou
        )
    }

    func testDashboardFailedThenWorkingThenReviewThenScheduled() {
        XCTAssertEqual(
            DashboardGrouping.group(DashboardGroupingInputs(isFailed: true)),
            .failed
        )
        XCTAssertEqual(
            DashboardGrouping.group(DashboardGroupingInputs(isStreaming: true, dirtyCount: 4, scheduledCount: 1)),
            .working
        )
        XCTAssertEqual(
            DashboardGrouping.group(DashboardGroupingInputs(isStarting: true)),
            .working
        )
        XCTAssertEqual(
            DashboardGrouping.group(DashboardGroupingInputs(isBusy: true)),
            .working
        )
        XCTAssertEqual(
            DashboardGrouping.group(DashboardGroupingInputs(dirtyCount: 2, scheduledCount: 1)),
            .needsReview
        )
        XCTAssertEqual(
            DashboardGrouping.group(DashboardGroupingInputs(scheduledCount: 1)),
            .scheduled
        )
        XCTAssertEqual(
            DashboardGrouping.group(DashboardGroupingInputs()),
            .idle
        )
    }

    func testDashboardSectionOrderMatchesGroupingPriority() {
        XCTAssertEqual(
            SessionDashboardEntry.Group.sectionOrder,
            [.needsYou, .failed, .working, .needsReview, .scheduled, .idle]
        )
        XCTAssertEqual(
            SessionDashboardEntry.Group.sectionOrder,
            Array(SessionDashboardEntry.Group.allCases)
        )
    }

    func testDashboardGitRefreshSkipsOtherProjectsAndDedupesPaths() {
        let current = UUID()
        let other = UUID()
        let shared = URL(fileURLWithPath: "/tmp/project")
        let worktree = URL(fileURLWithPath: "/tmp/project-review")
        let paths = DashboardGitRefresh.uniquePaths(
            sessions: [
                (current, shared),
                (current, shared),
                (current, worktree),
                (other, URL(fileURLWithPath: "/tmp/other")),
            ],
            currentWorkspaceID: current
        )
        XCTAssertEqual(paths.map(\.path), [shared.path, worktree.path])
        XCTAssertTrue(
            DashboardGitRefresh.uniquePaths(
                sessions: [(current, shared)],
                currentWorkspaceID: nil
            ).isEmpty
        )
    }

    func testDashboardScopeIsCurrentProjectOnly() {
        let current = UUID()
        let other = UUID()
        XCTAssertTrue(DashboardScope.isInCurrentProject(
            sessionWorkspaceID: current,
            currentWorkspaceID: current
        ))
        XCTAssertFalse(DashboardScope.isInCurrentProject(
            sessionWorkspaceID: other,
            currentWorkspaceID: current
        ))
        XCTAssertFalse(DashboardScope.isInCurrentProject(
            sessionWorkspaceID: current,
            currentWorkspaceID: nil
        ))
    }

    // MARK: - LRU pin for scheduled sessions

    func testConnectionCapKeepsSelectedMRUBusyIdleAndScheduled() {
        let selected = UUID()
        let mru = UUID()
        let scheduled = UUID()
        let busy = UUID()
        let idle = UUID()
        let ready = UUID()
        let recent = [selected, mru]

        XCTAssertFalse(
            ConnectionCapPolicy.shouldEvict(
                sessionID: selected,
                selectedSessionID: selected,
                recentOrder: recent,
                maxConnected: 2,
                connectionState: .ready,
                hasScheduledTasks: false
            )
        )
        XCTAssertFalse(
            ConnectionCapPolicy.shouldEvict(
                sessionID: mru,
                selectedSessionID: selected,
                recentOrder: recent,
                maxConnected: 2,
                connectionState: .ready,
                hasScheduledTasks: false
            )
        )
        XCTAssertFalse(
            ConnectionCapPolicy.shouldEvict(
                sessionID: scheduled,
                selectedSessionID: selected,
                recentOrder: recent,
                maxConnected: 2,
                connectionState: .ready,
                hasScheduledTasks: true
            )
        )
        XCTAssertFalse(
            ConnectionCapPolicy.shouldEvict(
                sessionID: busy,
                selectedSessionID: selected,
                recentOrder: recent,
                maxConnected: 2,
                connectionState: .busy,
                hasScheduledTasks: false
            )
        )
        XCTAssertFalse(
            ConnectionCapPolicy.shouldEvict(
                sessionID: idle,
                selectedSessionID: selected,
                recentOrder: recent,
                maxConnected: 2,
                connectionState: .idle,
                hasScheduledTasks: false
            )
        )
        XCTAssertTrue(
            ConnectionCapPolicy.shouldEvict(
                sessionID: ready,
                selectedSessionID: selected,
                recentOrder: recent,
                maxConnected: 2,
                connectionState: .ready,
                hasScheduledTasks: false
            )
        )
    }

    // MARK: - Named parallel session helpers

    func testParallelSessionSlugAndWorktreeDefaults() {
        XCTAssertEqual(ParallelSessionNaming.slug("Review Bot!"), "review-bot")
        XCTAssertEqual(ParallelSessionNaming.defaultBranch(fromName: "Review Bot"), "review-bot")
        XCTAssertEqual(ParallelSessionNaming.defaultBranch(fromName: "   "), "session")
        XCTAssertFalse(ParallelSessionNaming.isValidName("  "))
        XCTAssertTrue(ParallelSessionNaming.isValidName("Reviewer"))
        XCTAssertTrue(ParallelSessionNaming.isValidWorktree(branch: "feat", path: "/tmp/wt"))
        XCTAssertFalse(ParallelSessionNaming.isValidWorktree(branch: "", path: "/tmp/wt"))
        XCTAssertTrue(ParallelSessionNaming.isValidAutomation(interval: "1h", prompt: "triage"))
        XCTAssertFalse(ParallelSessionNaming.isValidAutomation(interval: "1h", prompt: " "))

        let project = URL(fileURLWithPath: "/Users/me/code/app")
        XCTAssertEqual(
            ParallelSessionNaming.defaultWorktreePath(projectPath: project, name: "Reviewer"),
            "/Users/me/code/app-reviewer"
        )
    }

    func testParallelSessionAndAutomationCopyExplainPurpose() {
        XCTAssertTrue(ParallelSessionCopy.summary.contains("two sessions"))
        XCTAssertTrue(ParallelSessionCopy.summary.contains("one-click"))
        XCTAssertTrue(ParallelSessionCopy.workspaceCaption.contains("worktree"))
        XCTAssertEqual(ParallelSessionCopy.windowTitle, "New Parallel Session")
        XCTAssertTrue(AutomationCopy.summary.contains("/loop"))
        XCTAssertTrue(AutomationCopy.limitation.contains("Quit"))
        XCTAssertEqual(AutomationCopy.windowTitle, "New Automation")
    }

    func testStringNilIfEmpty() {
        XCTAssertNil("  ".nilIfEmpty)
        XCTAssertEqual("role".nilIfEmpty, "role")
    }

    func testDashboardTitleSanitizesPromptDumpsAndCompactsRoles() {
        XCTAssertEqual(
            DashboardTitle.display("<user_info> OS Version: macos Shell: /bin/zsh Workspace Path:…"),
            DashboardTitle.untitled
        )
        XCTAssertEqual(DashboardTitle.display("  "), DashboardTitle.untitled)
        XCTAssertEqual(DashboardTitle.display("whats up?"), "whats up?")
        XCTAssertEqual(DashboardTitle.display("<html> table"), "<html> table")
        XCTAssertEqual(DashboardTitle.display("<3 thanks"), "<3 thanks")
        XCTAssertFalse(DashboardTitle.isPromptDump("<html>"))
        XCTAssertTrue(DashboardTitle.isPromptDump("<user_info> OS Version: macos"))
        XCTAssertEqual(DashboardTitle.compactRole("Default (grok build)"), "Default")
        XCTAssertEqual(DashboardTitle.compactRole("researcher"), "researcher")
        let long = String(repeating: "word ", count: 20)
        let displayed = DashboardTitle.display(long)
        XCTAssertTrue(displayed.hasSuffix("…"))
        XCTAssertLessThanOrEqual(displayed.count, DashboardTitle.maxCharacters + 1)
    }

    func testGitServiceReadsCurrentBranchFromHead() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("grokbuild-head-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "ref: refs/heads/feature/status-split\n".write(
            to: root.appendingPathComponent(".git/HEAD"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(GitService.currentBranch(in: root), "feature/status-split")

        try "abc123def456\n".write(
            to: root.appendingPathComponent(".git/HEAD"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(GitService.currentBranch(in: root), "abc123d")
    }

    // MARK: - Auto accept (CLI yolo)

    func testAutoAcceptModeLabelsHideYolo() {
        XCTAssertEqual(AgentMode.yolo.displayName, "Auto accept")
        XCTAssertTrue(AgentMode.yolo.isAutoAccept)
        XCTAssertEqual(AgentMode.agent.displayName, "Agent")
        XCTAssertEqual(AgentMode.plan.displayName, "Plan")
        XCTAssertFalse(AgentMode.agent.isAutoAccept)
        XCTAssertEqual(AgentMode(rawValue: "default").displayName, "Agent")
        XCTAssertEqual(AgentMode.yolo.systemImage, "bolt.fill")
    }

    func testPermissionAutoApprovePrefersAllowAlways() {
        let options = [
            PermissionOption(id: "reject", kind: "reject_once", name: "Reject"),
            PermissionOption(id: "once", kind: "allow_once", name: "Allow once"),
            PermissionOption(id: "always", kind: "allow_always", name: "Allow always"),
        ]
        XCTAssertEqual(PermissionAutoApprove.preferredOption(in: options)?.id, "always")
    }

    func testPermissionAutoApproveFallsBackToAllowOnce() {
        let options = [
            PermissionOption(id: "reject", kind: "reject_once", name: "Reject"),
            PermissionOption(id: "once", kind: "allow_once", name: "Allow once"),
        ]
        XCTAssertEqual(PermissionAutoApprove.preferredOption(in: options)?.id, "once")
    }

    func testPermissionAutoApproveIgnoresRejectAlways() {
        let options = [
            PermissionOption(id: "reject-always", kind: "reject_always", name: "Reject always"),
            PermissionOption(id: "once", kind: "allow_once", name: "Allow once"),
        ]
        XCTAssertEqual(PermissionAutoApprove.preferredOption(in: options)?.id, "once")
    }

    func testPermissionAutoApproveEmptyOptions() {
        XCTAssertNil(PermissionAutoApprove.preferredOption(in: []))
    }

}
