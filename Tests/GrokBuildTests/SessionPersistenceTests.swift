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
            selectedWorkspaceID: workspaceID
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
            selectedWorkspaceID: workspaceID
        )

        SessionLayoutStore.saveSessions(snapshot)
        let loaded = SessionLayoutStore.loadSessions()

        XCTAssertEqual(loaded.records, snapshot.records)
        XCTAssertEqual(loaded.sessionOrderByWorkspace, snapshot.sessionOrderByWorkspace)
        XCTAssertEqual(loaded.selectedSessionID, snapshot.selectedSessionID)
        XCTAssertEqual(loaded.selectedWorkspaceID, snapshot.selectedWorkspaceID)
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

    func testSessionNameStoreTrimsAndRemovesNames() {
        let id = UUID().uuidString

        SessionNameStore.setName("  Important session  ", for: id)
        XCTAssertEqual(SessionNameStore.name(for: id), "Important session")

        SessionNameStore.setName("   ", for: id)
        XCTAssertNil(SessionNameStore.name(for: id))
    }

    private func restore(_ data: Data?, forKey key: String) {
        if let data {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
