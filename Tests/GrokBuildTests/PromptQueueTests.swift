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
}
