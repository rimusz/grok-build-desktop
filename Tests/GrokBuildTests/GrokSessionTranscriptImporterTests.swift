import XCTest
@testable import GrokBuild

final class GrokSessionTranscriptImporterTests: XCTestCase {
    private var savedGrokHome: URL!

    override func setUp() {
        super.setUp()
        savedGrokHome = GrokSessionTranscriptImporter.grokHomeDirectory
    }

    override func tearDown() {
        GrokSessionTranscriptImporter.grokHomeDirectory = savedGrokHome
        super.tearDown()
    }

    func testEncodeWorkspacePathMatchesGrokLayout() {
        let workspace = URL(fileURLWithPath: "/Users/demo/helm-oci-plugin/")
        XCTAssertEqual(
            GrokSessionTranscriptImporter.encodeWorkspacePath(workspace),
            "%2FUsers%2Fdemo%2Fhelm-oci-plugin"
        )
    }

    func testChatHistoryURLUsesEncodedWorkspaceAndSessionID() {
        let workspace = URL(fileURLWithPath: "/tmp/demo")
        let url = GrokSessionTranscriptImporter.chatHistoryURL(
            workspacePath: workspace,
            grokSessionID: "019eef73-aadb-7b92-90a2-eff8825b3a0b"
        )
        XCTAssertEqual(
            url?.path,
            "\(NSHomeDirectory())/.grok/sessions/%2Ftmp%2Fdemo/019eef73-aadb-7b92-90a2-eff8825b3a0b/chat_history.jsonl"
        )
    }

