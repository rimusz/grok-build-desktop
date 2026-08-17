import XCTest
@testable import GrokBuild

final class SettingsTabTests: XCTestCase {
    func testAllTabsHaveUniqueNonEmptyTitles() {
        let titles = SettingsTab.allCases.map(\.title)
        XCTAssertEqual(titles.count, Set(titles).count)
        for title in titles {
            XCTAssertFalse(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(title.contains("…"))
            XCTAssertFalse(title.hasSuffix("..."))
        }
    }

    func testTabOrderMatchesSettingsSurface() {
        XCTAssertEqual(
            SettingsTab.allCases.map(\.title),
            [
                "Agents",
                "Models",
                "Permissions",
                "Memory",
                "Workflows",
                "Browser",
                "Computer Use",
                "MCP Servers",
                "Skills",
                "Plugins",
                "Marketplace",
                "Compatibility",
                "Hooks",
                "App",
            ]
        )
    }

    func testAllTabsHaveSystemImages() {
        for tab in SettingsTab.allCases {
            XCTAssertFalse(tab.systemImage.isEmpty, "\(tab) missing systemImage")
        }
    }

    func testKeepAliveMountsSelectedAndPreviouslyVisitedTabsOnly() {
        var loaded: Set<SettingsTab> = []
        XCTAssertTrue(SettingsTabKeepAlive.shouldMount(.agents, selected: .agents, loaded: loaded))
        XCTAssertFalse(SettingsTabKeepAlive.shouldMount(.browser, selected: .agents, loaded: loaded))

        SettingsTabKeepAlive.recordVisit(.agents, loaded: &loaded)
        SettingsTabKeepAlive.recordVisit(.browser, loaded: &loaded)

        XCTAssertEqual(loaded, [.agents, .browser])
        XCTAssertTrue(SettingsTabKeepAlive.shouldMount(.agents, selected: .models, loaded: loaded))
        XCTAssertTrue(SettingsTabKeepAlive.shouldMount(.browser, selected: .models, loaded: loaded))
        XCTAssertTrue(SettingsTabKeepAlive.shouldMount(.models, selected: .models, loaded: loaded))
        XCTAssertFalse(SettingsTabKeepAlive.shouldMount(.hooks, selected: .models, loaded: loaded))
    }

    func testSameWorkspaceDoesNotLeaveSettings() {
        let project = UUID()
        XCTAssertFalse(
            SettingsPaneNavigation.shouldLeaveSettings(
                incomingWorkspaceID: project,
                activeWorkspaceID: project
            )
        )
    }

    func testDifferentWorkspaceLeavesSettings() {
        XCTAssertTrue(
            SettingsPaneNavigation.shouldLeaveSettings(
                incomingWorkspaceID: UUID(),
                activeWorkspaceID: UUID()
            )
        )
    }

    func testNilIncomingWorkspaceKeepsSettings() {
        XCTAssertFalse(
            SettingsPaneNavigation.shouldLeaveSettings(
                incomingWorkspaceID: nil,
                activeWorkspaceID: UUID()
            )
        )
    }

    func testSelectingProjectFromEmptySessionLeavesSettings() {
        XCTAssertTrue(
            SettingsPaneNavigation.shouldLeaveSettings(
                incomingWorkspaceID: UUID(),
                activeWorkspaceID: nil
            )
        )
    }

    func testOpeningSettingsDismissesSessionSheets() {
        var showSessions = true
        var showDashboard = true
        let tab = SettingsPaneNavigation.openSettings(
            tab: .models,
            showSessions: &showSessions,
            showSessionDashboard: &showDashboard
        )
        XCTAssertEqual(tab, .models)
        XCTAssertFalse(showSessions)
        XCTAssertFalse(showDashboard)
    }
}
