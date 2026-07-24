import XCTest
@testable import GrokBuild

final class WorkflowRunTests: XCTestCase {

    // MARK: - Detection

    func testDetectsWorkflowToolByMetaName() {
        let update: [String: Any] = [
            "sessionUpdate": "tool_call",
            "toolCallId": "call-1",
            "title": "workflow",
            "_meta": ["x.ai/tool": ["name": "workflow", "namespace": "grok_build"]]
        ]
        XCTAssertEqual(WorkflowToolParsing.workflowName(inUpdate: update), "workflow")
    }

    func testDetectsWorkflowToolByPrefixedMetaName() {
        let update: [String: Any] = [
            "sessionUpdate": "tool_call",
            "toolCallId": "call-1",
            "_meta": ["x.ai/tool": ["name": "workflow_list"]]
        ]
        XCTAssertEqual(WorkflowToolParsing.workflowName(inUpdate: update), "workflow_list")
    }

    func testDetectsWorkflowToolByRawOutputType() {
        let update: [String: Any] = [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-1",
            "status": "completed",
            "rawOutput": ["type": "WorkflowList", "runs": []]
        ]
        XCTAssertEqual(WorkflowToolParsing.workflowName(inUpdate: update), "WorkflowList")
    }

    func testIgnoresNonWorkflowTool() {
        let update: [String: Any] = [
            "sessionUpdate": "tool_call",
            "toolCallId": "call-9",
            "_meta": ["x.ai/tool": ["name": "read_file"]]
        ]
        XCTAssertNil(WorkflowToolParsing.workflowName(inUpdate: update))
    }

    func testWorkflowSessionUpdateKeys() {
        XCTAssertTrue(WorkflowToolParsing.isWorkflowSessionUpdate("workflow_updated"))
        XCTAssertTrue(WorkflowToolParsing.isWorkflowSessionUpdate("WorkflowUpdated"))
        XCTAssertTrue(WorkflowToolParsing.isWorkflowSessionUpdate("goal_updated"))
        XCTAssertTrue(WorkflowToolParsing.isWorkflowSessionUpdate("goalupdated"))
        XCTAssertFalse(WorkflowToolParsing.isWorkflowSessionUpdate("tool_call"))
    }

    // MARK: - List replace

    func testWorkflowListReplacesRuns() {
        var tracker = WorkflowRunTracker()
        tracker.apply(update: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-list",
            "status": "completed",
            "rawOutput": [
                "type": "WorkflowList",
                "runs": [
                    [
                        "handle": "deep-research-2",
                        "workflowName": "Deep Research",
                        "phase": "research",
                        "status": "running",
                        "progress": "Gathering sources",
                        "agentBudgetSpent": 3,
                        "agentBudgetTotal": 10
                    ]
                ]
            ]
        ])

