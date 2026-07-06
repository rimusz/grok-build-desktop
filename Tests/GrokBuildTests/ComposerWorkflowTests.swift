import XCTest
@testable import GrokBuild

final class ComposerWorkflowTests: XCTestCase {
    func testWorkflowSlashCommandsFilterPreservesCuratedOrder() {
        let available = [
            SlashCommand(name: "review", description: "Review"),
            SlashCommand(name: "design", description: "Design"),
            SlashCommand(name: "compact", description: "Compact"),
            SlashCommand(name: "implement", description: "Implement"),
            SlashCommand(name: "goal", description: "Goal"),
        ]

        let filtered = WorkflowSlashCommands.filter(available)
        XCTAssertEqual(filtered.map(\.name), ["design", "implement", "review"])
    }

    func testWorkflowSlashCommandsOmitsUnavailableNames() {
        let available = [
            SlashCommand(name: "design", description: "Design"),
            SlashCommand(name: "compact", description: "Compact"),
        ]

        let filtered = WorkflowSlashCommands.filter(available)
        XCTAssertEqual(filtered.map(\.name), ["design"])
    }

    func testWorkflowSlashCommandsReturnsEmptyWhenNoneMatch() {
        let available = [SlashCommand(name: "compact", description: "Compact")]
        XCTAssertTrue(WorkflowSlashCommands.filter(available).isEmpty)
    }

    func testGoalCommandParseSetObjective() {
        XCTAssertEqual(GoalCommand.parse(from: "/goal ship v1"), .set(objective: "ship v1"))
        XCTAssertEqual(GoalCommand.parse(from: "  /goal  fix tests  "), .set(objective: "fix tests"))
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
        XCTAssertEqual(GoalCommand.set(objective: "ship").sendText, "/goal ship")
        XCTAssertEqual(GoalCommand.pause.sendText, "/goal pause")
    }

    func testSessionGoalStateMutation() {
        var state: SessionGoalState?

        SessionGoalStateMutation.apply(.set(objective: "ship v1"), to: &state)
        XCTAssertEqual(state, SessionGoalState(objective: "ship v1", isPaused: false))

        SessionGoalStateMutation.apply(.pause, to: &state)
        XCTAssertEqual(state?.isPaused, true)

        SessionGoalStateMutation.apply(.resume, to: &state)
        XCTAssertEqual(state?.isPaused, false)

        SessionGoalStateMutation.apply(.clear, to: &state)
        XCTAssertNil(state)
    }
}
