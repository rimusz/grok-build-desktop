import XCTest
@testable import GrokBuild

final class GrokAuthProbeTests: XCTestCase {
    func testHasCachedCredentialsTrueWhenFileHasContent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokAuthProbeTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try "{\"token\":\"abc\"}".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(GrokAuthProbe.hasCachedCredentials(at: url))
    }

    func testHasCachedCredentialsFalseWhenEmptyObject() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokAuthProbeTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try "{}".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertFalse(GrokAuthProbe.hasCachedCredentials(at: url))
    }

    func testHasCachedCredentialsFalseWhenMissing() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokAuthProbeTests-\(UUID().uuidString).json")
        XCTAssertFalse(GrokAuthProbe.hasCachedCredentials(at: url))
    }
}
