import XCTest
@testable import GrokBuild

/// Unit tests for the scheduled-tasks mirror. Payload shapes mirror the real ACP `session/update`
/// tool-call events grok emits for `scheduler_create` / `scheduler_list` / `scheduler_delete`
/// (captured live from `grok agent stdio` 0.2.93).
final class ScheduledTaskTests: XCTestCase {

    // MARK: - Detection

    func testDetectsSchedulerToolByMetaName() {
        let update: [String: Any] = [
            "sessionUpdate": "tool_call",
            "toolCallId": "call-1",
            "title": "scheduler_create",
            "rawInput": ["interval": "60s", "prompt": "say hi", "recurring": true],
            "_meta": ["x.ai/tool": ["name": "scheduler_create", "namespace": "grok_build"]]
        ]
        XCTAssertEqual(SchedulerToolParsing.schedulerName(inUpdate: update), "scheduler_create")
    }

    func testDetectsSchedulerToolByRawOutputType() {
        // Real grok completion events carry NO _meta and use CamelCase type.
        let update: [String: Any] = [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-1",
            "status": "completed",
            "rawOutput": ["type": "SchedulerList", "tasks": []]
        ]
        XCTAssertEqual(SchedulerToolParsing.schedulerName(inUpdate: update), "SchedulerList")
    }

    func testIgnoresNonSchedulerTool() {
        let update: [String: Any] = [
            "sessionUpdate": "tool_call",
            "toolCallId": "call-9",
            "title": "read_file",
            "_meta": ["x.ai/tool": ["name": "read_file"]]
        ]
        XCTAssertNil(SchedulerToolParsing.schedulerName(inUpdate: update))
    }

    // MARK: - scheduler_list is authoritative

    func testSchedulerListReplacesTasks() {
        var tracker = ScheduledTaskTracker()
        let listUpdate: [String: Any] = [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-list",
            "status": "completed",
            "rawOutput": [
                "type": "SchedulerList",
                "tasks": [
                    [
                        "id": "019f46ef23da",
                        "prompt": "say the current time",
                        "intervalHuman": "every 1 minute",
                        "nextFireAt": "2026-07-09T12:52:45.242123+00:00",
                        "recurring": true
                    ]
                ]
            ]
        ]
        tracker.apply(update: listUpdate)

        XCTAssertEqual(tracker.tasks.count, 1)
        let task = try? XCTUnwrap(tracker.tasks.first)
        XCTAssertEqual(task?.id, "019f46ef23da")
        XCTAssertEqual(task?.prompt, "say the current time")
        XCTAssertEqual(task?.intervalHuman, "every 1 minute")
        XCTAssertEqual(task?.recurring, true)
        XCTAssertNotNil(task?.nextFireAt)
    }

    // MARK: - create correlates rawInput (prompt) with rawOutput (id)

    func testSchedulerCreateMergesPromptFromInitiatingToolCall() {
        var tracker = ScheduledTaskTracker()
        // tool_call carries interval/prompt in rawInput
        tracker.apply(update: [
            "sessionUpdate": "tool_call",
            "toolCallId": "call-c1",
            "title": "scheduler_create",
            "rawInput": ["interval": "60s", "prompt": "say the current time", "recurring": true],
            "_meta": ["x.ai/tool": ["name": "scheduler_create"]]
        ])
        // completion carries id + humanSchedule in rawOutput (no prompt)
        tracker.apply(update: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-c1",
            "status": "completed",
            "rawOutput": ["type": "SchedulerCreate", "id": "019f46ef23da", "humanSchedule": "every 1 minute", "recurring": true]
        ])

