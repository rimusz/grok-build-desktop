import XCTest
@testable import GrokBuild

final class CompatConfigTests: XCTestCase {
    func testCompatConfigRewriteAddsSection() {
        let rewritten = CompatConfigStore.rewrite("", flavor: .cursor, enabled: true)
        XCTAssertTrue(rewritten.contains("[compat.cursor]"))
        XCTAssertTrue(rewritten.contains("enabled = true"))
    }

    func testCompatConfigRewriteUpdatesExisting() {
        let original = """
        [compat.claude]
        enabled = false
        """
        let rewritten = CompatConfigStore.rewrite(original, flavor: .claude, enabled: true)
        XCTAssertEqual(CompatConfigStore.isEnabled(.claude, contents: rewritten), true)
    }
}
