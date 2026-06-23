import XCTest
@testable import GrokBuild

final class UpdateCheckerTests: XCTestCase {
    func testNormalizedVersionStripsLeadingV() {
        XCTAssertEqual(UpdateChecker.normalizedVersion("v0.1.3"), "0.1.3")
        XCTAssertEqual(UpdateChecker.normalizedVersion("V1.2.0"), "1.2.0")
        XCTAssertEqual(UpdateChecker.normalizedVersion("  v0.1.3  "), "0.1.3")
    }

    func testCompareVersionsOrdersSemverComponents() {
        XCTAssertEqual(UpdateChecker.compareVersions("0.1.3", "0.1.2"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersions("0.1.2", "0.1.3"), .orderedAscending)
        XCTAssertEqual(UpdateChecker.compareVersions("0.1.3", "0.1.3"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersions("v0.2.0", "0.1.10"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersions("1.0", "1.0.0"), .orderedSame)
    }

    func testCompareVersionsIgnoresNonNumericSuffixes() {
        XCTAssertEqual(UpdateChecker.compareVersions("0.2.60-beta", "0.2.60"), .orderedSame)
    }

    func testGrokCLIStatusParsesUpToDateResponse() {
        let json = """
        {"currentVersion":"0.2.60","latestVersion":"0.2.60","updateAvailable":false,"channel":"stable"}
        """

        let status = UpdateChecker.grokCLIStatus(fromCheckOutput: json, stderr: "")

        guard case .upToDate(let current, let latest, let channel) = status.state else {
            return XCTFail("Expected upToDate, got \(status.state)")
        }
        XCTAssertEqual(current, "0.2.60")
        XCTAssertEqual(latest, "0.2.60")
        XCTAssertEqual(channel, "stable")
        XCTAssertFalse(status.updateAvailable)
    }

    func testGrokCLIStatusParsesUpdateAvailableResponse() {
        let json = """
        {"currentVersion":"0.2.59","latestVersion":"0.2.60","updateAvailable":true,"channel":"stable"}
        """

        let status = UpdateChecker.grokCLIStatus(fromCheckOutput: json, stderr: "")

        guard case .updateAvailable(let current, let latest, let channel) = status.state else {
            return XCTFail("Expected updateAvailable, got \(status.state)")
        }
        XCTAssertEqual(current, "0.2.59")
        XCTAssertEqual(latest, "0.2.60")
        XCTAssertEqual(channel, "stable")
        XCTAssertTrue(status.updateAvailable)
    }

    func testGrokCLIStatusParsesErrorField() {
        let json = """
        {"error":"not logged in"}
        """

        let status = UpdateChecker.grokCLIStatus(fromCheckOutput: json, stderr: "")

        guard case .checkFailed(let message) = status.state else {
            return XCTFail("Expected checkFailed, got \(status.state)")
        }
        XCTAssertEqual(message, "not logged in")
    }

    func testGrokCLIStatusFailsOnMalformedJSON() {
        let status = UpdateChecker.grokCLIStatus(fromCheckOutput: "not json", stderr: "stderr detail")

        guard case .checkFailed(let message) = status.state else {
            return XCTFail("Expected checkFailed, got \(status.state)")
        }
        XCTAssertTrue(message.contains("not json"))
        XCTAssertTrue(message.contains("stderr detail"))
    }

    func testGrokCLIStatusFailsWhenVersionsMissing() {
        let json = """
        {"currentVersion":"","latestVersion":"0.2.60","updateAvailable":false}
        """

        let status = UpdateChecker.grokCLIStatus(fromCheckOutput: json, stderr: "")

        guard case .checkFailed(let message) = status.state else {
            return XCTFail("Expected checkFailed, got \(status.state)")
        }
        XCTAssertEqual(message, "grok update --check did not return version information.")
    }
}
