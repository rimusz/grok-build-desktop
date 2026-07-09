import XCTest
@testable import GrokBuild

final class MemoryStoreTests: XCTestCase {
    private var tempBase: URL!

    override func setUpWithError() throws {
        tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-memory-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempBase { try? FileManager.default.removeItem(at: tempBase) }
    }

    private func write(_ contents: String, to relativePath: String, modified: Date? = nil) throws -> URL {
        let url = tempBase.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    // MARK: - Enumeration & grouping

    func testMissingBaseDirectoryReturnsEmpty() {
        let missing = tempBase.appendingPathComponent("does-not-exist")
        XCTAssertTrue(MemoryStore.load(base: missing).isEmpty)
    }

    func testEnumeratesGlobalWorkspaceAndSessions() throws {
        _ = try write("global facts", to: "MEMORY.md")
        _ = try write("proj facts", to: "myrepo-abc123/MEMORY.md")
        _ = try write("s1", to: "myrepo-abc123/sessions/2026-07-01-a.md", modified: Date(timeIntervalSince1970: 1_000))
        _ = try write("s2", to: "myrepo-abc123/sessions/2026-07-02-b.md", modified: Date(timeIntervalSince1970: 2_000))

        let files = MemoryStore.load(base: tempBase)

        XCTAssertEqual(files.filter { $0.scope == .global }.count, 1)
        XCTAssertEqual(files.filter { $0.scope == .workspace }.count, 1)
        XCTAssertEqual(files.filter { $0.scope == .session }.count, 2)

        // Global comes first.
        XCTAssertEqual(files.first?.scope, .global)

        // Workspace file precedes its session logs.
        let workspaceIdx = files.firstIndex { $0.scope == .workspace }!
        let firstSessionIdx = files.firstIndex { $0.scope == .session }!
        XCTAssertLessThan(workspaceIdx, firstSessionIdx)

        // Session logs are newest-first.
        let sessions = files.filter { $0.scope == .session }
        XCTAssertEqual(sessions.first?.title, "2026-07-02-b")
        XCTAssertEqual(sessions.last?.title, "2026-07-01-a")

        // Workspace label is the directory name.
        XCTAssertEqual(files.first { $0.scope == .workspace }?.workspaceLabel, "myrepo-abc123")
    }

    func testIgnoresNonMarkdownAndKeepsGlobalOnlyWhenNoWorkspaces() throws {
        _ = try write("global", to: "MEMORY.md")
        _ = try write("not md", to: "myrepo-abc123/sessions/index.sqlite")

        let files = MemoryStore.load(base: tempBase)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.scope, .global)
    }

    // MARK: - Deletion guard

    func testDeleteSessionFileRemovesIt() throws {
        let url = try write("s", to: "repo-1/sessions/log.md")
        let file = MemoryStore.load(base: tempBase).first { $0.scope == .session }
        let session = try XCTUnwrap(file)
        try MemoryStore.deleteSessionFile(session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDeleteRejectsGlobalAndWorkspaceFiles() throws {
        _ = try write("g", to: "MEMORY.md")
        _ = try write("w", to: "repo-1/MEMORY.md")
        let files = MemoryStore.load(base: tempBase)
        let global = try XCTUnwrap(files.first { $0.scope == .global })
        let workspace = try XCTUnwrap(files.first { $0.scope == .workspace })
        XCTAssertThrowsError(try MemoryStore.deleteSessionFile(global))
        XCTAssertThrowsError(try MemoryStore.deleteSessionFile(workspace))
        // Both files remain on disk.
        XCTAssertTrue(FileManager.default.fileExists(atPath: global.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.path))
    }

    // MARK: - Note appending (pure)

    func testAppendingNoteAddsHeadingWhenMissing() {
        let result = MemoryStore.appendingNote("- first note", to: "")
        XCTAssertTrue(result.contains("## Notes"))
        XCTAssertTrue(result.contains("- first note"))
    }

    func testAppendingNoteReusesExistingHeading() {
        let existing = "# Memory\n\n## Notes\n\n- old\n"
        let result = MemoryStore.appendingNote("- new", to: existing)
        XCTAssertEqual(result.components(separatedBy: "## Notes").count - 1, 1, "should not duplicate the heading")
        XCTAssertTrue(result.contains("- old"))
        XCTAssertTrue(result.contains("- new"))
    }

    func testAppendingNoteInsertsBeforeSubsequentSection() {
        let existing = "# Memory\n\n## Notes\n\n- old\n\n## Other Section\n\nsome content\n"
        let result = MemoryStore.appendingNote("- new", to: existing)
        XCTAssertEqual(result.components(separatedBy: "## Notes").count - 1, 1, "should not duplicate the heading")
        XCTAssertTrue(result.contains("- old"))
        XCTAssertTrue(result.contains("- new"))
        XCTAssertTrue(result.contains("## Other Section"))
        // The new entry must appear before the subsequent section
        let newRange = result.range(of: "- new")!
        let otherRange = result.range(of: "## Other Section")!
        XCTAssertLessThan(newRange.lowerBound, otherRange.lowerBound, "new note should appear before ## Other Section")
    }

    func testAppendGlobalNoteCreatesFileAndReindexablePath() throws {
        let url = tempBase.appendingPathComponent("MEMORY.md")
        let written = try MemoryStore.appendGlobalNote("staging uses eu-west", to: url)
        XCTAssertEqual(written, url)
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("staging uses eu-west"))
        XCTAssertTrue(contents.contains("## Notes"))
    }

    func testAppendGlobalNoteRejectsEmpty() {
        let url = tempBase.appendingPathComponent("MEMORY.md")
        XCTAssertThrowsError(try MemoryStore.appendGlobalNote("   ", to: url))
    }
}
