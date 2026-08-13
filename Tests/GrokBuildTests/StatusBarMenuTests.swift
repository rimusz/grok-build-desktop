import XCTest
@testable import GrokBuild

final class StatusBarMenuTests: XCTestCase {
    func testGrokStatusMapsReadyBusyErrorStarting() {
        XCTAssertEqual(GrokStatus(rawStatus: "ready"), .ready)
        XCTAssertEqual(GrokStatus(rawStatus: "busy"), .busy)
        XCTAssertEqual(GrokStatus(rawStatus: "error"), .error)
        XCTAssertEqual(GrokStatus(rawStatus: "starting"), .starting)
    }

    func testGrokStatusUnknownMapsToIdle() {
        XCTAssertEqual(GrokStatus(rawStatus: "unknown"), .idle)
        XCTAssertEqual(GrokStatus(rawStatus: ""), .idle)
    }

    func testGrokProcessStateStatusStringMapping() {
        XCTAssertEqual(GrokProcessState.statusString(for: .idle), "idle")
        XCTAssertEqual(GrokProcessState.statusString(for: .starting), "idle")
        XCTAssertEqual(GrokProcessState.statusString(for: .ready), "ready")
        XCTAssertEqual(GrokProcessState.statusString(for: .busy), "busy")
        XCTAssertEqual(GrokProcessState.statusString(for: .failed("boom")), "error")
    }

    func testGrokStatusAccessibilityLabels() {
        XCTAssertEqual(GrokStatus.idle.accessibilityLabel, "Idle")
        XCTAssertEqual(GrokStatus.ready.accessibilityLabel, "Ready")
        XCTAssertEqual(GrokStatus.busy.accessibilityLabel, "Working")
        XCTAssertEqual(GrokStatus.error.accessibilityLabel, "Error")
        XCTAssertEqual(GrokStatus.starting.accessibilityLabel, "Starting")
    }

    func testAuthMenuTitleWhenSignedIn() {
        XCTAssertEqual(
            StatusBarMenuCopy.menuTitle(authenticated: true),
            "Signed in to grok CLI"
        )
    }

    func testAuthMenuTitleWhenSignedOut() {
        XCTAssertEqual(
            StatusBarMenuCopy.menuTitle(authenticated: false),
            "Sign in required — run grok login"
        )
    }

    func testUpdateMenuTitleWhenNoUpdate() {
        XCTAssertEqual(
            StatusBarMenuCopy.updateMenuTitle(hasActionableUpdate: false),
            "Check for Updates…"
        )
    }

    func testUpdateMenuTitleWhenUpdateAvailable() {
        XCTAssertEqual(
            StatusBarMenuCopy.updateMenuTitle(hasActionableUpdate: true),
            "Upgrade Available…"
        )
    }

    func testSessionsHistoryCopyIsDistinctFromDashboard() {
        XCTAssertEqual(SessionsHistoryCopy.windowTitle, "Sessions History")
        XCTAssertEqual(SessionsHistoryCopy.menuItem, "Sessions History…")
        XCTAssertEqual(SessionsHistoryCopy.searchPlaceholder, "Search session history")
        XCTAssertEqual(SessionsHistoryCopy.toolbarHelp, "Sessions History")
        XCTAssertEqual(SessionsHistoryCopy.emptyTitle, "No session history")
        XCTAssertEqual(SessionsHistoryCopy.sidebarOverflowSuffix, "more in Sessions History…")
        XCTAssertFalse(SessionsHistoryCopy.windowTitle.localizedCaseInsensitiveContains("dashboard"))
    }

    func testSessionsDashboardCopyAndToolbarOrder() {
        XCTAssertEqual(SessionsDashboardCopy.windowTitle, "Sessions Dashboard")
        XCTAssertEqual(SessionsDashboardCopy.toolbarHelp, "Sessions Dashboard")
        XCTAssertEqual(
            SessionsDashboardCopy.toolbarHelpDetail,
            "Sessions Dashboard — roster, review, automations"
        )
        XCTAssertEqual(
            [SessionsDashboardCopy.toolbarHelp, SessionsHistoryCopy.toolbarHelp],
            ["Sessions Dashboard", "Sessions History"]
        )
    }
}
