import XCTest
@testable import GrokBuild

final class GrokActivitySummaryTests: XCTestCase {
    func testClassifyReadSkillVersusFile() {
        XCTAssertEqual(
            GrokActivitySummary.classify(title: "Read `/Users/me/.grok/skills/using-superpowers/SKILL.md`"),
            .readSkill
        )
        XCTAssertEqual(
            GrokActivitySummary.classify(title: "Read `/Users/me/project/README.md`"),
            .readFile
        )
        XCTAssertEqual(
            GrokActivitySummary.classify(title: "List `/Users/me/project`"),
            .listed
        )
        XCTAssertNil(GrokActivitySummary.classify(title: "Tool call"))
        XCTAssertEqual(GrokActivitySummary.classify(title: "Get"), .fetched)
        XCTAssertEqual(GrokActivitySummary.classify(title: "bash"), .ran)
        XCTAssertEqual(GrokActivitySummary.classify(title: "computer_list_apps"), .computerUse)
        XCTAssertEqual(GrokActivitySummary.classify(title: "computer list apps"), .computerUse)
        XCTAssertEqual(GrokActivitySummary.classify(title: "[subagent:general-purpose]"), .subagent)
        XCTAssertEqual(GrokActivitySummary.classify(title: "spawn.*bash"), .searched)
        XCTAssertEqual(GrokActivitySummary.classify(title: "\"name\":\"computer list apps\""), .searched)
        XCTAssertEqual(GrokActivitySummary.classify(title: "tool calls.*computer"), .searched)
        XCTAssertEqual(GrokActivitySummary.classify(title: "search"), .searched)
        XCTAssertEqual(GrokActivitySummary.classify(title: "Search files"), .searched)
    }

    func testSummarizeMatchesCLIVerbOrder() {
        let titles = [
            "Read `/tmp/skills/foo/SKILL.md`",
            "List `/tmp/project`",
            "Read `/tmp/project/docs/stack-map.md`",
            "Read `/tmp/project/README.md`"
        ]
        XCTAssertEqual(
            GrokActivitySummary.summarize(titles: titles),
            "Read 1 skill, Read 2 files, Listed 1 dir"
        )
        XCTAssertEqual(
            GrokActivitySummary.line(titles: titles, hookCount: 5),
            "Read 1 skill, Read 2 files, Listed 1 dir  [hooks: 5]"
        )
    }

    func testSummarizeMapsJunkTitlesToStableVerbs() {
        XCTAssertEqual(
            GrokActivitySummary.summarize(titles: [
                "Read `/tmp/a.swift`",
                "Read `/tmp/b.swift`",
                "Read `/tmp/c.swift`",
                "Read `/tmp/d.swift`",
                "bash",
                "buzz",
                "Listed `/tmp`",
                "Listed `/tmp/a`",
                "Listed `/tmp/b`",
                "\"name\":\"computer",
                "spawn.*bash"
            ]),
            "Read 4 files, Ran 1 command, buzz, Listed 3 dirs, Searched 2"
        )
        XCTAssertEqual(
            GrokActivitySummary.summarize(titles: [
                "Read `/tmp/one.swift`",
                "Listed `/tmp`",
                "computer_list_apps",
                "computer_list_apps",
                "\"name\":\"computer list apps\"",
                "tool calls.*computer"
            ]),
            "Read 1 file, Listed 1 dir, Computer Use ×2, Searched 2"
        )
        XCTAssertEqual(
            GrokActivitySummary.summarize(titles: ["Get"]),
            "Fetched 1"
        )
        XCTAssertEqual(
            GrokActivitySummary.summarize(titles: [
                "Read `/tmp/a.swift`",
                "Read `/tmp/b.swift`",
                "Read `/tmp/c.swift`",
                "Read `/tmp/d.swift`",
                "[subagent:general-purpose]"
            ]),
            "Read 4 files, subagent"
        )
    }

