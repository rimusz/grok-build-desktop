import XCTest
@testable import GrokBuild

final class SessionPersistenceTests: XCTestCase {
    private let sessionLayoutKey = "GrokBuild.sessionLayout.v2"
    private let workspaceLayoutKey = "GrokBuild.workspaceLayout.v1"
    private let sessionNameKey = "grokbuild.sessionNames.v1"

    private var savedSessionLayoutData: Data?
    private var savedWorkspaceLayoutData: Data?
    private var savedSessionNames: Any?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        savedSessionLayoutData = defaults.data(forKey: sessionLayoutKey)
        savedWorkspaceLayoutData = defaults.data(forKey: workspaceLayoutKey)
        savedSessionNames = defaults.object(forKey: sessionNameKey)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        restore(savedSessionLayoutData, forKey: sessionLayoutKey)
        restore(savedWorkspaceLayoutData, forKey: workspaceLayoutKey)
        if let savedSessionNames {
            defaults.set(savedSessionNames, forKey: sessionNameKey)
        } else {
            defaults.removeObject(forKey: sessionNameKey)
        }
        super.tearDown()
    }

    func testSessionTitleUsesFirstUserMessageOnly() {
        let messages = [
            Message(role: .assistant, content: "Ignore assistant output"),
            Message(role: .user, content: "  implement saved sessions per project  "),
            Message(role: .user, content: "ignore later user message")
        ]

        XCTAssertEqual(SessionTitle.auto(from: messages), "implement saved sessions per project")
    }

    func testSessionTitleCollapsesWhitespaceAndTruncatesToEightWords() {
        let messages = [
            Message(
                role: .user,
                content: "one\n two   three\tfour five six seven eight nine ten"
            )
        ]

        XCTAssertEqual(SessionTitle.auto(from: messages), "one two three four five six seven eight…")
    }

    func testSessionTitleReturnsNilForEmptyOrMissingUserMessage() {
        XCTAssertNil(SessionTitle.auto(from: []))
        XCTAssertNil(SessionTitle.auto(from: [Message(role: .assistant, content: "hello")]))
        XCTAssertNil(SessionTitle.auto(from: [Message(role: .user, content: "   \n\t  ")]))
    }

    func testSavedSessionRecordCodablePreservesGrokIDAndTitle() throws {
        let workspaceID = UUID()
        let sessionID = UUID()
        let selectedID = UUID()
        let otherWorkspaceID = UUID()
        let otherSelectedID = UUID()
        let expandedWorkspaceID = UUID()
        let hiddenWorkspaceID = UUID()
        let date = Date(timeIntervalSince1970: 1_719_000_000)
        let snapshot = SessionLayoutSnapshot(
            records: [
                SavedSessionRecord(
                    id: sessionID,
                    workspaceID: workspaceID,
                    grokSessionID: "019eef73-aadb-7b92-90a2-eff8825b3a0b",
                    title: "Generating Session Title for Test Query",
                    lastAccessed: date
                )
            ],
            sessionOrderByWorkspace: [workspaceID: [sessionID]],
            selectedSessionID: selectedID,
            selectedWorkspaceID: workspaceID,
            selectedSessionIDByWorkspace: [
                workspaceID: selectedID,
                otherWorkspaceID: otherSelectedID
            ],
            expandedSessionWorkspaceIDs: [expandedWorkspaceID],
            hiddenSessionWorkspaceIDs: [hiddenWorkspaceID]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionLayoutSnapshot.self, from: data)

        XCTAssertEqual(decoded.records.first?.id, sessionID)
        XCTAssertEqual(decoded.records.first?.workspaceID, workspaceID)
        XCTAssertEqual(decoded.records.first?.grokSessionID, "019eef73-aadb-7b92-90a2-eff8825b3a0b")
        XCTAssertEqual(decoded.records.first?.title, "Generating Session Title for Test Query")
        XCTAssertEqual(decoded.records.first?.lastAccessed, date)
        XCTAssertEqual(decoded.sessionOrderByWorkspace[workspaceID], [sessionID])
        XCTAssertEqual(decoded.selectedSessionID, selectedID)
        XCTAssertEqual(decoded.selectedWorkspaceID, workspaceID)
        XCTAssertEqual(decoded.selectedSessionIDByWorkspace[workspaceID], selectedID)
        XCTAssertEqual(decoded.selectedSessionIDByWorkspace[otherWorkspaceID], otherSelectedID)
        XCTAssertEqual(decoded.expandedSessionWorkspaceIDs, [expandedWorkspaceID])
        XCTAssertEqual(decoded.hiddenSessionWorkspaceIDs, [hiddenWorkspaceID])
    }

    func testSessionLayoutStoreRoundTripsSnapshot() {
        let workspaceID = UUID()
        let sessionID = UUID()
        let snapshot = SessionLayoutSnapshot(
            records: [
                SavedSessionRecord(
                    id: sessionID,
                    workspaceID: workspaceID,
                    grokSessionID: "019eef73-aadb-7b92-90a2-eff8825b3a0b",
                    title: "Saved title",
                    lastAccessed: Date(timeIntervalSince1970: 42)
                )
            ],
            sessionOrderByWorkspace: [workspaceID: [sessionID]],
            selectedSessionID: sessionID,
            selectedWorkspaceID: workspaceID,
            selectedSessionIDByWorkspace: [workspaceID: sessionID],
            expandedSessionWorkspaceIDs: [workspaceID],
            hiddenSessionWorkspaceIDs: [UUID()]
        )

        SessionLayoutStore.saveSessions(snapshot)
        let loaded = SessionLayoutStore.loadSessions()

        XCTAssertEqual(loaded.records, snapshot.records)
        XCTAssertEqual(loaded.sessionOrderByWorkspace, snapshot.sessionOrderByWorkspace)
        XCTAssertEqual(loaded.selectedSessionID, snapshot.selectedSessionID)
        XCTAssertEqual(loaded.selectedWorkspaceID, snapshot.selectedWorkspaceID)
        XCTAssertEqual(loaded.selectedSessionIDByWorkspace, snapshot.selectedSessionIDByWorkspace)
        XCTAssertEqual(loaded.expandedSessionWorkspaceIDs, snapshot.expandedSessionWorkspaceIDs)
        XCTAssertEqual(loaded.hiddenSessionWorkspaceIDs, snapshot.hiddenSessionWorkspaceIDs)
    }

    func testSessionLayoutSnapshotDecodesWithoutPerWorkspaceSelection() throws {
        let workspaceID = UUID()
        let sessionID = UUID()
        let json = """
        {
          "records": [],
          "sessionOrderByWorkspace": [],
          "selectedSessionID": "\(sessionID.uuidString)",
          "selectedWorkspaceID": "\(workspaceID.uuidString)"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SessionLayoutSnapshot.self, from: json)

        XCTAssertEqual(decoded.selectedSessionID, sessionID)
        XCTAssertEqual(decoded.selectedWorkspaceID, workspaceID)
        XCTAssertEqual(decoded.selectedSessionIDByWorkspace, [:])
        XCTAssertEqual(decoded.expandedSessionWorkspaceIDs, [])
        XCTAssertEqual(decoded.hiddenSessionWorkspaceIDs, [])
    }

    func testWorkspaceLayoutStoreRoundTripsPinnedAndManualOrder() {
        let pinned = [UUID(), UUID()]
        let ordered = [UUID(), UUID(), UUID()]
        let snapshot = WorkspaceLayoutSnapshot(
            pinnedWorkspaceIDs: pinned,
            workspaceOrder: ordered
        )

        SessionLayoutStore.saveWorkspaceLayout(snapshot)
        let loaded = SessionLayoutStore.loadWorkspaceLayout()

        XCTAssertEqual(loaded.pinnedWorkspaceIDs, pinned)
        XCTAssertEqual(loaded.workspaceOrder, ordered)
    }

    func testWorkspaceAgentSettingsRoundTripPerProject() {
        let workspaceID = UUID()
        let settings = WorkspaceAgentSettings(
            model: "grok-composer-2.5-fast",
            reasoningEffort: "high"
        )

        SessionLayoutStore.saveAgentSettings(settings, for: workspaceID)

        XCTAssertEqual(SessionLayoutStore.agentSettings(for: workspaceID), settings)

        SessionLayoutStore.removeAgentSettings(for: workspaceID)
        XCTAssertEqual(SessionLayoutStore.agentSettings(for: workspaceID), WorkspaceAgentSettings())
    }

    func testWorkspaceLayoutSnapshotDecodesWithoutAgentSettings() throws {
        let pinned = UUID()
        let ordered = UUID()
        let json = """
        {
          "pinnedWorkspaceIDs": ["\(pinned.uuidString)"],
          "workspaceOrder": ["\(ordered.uuidString)"]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WorkspaceLayoutSnapshot.self, from: json)

        XCTAssertEqual(decoded.pinnedWorkspaceIDs, [pinned])
        XCTAssertEqual(decoded.workspaceOrder, [ordered])
        XCTAssertEqual(decoded.agentSettingsByWorkspace, [:])
    }

    func testSessionNameStoreTrimsAndRemovesNames() {
        let id = UUID().uuidString

        SessionNameStore.setName("  Important session  ", for: id)
        XCTAssertEqual(SessionNameStore.name(for: id), "Important session")

        SessionNameStore.setName("   ", for: id)
        XCTAssertNil(SessionNameStore.name(for: id))
    }

    func testSessionMessageStoreRoundTripsTranscript() {
        let sessionID = UUID()
        let messages = [
            Message(role: .user, content: "hello"),
            Message(role: .assistant, content: "world")
        ]

        SessionMessageStore.save(messages, for: sessionID)
        XCTAssertEqual(SessionMessageStore.messages(for: sessionID), messages)

        SessionMessageStore.remove(for: sessionID)
        XCTAssertTrue(SessionMessageStore.messages(for: sessionID).isEmpty)
    }

    func testSessionMessageStoreSkipsLegacyResumeNotes() {
        let sessionID = UUID()
        let messages = [
            Message(role: .system, content: "Resumed session 019f281a-f002-7510-ab76-5244728404b6."),
            Message(role: .user, content: "real message")
        ]

        SessionMessageStore.save(messages, for: sessionID)
        let loaded = SessionMessageStore.messages(for: sessionID)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.content, "real message")

        SessionMessageStore.remove(for: sessionID)
    }

    @MainActor
    func testChatStoreMarksResumedSessionTabFromSavedGrokID() {
        let store = ChatStore()
        let workspace = Workspace(name: "demo", path: URL(fileURLWithPath: "/tmp/demo"))
        store.prepare(workspace: workspace, savedGrokSessionID: "019eef73-aadb-7b92-90a2-eff8825b3a0b")
        XCTAssertTrue(store.isResumedSessionTab)
    }

    // MARK: - Session restore selection

    func testSessionHasContentIncludesPersistedTranscript() {
        let sessionID = UUID()
        SessionMessageStore.save([Message(role: .user, content: "hello")], for: sessionID)
        defer { SessionMessageStore.remove(for: sessionID) }

        XCTAssertTrue(
            SessionRestorePolicy.sessionHasContent(
                hasUserMessages: false,
                liveGrokSessionID: nil,
                savedGrokSessionID: nil,
                sessionID: sessionID
            )
        )
    }

    func testRecentSessionOrderSortsByLastAccessedDescending() {
        let older = UUID()
        let newer = UUID()
        let workspaceID = UUID()
        let records = [
            SavedSessionRecord(
                id: older,
                workspaceID: workspaceID,
                grokSessionID: nil,
                title: nil,
                lastAccessed: Date(timeIntervalSince1970: 100)
            ),
            SavedSessionRecord(
                id: newer,
                workspaceID: workspaceID,
                grokSessionID: nil,
                title: nil,
                lastAccessed: Date(timeIntervalSince1970: 200)
            )
        ]

        XCTAssertEqual(SessionRestorePolicy.recentSessionOrder(from: records), [newer, older])
    }

    func testPreferredSessionIDHonorsSavedSelectionEvenWhenEmpty() {
        let workspaceID = UUID()
        let emptySession = UUID()
        let contentSession = UUID()
        let snapshot = SessionLayoutSnapshot(
            records: [],
            sessionOrderByWorkspace: [workspaceID: [emptySession, contentSession]],
            selectedSessionID: emptySession,
            selectedWorkspaceID: workspaceID,
            selectedSessionIDByWorkspace: [workspaceID: emptySession]
        )

        let preferred = SessionRestorePolicy.preferredSessionID(
            for: workspaceID,
            saved: snapshot,
            liveSessionIDsInWorkspace: [emptySession, contentSession],
            currentSelectedSessionID: nil,
            currentSelectedWorkspaceID: nil,
            recentSessionOrder: [],
            hasContent: { $0 == contentSession }
        )

        XCTAssertEqual(preferred, emptySession)
    }

    func testRestoreSelectedSessionIDSkipsEmptySavedSelection() {
        let workspaceID = UUID()
        let emptySession = UUID()
        let contentSession = UUID()
        let snapshot = SessionLayoutSnapshot(
            records: [],
            sessionOrderByWorkspace: [:],
            selectedSessionID: emptySession,
            selectedWorkspaceID: workspaceID
        )

        let restored = SessionRestorePolicy.restoreSelectedSessionID(
            saved: snapshot,
            workspaceID: workspaceID,
            liveSessionIDsInWorkspace: [emptySession, contentSession],
            hasTranscript: { $0 == contentSession },
            hasContent: { $0 == contentSession },
            preferredSessionID: { _ in contentSession }
        )

        XCTAssertEqual(restored, contentSession)
    }

    func testRestoreSelectedSessionIDPrefersTranscriptOverGrokOnlySavedTab() {
        let workspaceID = UUID()
        let grokOnlySession = UUID()
        let transcriptSession = UUID()
        let snapshot = SessionLayoutSnapshot(
            records: [
                SavedSessionRecord(
                    id: grokOnlySession,
                    workspaceID: workspaceID,
                    grokSessionID: "019f28a8-4d84",
                    title: "overview",
                    lastAccessed: Date(timeIntervalSince1970: 300)
                ),
                SavedSessionRecord(
                    id: transcriptSession,
                    workspaceID: workspaceID,
                    grokSessionID: "019f2896-700",
                    title: "overview copy",
                    lastAccessed: Date(timeIntervalSince1970: 100)
                )
            ],
            sessionOrderByWorkspace: [workspaceID: [grokOnlySession, transcriptSession]],
            selectedSessionID: grokOnlySession,
            selectedWorkspaceID: workspaceID
        )

        let restored = SessionRestorePolicy.restoreSelectedSessionID(
            saved: snapshot,
            workspaceID: workspaceID,
            liveSessionIDsInWorkspace: [grokOnlySession, transcriptSession],
            hasTranscript: { $0 == transcriptSession },
            hasContent: { $0 == grokOnlySession || $0 == transcriptSession },
            preferredSessionID: { _ in grokOnlySession }
        )

        XCTAssertEqual(restored, transcriptSession)
    }

    func testRestoreSelectedSessionIDKeepsSavedSelectionWhenItHasContent() {
        let workspaceID = UUID()
        let savedSession = UUID()
        let otherSession = UUID()
        let snapshot = SessionLayoutSnapshot(
            records: [],
            sessionOrderByWorkspace: [:],
            selectedSessionID: savedSession,
            selectedWorkspaceID: workspaceID
        )

        let restored = SessionRestorePolicy.restoreSelectedSessionID(
            saved: snapshot,
            workspaceID: workspaceID,
            liveSessionIDsInWorkspace: [savedSession, otherSession],
            hasTranscript: { $0 == savedSession },
            hasContent: { $0 == savedSession },
            preferredSessionID: { _ in otherSession }
        )

        XCTAssertEqual(restored, savedSession)
    }

    func testPreferredSessionIDKeepsCurrentSessionInSameWorkspace() {
        let workspaceID = UUID()
        let current = UUID()
        let other = UUID()
        let snapshot = SessionLayoutSnapshot(
            records: [],
            sessionOrderByWorkspace: [:],
            selectedSessionID: other,
            selectedWorkspaceID: workspaceID
        )

        let preferred = SessionRestorePolicy.preferredSessionID(
            for: workspaceID,
            saved: snapshot,
            liveSessionIDsInWorkspace: [current, other],
            currentSelectedSessionID: current,
            currentSelectedWorkspaceID: workspaceID,
            recentSessionOrder: [other, current],
            hasContent: { _ in true }
        )

        XCTAssertEqual(preferred, current)
    }

    func testSessionMessageStoreMergesOnPartialSave() {
        let sessionID = UUID()
        let original = [
            Message(role: .user, content: "hello"),
            Message(role: .assistant, content: "world")
        ]
        SessionMessageStore.save(original, for: sessionID)
        SessionMessageStore.save([Message(role: .system, content: "note")], for: sessionID)

        let loaded = SessionMessageStore.messages(for: sessionID)
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.filter { $0.role == .user }.first?.content, "hello")
        XCTAssertEqual(loaded.filter { $0.role == .assistant }.first?.content, "world")
        XCTAssertEqual(loaded.filter { $0.role == .system }.first?.content, "note")

        SessionMessageStore.remove(for: sessionID)
    }

    // MARK: - Stale grok session load

    func testStaleSessionLoadDetectsFSNotFound() {
        let error = NSError(
            domain: "ACP",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: "Path not found.",
                "acpErrorCode": "FS_NOT_FOUND"
            ]
        )
        XCTAssertTrue(GrokSessionLoadError.isStaleSessionMissing(error))
    }

    func testStaleSessionLoadIgnoresUnrelatedErrors() {
        let error = NSError(domain: "ACP", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Connection refused"
        ])
        XCTAssertFalse(GrokSessionLoadError.isStaleSessionMissing(error))
    }

    // MARK: - Session list parsing

    func testParseListOutputNormalizesNoSummaryPlaceholder() {
        let output = """
        SESSION ID                            CREATED     UPDATED     STATUS      SUMMARY
        019f191a-c344-7ac2-ac79-dd49cec5460a  2026-07-03  2026-07-03  both  Implement /voice Slash Command Feature
        019f191a-2795-74f1-a8a3-b1df0cf2d49f  2026-06-30  2026-06-30  local  (no summary)
        """

        let sessions = GrokSessionInfo.parseListOutput(output)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].summary, "Implement /voice Slash Command Feature")
        // The literal "(no summary)" placeholder normalizes to empty.
        XCTAssertEqual(sessions[1].summary, "")
    }

    // MARK: - Sessions cleanup ("Clear Empty")

    func testCleanableSessionRequiresNoIdentityAndNotInUse() {
        // Unnamed, no summary, not active, not live → safe to bulk-clear.
        XCTAssertTrue(SessionsBrowserPanel.isCleanableSession(
            summary: "   ", hasCustomName: false, isActive: false, isLive: false
        ))
    }

    func testCleanableSessionExcludesNamedSummarizedActiveOrLive() {
        // A summary protects the session.
        XCTAssertFalse(SessionsBrowserPanel.isCleanableSession(
            summary: "Implement feature", hasCustomName: false, isActive: false, isLive: false
        ))
        // A user-assigned name protects it.
        XCTAssertFalse(SessionsBrowserPanel.isCleanableSession(
            summary: "", hasCustomName: true, isActive: false, isLive: false
        ))
        // The active session is never cleared out from under the user.
        XCTAssertFalse(SessionsBrowserPanel.isCleanableSession(
            summary: "", hasCustomName: false, isActive: true, isLive: false
        ))
        // An open live tab is never cleared.
        XCTAssertFalse(SessionsBrowserPanel.isCleanableSession(
            summary: "", hasCustomName: false, isActive: false, isLive: true
        ))
    }

    // MARK: - Reasoning effort default inheritance

    func testResolveReasoningEffortInheritsGlobalDefaultWhenUnset() {
        // No per-project value → inherit the global default for new projects.
        XCTAssertEqual(ChatStore.resolveReasoningEffort(saved: nil, globalDefault: "high"), "high")
    }

    func testResolveReasoningEffortPrefersSavedValueIncludingDefault() {
        // An explicit per-project choice wins over the global default…
        XCTAssertEqual(ChatStore.resolveReasoningEffort(saved: "low", globalDefault: "high"), "low")
        // …including an explicit "Default" (empty string), which must not fall back.
        XCTAssertEqual(ChatStore.resolveReasoningEffort(saved: "", globalDefault: "high"), "")
    }

    // MARK: - Per-tab model

    func testSavedSessionRecordDecodesWithoutModel() throws {
        let record = SavedSessionRecord(
            id: UUID(),
            workspaceID: UUID(),
            lastAccessed: Date()
        )

        let decoded = try JSONDecoder().decode(
            SavedSessionRecord.self,
            from: JSONEncoder().encode(record)
        )

        XCTAssertNil(decoded.model)
    }

    func testSavedSessionRecordRoundTripsModel() throws {
        let record = SavedSessionRecord(
            id: UUID(),
            workspaceID: UUID(),
            grokSessionID: "abc",
            title: "Tab",
            model: "grok-build",
            lastAccessed: Date()
        )

        let decoded = try JSONDecoder().decode(SavedSessionRecord.self, from: JSONEncoder().encode(record))

        XCTAssertEqual(decoded.model, "grok-build")
    }

    func testSessionTabModelPolicyPrefersTabOverWorkspaceDefault() {
        XCTAssertEqual(
            SessionTabModelPolicy.resolvedModel(
                tabModel: "mini-max",
                workspaceDefault: "grok-composer-2.5-fast",
                appDefault: "grok-build"
            ),
            "mini-max"
        )
        XCTAssertEqual(
            SessionTabModelPolicy.resolvedModel(
                tabModel: nil,
                workspaceDefault: "grok-composer-2.5-fast",
                appDefault: "grok-build"
            ),
            "grok-composer-2.5-fast"
        )
        XCTAssertEqual(
            SessionTabModelPolicy.resolvedModel(
                tabModel: "  ",
                workspaceDefault: nil,
                appDefault: "grok-build"
            ),
            "grok-build"
        )
    }

    private func restore(_ data: Data?, forKey key: String) {
        if let data {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
