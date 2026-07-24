import XCTest
@testable import GrokBuild

@MainActor
final class PromptQueueTests: XCTestCase {
    func testEnqueueAndRemoveQueuedPrompt() {
        let store = ChatStore(process: GrokProcess())
        store.enqueuePrompt("first")
        store.enqueuePrompt("second")
        XCTAssertEqual(store.promptQueue, ["first", "second"])
        store.removeQueuedPrompt(at: 0)
        XCTAssertEqual(store.promptQueue, ["second"])
    }

    func testRemoveQueuedPromptOutOfRangeIsNoOp() {
        let store = ChatStore(process: GrokProcess())
        store.enqueuePrompt("only")
        store.removeQueuedPrompt(at: 5)
        XCTAssertEqual(store.promptQueue, ["only"])
    }

    func testSendQueuedPromptNowWhileStreamingKeepsQueueIntact() async {
        let store = ChatStore(process: GrokProcess())
        store.enqueuePrompt("queued-a")
        store.enqueuePrompt("queued-b")
        store.setStreamingForTests(true)

        let ok = await store.sendQueuedPromptNow(at: 0)

        XCTAssertFalse(ok)
        XCTAssertEqual(store.promptQueue, ["queued-a", "queued-b"])
        XCTAssertEqual(store.lastError, "Wait for the current response to finish.")
    }

    func testSendQueuedPromptNowRestoresPromptWhenDeliverFails() async {
        let store = ChatStore(process: GrokProcess())
        // No workspace → deliverPrompt fails after dequeue.
        store.enqueuePrompt("keep-me")
        store.enqueuePrompt("second")

        let ok = await store.sendQueuedPromptNow(at: 0)

        XCTAssertFalse(ok)
        XCTAssertEqual(store.promptQueue, ["keep-me", "second"])
        XCTAssertEqual(store.lastError, "Select a project first.")
    }

    func testShareSessionClearsCaptureFlagWhenSendFails() async {
        let store = ChatStore(process: GrokProcess())
        // No workspace → send("/share") fails; capture flag must not stick.
        let ok = await store.shareSession()
        XCTAssertFalse(ok)
        XCTAssertFalse(store.isPendingShareURLCaptureForTests)
    }
}