    func testRefreshSummaryRewritesPersistedJunkClauses() {
        XCTAssertEqual(
            GrokActivitySummary.refreshSummary(
                #"Read 4 files, bash, buzz, Listed 3 dirs, "name":"computer , spawn.*bash"#
            ),
            "Read 4 files, Ran 1 command, buzz, Listed 3 dirs, Searched 2"
        )
        XCTAssertEqual(
            GrokActivitySummary.refreshSummary(
                #"Read 1 file, Listed 1 dir, computer list apps ×2, "name":"computer list apps", tool calls.*computer"#
            ),
            "Read 1 file, Listed 1 dir, Computer Use ×2, Searched 2"
        )
        XCTAssertEqual(GrokActivitySummary.refreshSummary("Get"), "Fetched 1")
        XCTAssertEqual(
            GrokActivitySummary.refreshSummary("Read 4 files, [subagent:general-purpose]"),
            "Read 4 files, subagent"
        )
        XCTAssertEqual(
            GrokActivitySummary.refreshSummary("Read 1 skill, Read 2 files, Listed 1 dir"),
            "Read 1 skill, Read 2 files, Listed 1 dir"
        )
        XCTAssertEqual(
            GrokActivitySummary.refreshSummary("Read 1 skill, Read 5 files, Searched 4, Memory ×2, Listed 1 dir, subagent"),
            "Read 1 skill, Read 5 files, Searched 4, Memory ×2, Listed 1 dir, subagent"
        )
    }

    func testBuilderCountsPromptAndPreToolHooksNotPosts() {
        var builder = GrokActivityBuilder()
        builder.addMessage("I'll start by reading the docs.")
        builder.addHook(eventName: "user_prompt_submit", runCount: 1)
        builder.addHook(eventName: "pre_tool_use", runCount: 1)
        builder.addTool(id: "1", title: "Read `/tmp/skills/foo/SKILL.md`")
        builder.addHook(eventName: "pre_tool_use", runCount: 1)
        builder.addTool(id: "2", title: "List `/tmp/project`")
        builder.addHook(eventName: "pre_tool_use", runCount: 1)
        builder.addTool(id: "3", title: "Read `/tmp/project/docs/stack-map.md`")
        builder.addHook(eventName: "pre_tool_use", runCount: 1)
        builder.addTool(id: "4", title: "Read `/tmp/project/README.md`")
        builder.addHook(eventName: "post_tool_use", runCount: 1)
        builder.addHook(eventName: "post_tool_use", runCount: 1)
        builder.finish()

        XCTAssertEqual(builder.parts.count, 2)
        guard case .text(let text) = builder.parts[0] else {
            return XCTFail("expected leading text")
        }
        XCTAssertTrue(text.contains("I'll start"))
        guard case .activity(let line) = builder.parts[1] else {
            return XCTFail("expected activity line")
        }
        XCTAssertEqual(line.summary, "Read 1 skill, Read 2 files, Listed 1 dir")
        XCTAssertEqual(line.hookCount, 5)
        XCTAssertTrue(line.isLead)
        XCTAssertEqual(line.displayText, "Read 1 skill, Read 2 files, Listed 1 dir  [hooks: 5]")
    }

    func testBuilderStopLineAndFollowOnText() {
        var builder = GrokActivityBuilder()
        builder.addMessage("Next I’ll skim the usage guide.")
        builder.addTool(id: "a", title: "Read `/tmp/USAGE.md`")
        builder.addTool(id: "b", title: "Read `/tmp/adr.md`")
        builder.addTool(id: "c", title: "Read `/tmp/routing.md`")
        builder.addTool(id: "d", title: "List `/tmp/docs`")
        builder.addHook(eventName: "pre_tool_use", runCount: 1)
        builder.addHook(eventName: "pre_tool_use", runCount: 1)
        builder.addHook(eventName: "pre_tool_use", runCount: 1)
        builder.addHook(eventName: "stop", runCount: 3)
        builder.addMessage("**This repo is the operator playbook.**")
        builder.finish()

        let activities = builder.parts.compactMap { part -> GrokActivityLine? in
            if case .activity(let line) = part { return line }
            return nil
        }
        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(activities[0].summary, "Read 3 files, Listed 1 dir")
        XCTAssertTrue(activities[0].isLead)
        XCTAssertEqual(activities[1].summary, "stop")
        XCTAssertEqual(activities[1].hookCount, 3)
        XCTAssertFalse(activities[1].isLead)
        XCTAssertTrue(builder.textContent.contains("operator playbook"))
    }

