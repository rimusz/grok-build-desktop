import XCTest
import SwiftUI
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

    func testUpdatesBannerCopyAndAccessibility() {
        XCTAssertEqual(UpdatesBannerCopy.title, "Updates Available")
        XCTAssertEqual(UpdatesBannerCopy.dismissHelp, "Dismiss until next launch")
        XCTAssertEqual(
            UpdatesBannerCopy.subtitle(appVersion: "0.3.1", cliVersion: nil),
            "GrokBuild 0.3.1 is ready to download and install."
        )
        XCTAssertEqual(
            UpdatesBannerCopy.subtitle(appVersion: nil, cliVersion: "1.0.6"),
            "grok CLI 1.0.6 is ready to update."
        )
        XCTAssertEqual(
            UpdatesBannerCopy.subtitle(appVersion: "0.3.1", cliVersion: "1.0.6"),
            "GrokBuild 0.3.1 and grok CLI 1.0.6 have updates ready."
        )
        XCTAssertEqual(
            UpdatesBannerCopy.subtitle(appVersion: nil, cliVersion: nil),
            "Review available updates."
        )
        XCTAssertEqual(
            UpdatesBannerCopy.accessibilityLabel(appVersion: "0.3.1", cliVersion: nil),
            "Updates Available. GrokBuild 0.3.1 is ready to download and install."
        )
        XCTAssertEqual(
            UpdatesBannerCopy.accessibilityLabel(appVersion: nil, cliVersion: "1.0.6"),
            "Updates Available. grok CLI 1.0.6 is ready to update."
        )
        XCTAssertEqual(
            UpdatesBannerCopy.accessibilityLabel(appVersion: "0.3.1", cliVersion: "1.0.6"),
            "Updates Available. GrokBuild 0.3.1 and grok CLI 1.0.6 have updates ready."
        )
        XCTAssertEqual(
            UpdatesBannerCopy.accessibilityLabel(appVersion: nil, cliVersion: nil),
            "Updates Available. Review available updates."
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

    func testHelpMenuTopicsAndAgentConcepts() {
        XCTAssertEqual(
            HelpTopic.allCases.map(\.title),
            [
                "GrokBuild Help",
                "Getting Started",
                "Settings Guide",
                "Models",
                "Agents, Roles & Subagents",
                "Sessions",
                "Browser & Computer Use",
            ]
        )
        XCTAssertEqual(HelpMenuCopy.help, "GrokBuild Help")
        XCTAssertEqual(HelpMenuCopy.settingsGuide, "Settings Guide")
        XCTAssertEqual(HelpMenuCopy.models, "Models")
        XCTAssertEqual(HelpMenuCopy.sessions, "Sessions")
        XCTAssertEqual(HelpMenuCopy.browserAndComputerUse, "Browser & Computer Use")
        XCTAssertTrue(HelpMenuCopy.agentDefinition.contains("saved GrokBuild identity"))
        XCTAssertTrue(HelpMenuCopy.sessionRoleDefinition.contains("entire current session"))
        XCTAssertTrue(HelpMenuCopy.subagentDefinition.contains("child worker"))
        XCTAssertTrue(HelpMenuCopy.modelsSharedConfig.contains("~/.grok/config.toml"))
        XCTAssertTrue(HelpMenuCopy.modelsSharedConfig.contains("/model"))
        XCTAssertTrue(HelpMenuCopy.modelsFetchBeforeAdd.contains("dummy key"))
        XCTAssertTrue(HelpMenuCopy.modelsFetchBeforeAdd.contains("host.docker.internal"))
        XCTAssertTrue(HelpMenuCopy.sessionsDashboardDefinition.contains("live named sessions"))
        XCTAssertTrue(HelpMenuCopy.sessionsHistoryDefinition.contains("archived grok sessions"))
        XCTAssertTrue(HelpMenuCopy.browserEnableDefinition.contains("apply immediately"))
    }
}
