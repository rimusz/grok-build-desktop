import XCTest
@testable import GrokBuild

final class GrokCLIUpdaterTests: XCTestCase {
    @MainActor
    func testResetReturnsToIdle() {
        let updater = GrokCLIUpdater.shared
        updater.reset()
        XCTAssertEqual(updater.phase, .idle)
        XCTAssertFalse(updater.isBusy)
    }

    func testTrimmedOutputTruncatesLongText() {
        let long = String(repeating: "x", count: 1500)
        let trimmed = GrokCLIUpdater.trimmedOutput(long, limit: 100)
        XCTAssertTrue(trimmed.hasSuffix("…"))
        XCTAssertLessThan(trimmed.count, long.count)
    }

    func testFailureMessageIncludesOutputWhenPresent() {
        let result = GrokCLIResult(
            stdout: "partial output",
            stderr: "",
            exitCode: 1
        )
        let message = GrokCLIUpdater.failureMessage(from: result)
        XCTAssertTrue(message.contains("exit code 1"))
        XCTAssertTrue(message.contains("partial output"))
    }

    func testFailureMessageWithoutOutput() {
        let result = GrokCLIResult(stdout: "", stderr: "", exitCode: 2)
        let message = GrokCLIUpdater.failureMessage(from: result)
        XCTAssertEqual(message, "grok update failed with exit code 2.")
    }

#if DEBUG
    @MainActor
    func testSimulatedCLIUpdateDoesNotRunRealUpdater() async {
        UpdateDebugSimulator.apply(.cli)

        await GrokCLIUpdater.shared.updateCLI()

        guard case .success(let version) = GrokCLIUpdater.shared.phase else {
            return XCTFail("Expected simulated CLI update to succeed.")
        }
        XCTAssertEqual(version, UpdateDebugSimulator.simulatedCLIVersion)
        XCTAssertFalse(UpdateScheduler.hasActionableCLIUpdate)

        await UpdateDebugSimulator.clear()
    }
#endif
}