    func testUpdatesJSONLRebuildsInterleavedParts() {
        let jsonl = """
        {"method":"session/update","params":{"update":{"sessionUpdate":"hook_execution","event_name":"user_prompt_submit","runs":[{}]}}}
        {"method":"session/update","params":{"update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"overview"}}}}
        {"method":"session/update","params":{"update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"I'll start."}}}}
        {"method":"session/update","params":{"update":{"sessionUpdate":"hook_execution","event_name":"pre_tool_use","runs":[{}]}}}
        {"method":"session/update","params":{"update":{"sessionUpdate":"tool_call","toolCallId":"t1","title":"read_file"}}}
        {"method":"session/update","params":{"update":{"sessionUpdate":"tool_call_update","toolCallId":"t1","title":"Read `/tmp/skills/x/SKILL.md`"}}}
        {"method":"session/update","params":{"update":{"sessionUpdate":"tool_call_update","toolCallId":"t2","title":"List `/tmp/project`"}}}
        {"method":"session/update","params":{"update":{"sessionUpdate":"hook_execution","event_name":"stop","runs":[{},{},{}]}}}
        {"method":"session/update","params":{"update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Done."}}}}
        {"method":"session/update","params":{"update":{"sessionUpdate":"turn_completed"}}}
        """
        let turns = GrokActivityLog.turns(fromJSONL: jsonl)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].userText, "overview")
        XCTAssertTrue(turns[0].parts.contains(where: \.isActivity))
        XCTAssertTrue(turns[0].parts.compactMap(\.text).joined().contains("I'll start."))
        XCTAssertTrue(turns[0].parts.compactMap(\.text).joined().contains("Done."))
        let summaries = turns[0].parts.compactMap { part -> String? in
            if case .activity(let line) = part { return line.displayText }
            return nil
        }
        XCTAssertTrue(summaries.contains(where: { $0.contains("Read 1 skill") && $0.contains("Listed 1 dir") }))
        XCTAssertTrue(summaries.contains(where: { $0.hasPrefix("stop") && $0.contains("[hooks: 3]") }))
    }

    func testAttachActivityIfNeededWritesPartsWithoutReplacingText() throws {
        let sessionID = UUID()
        defer { SessionMessageStore.remove(for: sessionID) }

        let grokHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-activity-\(UUID().uuidString)", isDirectory: true)
        GrokSessionTranscriptImporter.grokHomeDirectory = grokHome
        defer {
            GrokSessionTranscriptImporter.grokHomeDirectory = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".grok", isDirectory: true)
            try? FileManager.default.removeItem(at: grokHome)
        }

        let workspace = URL(fileURLWithPath: "/tmp/activity-demo")
        let grokID = "01a00bbf-activity-demo"
        let historyURL = GrokSessionTranscriptImporter.chatHistoryURL(
            workspacePath: workspace,
            grokSessionID: grokID
        )!
        try FileManager.default.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let updates = """
        {"method":"session/update","params":{"update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"overview"}}}}
        {"method":"session/update","params":{"update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"I'll start."}}}}
        {"method":"session/update","params":{"update":{"sessionUpdate":"tool_call_update","toolCallId":"t1","title":"Read `/tmp/README.md`"}}}
        {"method":"session/update","params":{"update":{"sessionUpdate":"hook_execution","event_name":"pre_tool_use","runs":[{}]}}}
        {"method":"session/update","params":{"update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":" All done."}}}}
        {"method":"session/update","params":{"update":{"sessionUpdate":"turn_completed"}}}
        """
        try updates.write(
            to: historyURL.deletingLastPathComponent().appendingPathComponent("updates.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let current = [
            Message(role: .user, content: "overview"),
            Message(role: .assistant, content: "I'll start. All done.")
        ]
        let attached = SessionTranscriptRecovery.attachActivityIfNeeded(
            messages: current,
            grokSessionID: grokID,
            workspacePath: workspace
        )
        XCTAssertEqual(attached.last?.content, "I'll start. All done.")
        XCTAssertTrue(attached.last?.hasActivityParts == true)
        XCTAssertTrue(
            attached.last?.parts.contains(where: { part in
                if case .activity(let line) = part {
                    return line.summary.contains("Read 1 file")
                }
                return false
            }) == true
        )
    }

    func testAttachActivityKeepsTextOnlyTurnFromStealingLaterTools() {
        let textOnly = GrokActivityLog.Turn(
            userText: "hi",
            parts: [.text("Hello.")]
        )
        let withTools = GrokActivityLog.Turn(
            userText: "read it",
            parts: [
                .text("I'll look."),
                .activity(GrokActivityLine(summary: "Read 1 file", hookCount: 1, isLead: true)),
                .text(" Done.")
            ]
        )
        let messages = [
            Message(role: .user, content: "hi"),
            Message(role: .assistant, content: "Hello."),
            Message(role: .user, content: "read it"),
            Message(role: .assistant, content: "I'll look. Done.")
        ]
        let attached = SessionTranscriptRecovery.attachActivity(
            messages: messages,
            turns: [textOnly, withTools]
        )
        XCTAssertFalse(attached[1].hasActivityParts)
        XCTAssertTrue(attached[3].hasActivityParts)
        XCTAssertEqual(attached[1].content, "Hello.")
        XCTAssertTrue(
            attached[3].parts.contains(where: { part in
                if case .activity(let line) = part {
                    return line.summary.contains("Read 1 file")
                }
                return false
            })
        )
    }

    func testLateChunksStayOnCompletedAssistantUntilNextSendBegins() {
        let previous = UUID()
        let next = UUID()
        let until = Date().addingTimeInterval(2)

        XCTAssertEqual(
            LateAssistantChunkRouting.destination(
                streamingID: next,
                currentPromptSendBegun: false,
                lateUntil: until,
                previousAssistantID: previous
            ),
            .late(previous)
        )
        XCTAssertEqual(
            LateAssistantChunkRouting.destination(
                streamingID: next,
                currentPromptSendBegun: true,
                lateUntil: until,
                previousAssistantID: previous
            ),
            .streaming(next)
        )
        XCTAssertEqual(
            LateAssistantChunkRouting.destination(
                streamingID: nil,
                currentPromptSendBegun: false,
                lateUntil: until,
                previousAssistantID: previous
            ),
            .late(previous)
        )
    }

    func testLateChunkWindowStaysOpenAfterJsonlReconcile() {
        let previous = UUID()
        let until = Date().addingTimeInterval(2)
        XCTAssertEqual(
            LateAssistantChunkRouting.destination(
                streamingID: nil,
                currentPromptSendBegun: false,
                lateUntil: until,
                previousAssistantID: previous
            ),
            .late(previous)
        )
        XCTAssertNil(
            LateAssistantChunkRouting.destination(
                streamingID: nil,
                currentPromptSendBegun: false,
                lateUntil: Date().addingTimeInterval(-0.1),
                previousAssistantID: previous
            )
        )
    }

    func testFailedPromptKeepsActivityOnlyAssistant() {
        XCTAssertFalse(
            FailedPromptCleanup.shouldDiscardEmptyAssistant(
                content: "",
                hasActivityParts: true
            )
        )
        XCTAssertTrue(
            FailedPromptCleanup.shouldDiscardEmptyAssistant(
                content: "   ",
                hasActivityParts: false
            )
        )
        XCTAssertFalse(
            FailedPromptCleanup.shouldDiscardEmptyAssistant(
                content: "partial answer",
                hasActivityParts: false
            )
        )
    }

    func testMessageDecodeWithoutPartsStaysCompatible() throws {
        let old = Message(role: .assistant, content: "hello")
        var data = try JSONEncoder().encode(old)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "parts")
        data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.content, "hello")
        XCTAssertTrue(decoded.parts.isEmpty)
    }

    func testReplaceContentKeepsActivityAndExtendsLastText() {
        var message = Message(
            role: .assistant,
            content: "Hello",
            parts: [
                .text("Hello"),
                .activity(GrokActivityLine(summary: "Read 1 file", hookCount: 1, isLead: true))
            ]
        )
        message.replaceContent("Hello world")
        XCTAssertEqual(message.content, "Hello world")
        XCTAssertEqual(message.parts.count, 2)
        XCTAssertTrue(message.hasActivityParts)
        if case .text(let text) = message.parts.first {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("expected text part to absorb the tail")
        }
    }

    func testSanitizerDropsToolCallUpdateFragments() {
        let fragment = #"""
        b7253ac98ff2-1595","agentTimestampMs":1787051849708,"promptId":"01a01495-9c83-74d1-89a2-76b8b9525b6c","streamStartMs":1787051840405,"turnStartMs":1787051744404,"updateType":"ToolCallUpdate","updateParams":{"toolCallId":"call-a7f8b242-4078-437c-95b8-3bd33f11bdd7-29","status":"Completed"}}}
        """#
        XCTAssertTrue(AssistantTranscriptSanitizer.isProtocolNoise(fragment))
        XCTAssertTrue(AssistantTranscriptSanitizer.shouldDropRawLine(fragment))
        XCTAssertTrue(AssistantTranscriptSanitizer.strip(fragment).isEmpty)
        XCTAssertEqual(
            AssistantTranscriptSanitizer.strip("I'll drive Terminal.\n\(fragment)\nDone.")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "I'll drive Terminal.\nDone."
        )
        XCTAssertNil(AssistantTranscriptSanitizer.usableChunk(fragment))
        XCTAssertTrue(AssistantTranscriptSanitizer.shouldDropRawLine(#"{"updateType":"ToolCallUpdate"}"#))
        XCTAssertFalse(AssistantTranscriptSanitizer.shouldDropRawLine("[process stopped]"))
    }

    func testSanitizerKeepsOrdinaryAssistantProseAndJSONExamples() {
        XCTAssertEqual(
            AssistantTranscriptSanitizer.strip("Use `{\"ok\": true}` in the payload."),
            "Use `{\"ok\": true}` in the payload."
        )
        XCTAssertFalse(AssistantTranscriptSanitizer.isProtocolNoise("I'll list apps and then drive Terminal."))
        XCTAssertEqual(
            AssistantTranscriptSanitizer.strip(
                #"I'll start.{"updateType":"ToolCallUpdate","updateParams":{"status":"Completed"}}"#
            ).trimmingCharacters(in: .whitespacesAndNewlines),
            "I'll start."
        )
        XCTAssertEqual(
            AssistantTranscriptSanitizer.strip(
                "I'll start.{\"updateType\":\"ToolCallUpdate\",\"updateParams\":{\"status\":\"Completed\""
            ).trimmingCharacters(in: .whitespacesAndNewlines),
            "I'll start."
        )
        XCTAssertEqual(
            AssistantTranscriptSanitizer.usableChunk(
                #"I'll start.{"updateType":"ToolCallUpdate","updateParams":{"status":"Completed"}}"#
            ),
            "I'll start."
        )
    }

    func testSanitizerDropsProtocolOnlyAssistantBubbles() {
        let noise = Message(
            role: .assistant,
            content: #"{"updateType":"ToolCallUpdate","updateParams":{"status":"Completed"}}"#
        )
        let kept = Message(role: .assistant, content: "I'll start.")
        let user = Message(role: .user, content: "overview")
        let cleaned = AssistantTranscriptSanitizer.cleanedTranscript([user, noise, kept])
        XCTAssertEqual(cleaned.map(\.content), ["overview", "I'll start."])
    }

    func testBuilderIgnoresProtocolChunks() {
        var builder = GrokActivityBuilder()
        builder.addMessage("I'll start.")
        builder.addMessage(
            #""updateType":"ToolCallUpdate","updateParams":{"toolCallId":"t1","status":"Completed"}}}"#
        )
        builder.addMessage(" Done.")
        builder.finish()
        XCTAssertEqual(builder.textContent, "I'll start. Done.")
    }

    func testAlignDoesNotReattachProtocolTail() {
        let parts: [TranscriptPart] = [
            .text("I'll start."),
            .activity(GrokActivityLine(summary: "Read 1 file", hookCount: 0, isLead: true))
        ]
        let polluted = "I'll start.{\"updateType\":\"ToolCallUpdate\",\"updateParams\":{\"status\":\"Completed\"}}"
        let aligned = GrokActivityLog.align(parts, toContent: polluted)
        XCTAssertEqual(aligned.compactMap(\.text).joined(), "I'll start.")
        XCTAssertTrue(aligned.contains(where: \.isActivity))
    }
}