        XCTAssertEqual(tracker.runs.count, 1)
        let run = try? XCTUnwrap(tracker.runs.first)
        XCTAssertEqual(run?.id, "deep-research-2")
        XCTAssertEqual(run?.name, "Deep Research")
        XCTAssertEqual(run?.phase, "research")
        XCTAssertEqual(run?.status, "running")
        XCTAssertEqual(run?.progress, "Gathering sources")
        XCTAssertEqual(run?.agentBudgetSpent, 3)
        XCTAssertEqual(run?.agentBudgetTotal, 10)
    }

    func testWorkflowListFallsBackToWorkflowsKey() {
        var tracker = WorkflowRunTracker()
        tracker.apply(update: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-list",
            "status": "completed",
            "rawOutput": [
                "type": "workflow_list",
                "workflows": [["handle": "alpha", "status": "running"]]
            ]
        ])
        XCTAssertEqual(tracker.runs.map(\.id), ["alpha"])
    }

    // MARK: - Create / upsert

    func testWorkflowCreateMergesInputAndOutput() {
        var tracker = WorkflowRunTracker()
        tracker.apply(update: [
            "sessionUpdate": "tool_call",
            "toolCallId": "call-create",
            "rawInput": ["name": "deep-research", "query": "swift concurrency"],
            "_meta": ["x.ai/tool": ["name": "workflow_create"]]
        ])
        tracker.apply(update: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-create",
            "status": "completed",
            "rawOutput": [
                "type": "WorkflowCreate",
                "handle": "deep-research-2",
                "workflowName": "Deep Research",
                "status": "running",
                "progress": "Starting"
            ]
        ])

        XCTAssertEqual(tracker.runs.count, 1)
        XCTAssertEqual(tracker.runs.first?.id, "deep-research-2")
        XCTAssertEqual(tracker.runs.first?.name, "Deep Research")
        XCTAssertEqual(tracker.runs.first?.status, "running")
    }

    // MARK: - Pause / stop

    func testWorkflowPauseUpdatesStatus() {
        var tracker = WorkflowRunTracker()
        tracker.apply(update: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-list",
            "status": "completed",
            "rawOutput": [
                "type": "WorkflowList",
                "runs": [["handle": "deep-research-2", "status": "running"]]
            ]
        ])
        tracker.apply(update: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-pause",
            "status": "completed",
            "rawOutput": ["type": "WorkflowPause", "handle": "deep-research-2"]
        ])
        XCTAssertEqual(tracker.runs.first?.status, "paused")
    }

    func testWorkflowStopUpdatesStatus() {
        var tracker = WorkflowRunTracker()
        tracker.apply(update: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-list",
            "status": "completed",
            "rawOutput": [
                "type": "WorkflowList",
                "runs": [["handle": "deep-research-2", "status": "running"]]
            ]
        ])
        tracker.apply(update: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-stop",
            "status": "completed",
            "rawOutput": ["type": "WorkflowStop", "handle": "deep-research-2"]
        ])
        XCTAssertEqual(tracker.runs.first?.status, "stopped")
    }

    // MARK: - Session updates

    func testWorkflowUpdatedSessionUpdateUpsertsRun() {
        var tracker = WorkflowRunTracker()
        tracker.apply(update: [
            "sessionUpdate": "workflow_updated",
            "handle": "deep-research-2",
            "workflowName": "Deep Research",
            "phase": "synthesis",
            "status": "running",
            "progress": "Writing report"
        ])
        XCTAssertEqual(tracker.runs.count, 1)
        XCTAssertEqual(tracker.runs.first?.phase, "synthesis")
        XCTAssertEqual(tracker.runs.first?.progress, "Writing report")
    }

    func testGoalUpdatedSessionUpdateUpsertsRun() {
        var tracker = WorkflowRunTracker()
        tracker.apply(update: [
            "sessionUpdate": "goal_updated",
            "run": [
                "handle": "deep-research-2",
                "status": "paused",
                "progress": "Waiting on user"
            ]
        ])
        XCTAssertEqual(tracker.runs.first?.status, "paused")
    }

    func testTrackerResetClearsRuns() {
        var tracker = WorkflowRunTracker()
        tracker.apply(update: [
            "sessionUpdate": "workflow_updated",
            "handle": "deep-research-2",
            "status": "running"
        ])
        tracker.reset()
        XCTAssertTrue(tracker.runs.isEmpty)
    }

    // MARK: - SavedWorkflowStore

    func testSavedWorkflowParseMeta() {
        let contents = """
        // meta
        name: "Deep Research"
        description = "Runs multi-step research"
        """
        let meta = SavedWorkflowStore.parseMeta(from: contents)
        XCTAssertEqual(meta.name, "Deep Research")
        XCTAssertEqual(meta.description, "Runs multi-step research")
    }

    // MARK: - WorkflowsConfigStore

    func testWorkflowsConfigRewriteAddsSectionWhenMissing() {
        let rewritten = WorkflowsConfigStore.rewrite("", enabled: false)
        XCTAssertTrue(rewritten.contains("[workflows]"))
        XCTAssertTrue(rewritten.contains("enabled = false"))
        XCTAssertEqual(WorkflowsConfigStore.isEnabled(contents: rewritten), false)
    }

    func testWorkflowsConfigRewriteUpdatesEnabledPreservingOtherSections() {
        let original = """
        [models]
        default = "grok"

        [workflows]
        enabled = true
        max_parallel = 2

        [browser]
        enabled = false
        """
        let rewritten = WorkflowsConfigStore.rewrite(original, enabled: false)
        XCTAssertTrue(rewritten.contains("[models]"))
        XCTAssertTrue(rewritten.contains("default = \"grok\""))
        XCTAssertTrue(rewritten.contains("max_parallel = 2"))
        XCTAssertTrue(rewritten.contains("[browser]"))
        XCTAssertTrue(rewritten.contains("enabled = false"))
        XCTAssertFalse(rewritten.contains("enabled = true"))
        XCTAssertEqual(WorkflowsConfigStore.isEnabled(contents: rewritten), false)
    }

    func testWorkflowsConfigDefaultsToEnabledWhenMissing() {
        XCTAssertTrue(WorkflowsConfigStore.isEnabled(contents: "[models]\ndefault = \"grok\"\n"))
    }
}
