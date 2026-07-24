import XCTest
@testable import GrokBuild

final class BackgroundTaskTests: XCTestCase {
    func testBackgroundToolParsingDetectsScheduler() {
        let update: [String: Any] = [
            "_meta": ["x.ai/tool": ["name": "scheduler_list"]],
            "rawOutput": ["type": "SchedulerList", "tasks": []]
        ]
        XCTAssertEqual(BackgroundToolParsing.backgroundToolName(inUpdate: update), "scheduler_list")
    }

    func testBackgroundToolParsingDetectsBackgroundTerminal() {
        let update: [String: Any] = [
            "_meta": ["x.ai/tool": ["name": "run_terminal_command"]],
            "rawInput": ["command": "sleep 60", "background": true]
        ]
        XCTAssertEqual(BackgroundToolParsing.backgroundToolName(inUpdate: update), "run_terminal_command")
        XCTAssertEqual(
            BackgroundToolParsing.activityKind(for: "run_terminal_command", input: update["rawInput"] as! [String: Any]),
            .backgroundCommand
        )
    }

    func testBackgroundToolParsingIgnoresForegroundTerminal() {
        let input: [String: Any] = ["command": "ls", "background": false]
        XCTAssertNil(BackgroundToolParsing.activityKind(for: "run_terminal_command", input: input))
    }

    func testBackgroundTaskTrackerAccumulatesSubagent() {
        var tracker = BackgroundTaskTracker()
        let callID = "call-1"
        tracker.apply(update: [
            "toolCallId": callID,
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["name": "reviewer", "prompt": "Review the diff"]
        ])
        tracker.apply(update: [
            "toolCallId": callID,
            "rawOutput": ["id": "sub-1", "status": "running"]
        ])
        XCTAssertEqual(tracker.activities.count, 1)
        XCTAssertEqual(tracker.activities.first?.kind, .subagent)
        XCTAssertEqual(tracker.activities.first?.title, "reviewer")
    }

    func testBackgroundTaskTrackerSyncsScheduledTasks() {
        var tracker = BackgroundTaskTracker()
        tracker.apply(update: [
            "rawOutput": [
                "type": "SchedulerList",
                "tasks": [[
                    "id": "t1",
                    "prompt": "ping",
                    "intervalHuman": "5m",
                    "recurring": true
                ]]
            ]
        ])
        XCTAssertEqual(tracker.activities.count, 1)
        XCTAssertEqual(tracker.activities.first?.kind, .scheduled)
        XCTAssertEqual(tracker.activities.first?.scheduledTask?.prompt, "ping")
    }
}
