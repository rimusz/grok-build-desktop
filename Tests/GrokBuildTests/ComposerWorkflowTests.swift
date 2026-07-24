import XCTest
@testable import GrokBuild

final class ComposerWorkflowTests: XCTestCase {
    func testSkillSlashCommandsFilterPreservesCuratedOrder() {
        let available = [
            SlashCommand(name: "review", description: "Review"),
            SlashCommand(name: "design", description: "Design"),
            SlashCommand(name: "compact", description: "Compact"),
            SlashCommand(name: "implement", description: "Implement"),
            SlashCommand(name: "goal", description: "Goal"),
        ]

        let filtered = SkillSlashCommands.filter(available)
        XCTAssertEqual(filtered.map(\.name), ["design", "implement", "review"])
    }

    func testSkillSlashCommandsOmitsUnavailableNames() {
        let available = [
            SlashCommand(name: "design", description: "Design"),
            SlashCommand(name: "compact", description: "Compact"),
        ]

        let filtered = SkillSlashCommands.filter(available)
        XCTAssertEqual(filtered.map(\.name), ["design"])
    }

    func testSkillSlashCommandsIgnoresDuplicateAdvertisedNames() {
        let available = [
            SlashCommand(name: "design", description: "Design"),
            SlashCommand(name: "design", description: "Duplicate design"),
            SlashCommand(name: "review", description: "Review")
        ]

        let filtered = SkillSlashCommands.filter(available)
        XCTAssertEqual(filtered.map(\.name), ["design", "review"])
        XCTAssertEqual(filtered.first?.description, "Design")
    }

    func testSkillSlashCommandsReturnsEmptyWhenNoneMatch() {
        let available = [SlashCommand(name: "compact", description: "Compact")]
        XCTAssertTrue(SkillSlashCommands.filter(available).isEmpty)
    }

    func testResearchSlashCommandsFilterPreservesCuratedOrder() {
        let available = [
            SlashCommand(name: "create-workflow", description: "Create workflow"),
            SlashCommand(name: "deep-research", description: "Deep research"),
            SlashCommand(name: "compact", description: "Compact"),
        ]

        let filtered = ResearchSlashCommands.filter(available)
        XCTAssertEqual(filtered.map(\.name), ["deep-research", "create-workflow"])
    }

    func testResearchSlashCommandsOmitsUnavailableNames() {
        let available = [SlashCommand(name: "deep-research", description: "Deep research")]
        XCTAssertEqual(ResearchSlashCommands.filter(available).map(\.name), ["deep-research"])
    }

    func testGoalCommandParseSetObjective() {
        XCTAssertEqual(GoalCommand.parse(from: "/goal ship v1"), .set(objective: "ship v1", budget: nil))
        XCTAssertEqual(GoalCommand.parse(from: "  /goal  fix tests  "), .set(objective: "fix tests", budget: nil))
        XCTAssertEqual(GoalCommand.parse(from: "/goal ship v1 --budget 42"), .set(objective: "ship v1", budget: 42))
    }

    func testGoalCommandParseSubcommands() {
        XCTAssertEqual(GoalCommand.parse(from: "/goal status"), .status)
        XCTAssertEqual(GoalCommand.parse(from: "/goal pause"), .pause)
        XCTAssertEqual(GoalCommand.parse(from: "/goal resume"), .resume)
        XCTAssertEqual(GoalCommand.parse(from: "/goal clear"), .clear)
        XCTAssertEqual(GoalCommand.parse(from: "/goal STATUS"), .status)
    }

    func testGoalCommandParseRejectsBareGoal() {
        XCTAssertNil(GoalCommand.parse(from: "/goal"))
        XCTAssertNil(GoalCommand.parse(from: "/goals status"))
        XCTAssertNil(GoalCommand.parse(from: "not a goal"))
    }

    func testGoalCommandSendText() {
        XCTAssertEqual(GoalCommand.set(objective: "ship", budget: nil).sendText, "/goal ship")
        XCTAssertEqual(GoalCommand.set(objective: "ship", budget: 10).sendText, "/goal ship --budget 10")
        XCTAssertEqual(GoalCommand.pause.sendText, "/goal pause")
    }

    func testImagineSlashCommandsFilter() {
        let available = [
            SlashCommand(name: "imagine-video", description: "Video"),
            SlashCommand(name: "imagine", description: "Image"),
            SlashCommand(name: "compact", description: "Compact"),
        ]
        XCTAssertEqual(ImagineSlashCommands.filter(available).map(\.name), ["imagine", "imagine-video"])
    }

    func testShareURLParser() {
        XCTAssertEqual(
            ShareURLParser.firstURL(in: "Share link: https://grok.com/share/abc-123 done"),
            "https://grok.com/share/abc-123"
        )
        XCTAssertNil(ShareURLParser.firstURL(in: "no link here"))
    }

    func testSessionGoalStateMutation() {
        var state: SessionGoalState?

        SessionGoalStateMutation.apply(.set(objective: "ship v1", budget: 5), to: &state)
        XCTAssertEqual(state, SessionGoalState(objective: "ship v1", budget: 5, isPaused: false))

        SessionGoalStateMutation.apply(.pause, to: &state)
        XCTAssertEqual(state?.isPaused, true)

        SessionGoalStateMutation.apply(.resume, to: &state)
        XCTAssertEqual(state?.isPaused, false)

        SessionGoalStateMutation.apply(.clear, to: &state)
        XCTAssertNil(state)
    }
}