        XCTAssertEqual(tracker.tasks.count, 1)
        XCTAssertEqual(tracker.tasks.first?.id, "019f46ef23da")
        XCTAssertEqual(tracker.tasks.first?.prompt, "say the current time")
        XCTAssertEqual(tracker.tasks.first?.intervalHuman, "every 1 minute")
    }

    // MARK: - delete removes

    func testSchedulerDeleteRemovesTask() {
        var tracker = ScheduledTaskTracker()
        tracker.apply(update: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-list",
            "status": "completed",
            "rawOutput": ["type": "SchedulerList", "tasks": [["id": "abc", "prompt": "p", "recurring": false]]]
        ])
        XCTAssertEqual(tracker.tasks.count, 1)

        tracker.apply(update: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-del",
            "status": "completed",
            "rawOutput": ["type": "SchedulerDelete", "id": "abc"]
        ])
        XCTAssertTrue(tracker.tasks.isEmpty)
    }

    func testSchedulerDeleteUsesInitiatingInputWhenOutputLacksId() {
        var tracker = ScheduledTaskTracker()
        tracker.apply(update: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-list",
            "status": "completed",
            "rawOutput": ["type": "SchedulerList", "tasks": [["id": "abc", "prompt": "p", "recurring": false]]]
        ])
        // delete tool_call carries id in rawInput; completion output omits it
        tracker.apply(update: [
            "sessionUpdate": "tool_call",
            "toolCallId": "call-del",
            "rawInput": ["id": "abc"],
            "_meta": ["x.ai/tool": ["name": "scheduler_delete"]]
        ])
        tracker.apply(update: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-del",
            "status": "completed",
            "rawOutput": ["type": "SchedulerDelete", "ok": true]
        ])
        XCTAssertTrue(tracker.tasks.isEmpty)
    }

    // MARK: - tolerant casing

    func testTaskParsingToleratesLowercaseKeys() {
        let task = SchedulerToolParsing.task(from: [
            "id": "z1",
            "prompt": "do thing",
            "intervalhuman": "every 5 minutes",
            "nextfireat": "2026-07-09T12:52:45+00:00",
            "recurring": true
        ])
        XCTAssertEqual(task?.id, "z1")
        XCTAssertEqual(task?.intervalHuman, "every 5 minutes")
        XCTAssertNotNil(task?.nextFireAt)
    }

    func testInitiatingToolCallAloneAddsNoTask() {
        var tracker = ScheduledTaskTracker()
        tracker.apply(update: [
            "sessionUpdate": "tool_call",
            "toolCallId": "call-c1",
            "rawInput": ["interval": "60s", "prompt": "hi", "recurring": true],
            "_meta": ["x.ai/tool": ["name": "scheduler_create"]]
        ])
        XCTAssertTrue(tracker.tasks.isEmpty, "No task until a completed rawOutput arrives")
    }

    // MARK: - Real captured wire shapes (grok agent stdio 0.2.93)

    /// Regression: the list-output completion event has CamelCase `type` and NO `_meta`, so
    /// detection must rely on a case-insensitive rawOutput.type prefix. (This exact shape was
    /// captured live and previously slipped through, leaving the panel empty.)
    func testRealCapturedCreateThenListSequence() {
        var tracker = ScheduledTaskTracker()
        let events: [[String: Any]] = [
            [
                "sessionUpdate": "tool_call",
                "toolCallId": "call-a-0",
                "title": "scheduler_create",
                "rawInput": ["interval": "60s", "prompt": "say hi", "recurring": true],
                "_meta": ["x.ai/tool": ["name": "scheduler_create", "namespace": "grok_build"]]
            ],
            [
                "sessionUpdate": "tool_call_update",
                "toolCallId": "call-a-0",
                "status": "completed",
                "rawOutput": ["type": "SchedulerCreate", "id": "019f4708d7b8", "humanSchedule": "every 1 minute", "recurring": true]
            ],
            [
                "sessionUpdate": "tool_call",
                "toolCallId": "call-b-1",
                "title": "scheduler_list",
                "rawInput": [:],
                "_meta": ["x.ai/tool": ["name": "scheduler_list", "namespace": "grok_build"]]
            ],
            [
                "sessionUpdate": "tool_call_update",
                "toolCallId": "call-b-1",
                "status": "completed",
                "rawOutput": [
                    "type": "SchedulerList",
                    "tasks": [
                        [
                            "id": "019f4708d7b8",
                            "prompt": "say hi",
                            "intervalHuman": "every 1 minute",
                            "nextFireAt": "2026-07-09T13:20:49.688877+00:00",
                            "createdAt": "2026-07-09T13:19:49.688877+00:00",
                            "recurring": true
                        ]
                    ]
                ]
            ]
        ]
        for event in events {
            if SchedulerToolParsing.schedulerName(inUpdate: event) != nil {
                tracker.apply(update: event)
            }
        }

        XCTAssertEqual(tracker.tasks.count, 1)
        XCTAssertEqual(tracker.tasks.first?.id, "019f4708d7b8")
        XCTAssertEqual(tracker.tasks.first?.prompt, "say hi")
        XCTAssertEqual(tracker.tasks.first?.intervalHuman, "every 1 minute")
        XCTAssertEqual(tracker.tasks.first?.recurring, true)
        XCTAssertNotNil(tracker.tasks.first?.nextFireAt)
    }
}
