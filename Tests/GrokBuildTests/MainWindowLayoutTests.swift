import XCTest
@testable import GrokBuild

final class MainWindowLayoutTests: XCTestCase {
    func testMinimumFitsSidebarPlusComposerAndStatusPills() {
        // Sidebar (~260) + composer/status chrome (~840) → 1100×720.
        XCTAssertGreaterThanOrEqual(MainWindowLayout.minimumSize.width, 1000)
        XCTAssertEqual(MainWindowLayout.minimumSize.width, 1100)
        XCTAssertEqual(MainWindowLayout.minimumSize.height, 720)
    }

    func testDefaultIsAtLeastMinimum() {
        XCTAssertGreaterThanOrEqual(MainWindowLayout.defaultSize.width, MainWindowLayout.minimumSize.width)
        XCTAssertGreaterThanOrEqual(MainWindowLayout.defaultSize.height, MainWindowLayout.minimumSize.height)
        XCTAssertEqual(MainWindowLayout.defaultSize.width, 1200)
        XCTAssertEqual(MainWindowLayout.defaultSize.height, 800)
    }

    func testComposerUsesFullChatColumnWidth() {
        XCTAssertEqual(MainWindowLayout.composerMaxWidth, .infinity)
    }
}
