import XCTest
@testable import GrokBuild

final class GrokSessionReplayTests: XCTestCase {
    func testReplayDetectedFromParamsMeta() {
        let params: [String: Any] = [
            "_meta": ["isReplay": true],
            "update": ["sessionUpdate": "tool_call"]
        ]
        XCTAssertTrue(GrokSessionReplay.isReplaySessionUpdate(params: params))
    }

    func testReplayDetectedFromUpdateMeta() {
        let params: [String: Any] = [
            "update": [
                "_meta": ["isReplay": true],
                "sessionUpdate": "agent_thought_chunk"
            ]
        ]
        XCTAssertTrue(GrokSessionReplay.isReplaySessionUpdate(params: params))
    }

    func testLiveUpdateNotReplay() {
        let params: [String: Any] = [
            "update": ["sessionUpdate": "agent_message_chunk", "content": ["text": "hi"]]
        ]
        XCTAssertFalse(GrokSessionReplay.isReplaySessionUpdate(params: params))
    }

    func testReplayFalseWhenMetaMissing() {
        let params: [String: Any] = [
            "_meta": [:] as [String: Any],
            "update": ["sessionUpdate": "tool_call_update"]
        ]
        XCTAssertFalse(GrokSessionReplay.isReplaySessionUpdate(params: params))
    }

    func testReplayFalseWhenIsReplayFalse() {
        let params: [String: Any] = [
            "_meta": ["isReplay": false],
            "update": ["sessionUpdate": "tool_call"]
        ]
        XCTAssertFalse(GrokSessionReplay.isReplaySessionUpdate(params: params))
    }
}