    func testImportMessagesExtractsUserQueryAndAssistantText() throws {
        let jsonl = """
        {"type":"system","content":"bootstrap"}
        {"type":"user","content":[{"type":"text","text":"<user_query>Fix the helm plugin</user_query>"}]}
        {"type":"assistant","content":"On it."}
        {"type":"reasoning","content":"hidden"}
        {"type":"tool_call","content":"ignored"}
        """
        let file = try writeTempJSONL(jsonl)

        let messages = GrokSessionTranscriptImporter.importMessages(from: file)

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[0].content, "Fix the helm plugin")
        XCTAssertEqual(messages[1].role, .assistant)
        XCTAssertEqual(messages[1].content, "On it.")
        XCTAssertTrue(GrokSessionTranscriptImporter.hasRecoverableTranscript(at: file))
    }

    func testImportSkipsSyntheticSystemReminderOnlyUserRows() throws {
        let jsonl = """
        {"type":"user","content":[{"type":"text","text":"<system-reminder>follow the rules</system-reminder>"}]}
        """
        let file = try writeTempJSONL(jsonl)

        XCTAssertTrue(GrokSessionTranscriptImporter.importMessages(from: file).isEmpty)
        XCTAssertFalse(GrokSessionTranscriptImporter.hasRecoverableTranscript(at: file))
    }

    func testImportStripsRedactedThinkingFromAssistant() throws {
        let open = "<" + "redacted_thinking" + ">"
        let close = "</" + "redacted_thinking" + ">"
        let jsonl = """
        {"type":"assistant","content":"\(open)hidden\(close)Visible answer"}
        """
        let file = try writeTempJSONL(jsonl)

        let messages = GrokSessionTranscriptImporter.importMessages(from: file)
        XCTAssertEqual(messages.first?.content, "Visible answer")
    }

    func testRecoverIfNeededImportsWhenLocalTranscriptEmpty() throws {
        let sessionID = UUID()
        defer { SessionMessageStore.remove(for: sessionID) }

        let grokHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-test-\(UUID().uuidString)", isDirectory: true)
        GrokSessionTranscriptImporter.grokHomeDirectory = grokHome
        defer { try? FileManager.default.removeItem(at: grokHome) }

        let workspace = URL(fileURLWithPath: "/tmp/recovery-demo")
        let grokID = "019eef73-aadb-7b92-90a2-eff8825b3a0b"
        let historyURL = GrokSessionTranscriptImporter.chatHistoryURL(
            workspacePath: workspace,
            grokSessionID: grokID
        )!
        try FileManager.default.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {"type":"user","content":[{"type":"text","text":"hello"}]}
        {"type":"assistant","content":"world"}
        """.write(to: historyURL, atomically: true, encoding: .utf8)

        let recovered = SessionTranscriptRecovery.recoverIfNeeded(
            sessionID: sessionID,
            grokSessionID: grokID,
            workspacePath: workspace,
            currentMessages: []
        )

        XCTAssertEqual(recovered?.count, 2)
        XCTAssertEqual(SessionMessageStore.messages(for: sessionID).count, 2)
    }

    func testRecoverIfNeededSkipsStaleFallbackOnlyTabWithStubHistory() throws {
        let sessionID = UUID()
        defer { SessionMessageStore.remove(for: sessionID) }

        let grokHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-test-\(UUID().uuidString)", isDirectory: true)
        GrokSessionTranscriptImporter.grokHomeDirectory = grokHome
        defer { try? FileManager.default.removeItem(at: grokHome) }

        let workspace = URL(fileURLWithPath: "/tmp/stale-only")
        let grokID = "019eef73-stale-stub"
        let historyURL = GrokSessionTranscriptImporter.chatHistoryURL(
            workspacePath: workspace,
            grokSessionID: grokID
        )!
        try FileManager.default.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {"type":"system","content":"session started"}
        {"type":"user","content":[{"type":"text","text":"<system-reminder>rules</system-reminder>"}]}
        {"type":"assistant","content":""}
        """.write(to: historyURL, atomically: true, encoding: .utf8)

        let staleOnly = [
            Message(
                role: .system,
                content: "Previous grok session expired; started a fresh chat. Your saved transcript in this tab is still shown."
            )
        ]

        XCTAssertNil(
            SessionTranscriptRecovery.recoverIfNeeded(
                sessionID: sessionID,
                grokSessionID: grokID,
                workspacePath: workspace,
                currentMessages: staleOnly
            )
        )
        XCTAssertTrue(SessionMessageStore.messages(for: sessionID).isEmpty)
    }

    func testRecoverIfNeededReplacesShorterLocalTranscript() throws {
        let sessionID = UUID()
        defer { SessionMessageStore.remove(for: sessionID) }

        let grokHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-test-\(UUID().uuidString)", isDirectory: true)
        GrokSessionTranscriptImporter.grokHomeDirectory = grokHome
        defer { try? FileManager.default.removeItem(at: grokHome) }

        let workspace = URL(fileURLWithPath: "/tmp/truncated-recovery")
        let grokID = "019eef73-trunc-tail"
        let historyURL = GrokSessionTranscriptImporter.chatHistoryURL(
            workspacePath: workspace,
            grokSessionID: grokID
        )!
        try FileManager.default.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {"type":"user","content":[{"type":"text","text":"explain"}]}
        {"type":"assistant","content":"tell agents how to upgrade, wire Buzz, switch Spark models, and keep trading gated.\\n\\n**In one line:** AGNT takes the request."}
        """.write(to: historyURL, atomically: true, encoding: .utf8)

        let truncated = [
            Message(role: .user, content: "explain"),
            Message(role: .assistant, content: "tell agents how to upgrade, wire")
        ]
        XCTAssertTrue(
            SessionTranscriptRecovery.shouldReplace(current: truncated, with: [
                Message(role: .user, content: "explain"),
                Message(role: .assistant, content: "tell agents how to upgrade, wire Buzz")
            ])
        )

        let recovered = SessionTranscriptRecovery.recoverIfNeeded(
            sessionID: sessionID,
            grokSessionID: grokID,
            workspacePath: workspace,
            currentMessages: truncated
        )
        XCTAssertEqual(recovered?.last?.content.contains("In one line"), true)
        XCTAssertEqual(
            SessionMessageStore.messages(for: sessionID).last?.content.contains("In one line"),
            true
        )
    }

    func testStaleFallbackNoteIsNotRestorableTranscript() {
        let sessionID = UUID()
        defer { SessionMessageStore.remove(for: sessionID) }

        let staleNote = Message(
            role: .system,
            content: "Previous grok session expired; started a fresh chat. Your saved transcript in this tab is still shown."
        )
        XCTAssertTrue(SessionMessageStore.isStaleSessionFallbackNote(staleNote))

        SessionMessageStore.save([staleNote], for: sessionID)
        XCTAssertTrue(SessionMessageStore.messages(for: sessionID).isEmpty)
        XCTAssertFalse(SessionMessageStore.hasRestorableTranscript(for: sessionID))
        XCTAssertFalse(
            SessionRestorePolicy.sessionHasRestorableTranscript(
                hasUserMessages: false,
                sessionID: sessionID
            )
        )
    }

    private func writeTempJSONL(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat_history-\(UUID().uuidString).jsonl")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
