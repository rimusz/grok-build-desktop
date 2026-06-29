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

    func testPreferredAppZipAssetNameUsesTag() {
        XCTAssertEqual(
            UpdateChecker.preferredAppZipAssetName(tagName: "v0.2.0"),
            "GrokBuild-v0.2.0.app.zip"
        )
    }

    func testSelectDownloadAssetPrefersExactMatch() {
        let assets = [
            UpdateChecker.GitHubReleaseAsset(
                name: "GrokBuild-v0.2.0-macOS.dmg",
                browserDownloadURL: URL(string: "https://example.com/a.dmg")!
            ),
            UpdateChecker.GitHubReleaseAsset(
                name: "GrokBuild-v0.2.0.app.zip",
                browserDownloadURL: URL(string: "https://example.com/a.zip")!
            ),
        ]

        let selected = UpdateChecker.selectDownloadAsset(from: assets, tagName: "v0.2.0")
        XCTAssertEqual(selected?.absoluteString, "https://example.com/a.zip")
    }

    func testSelectDownloadAssetFallsBackToAnyAppZip() {
        let assets = [
            UpdateChecker.GitHubReleaseAsset(
                name: "GrokBuild-v0.2.0-macOS.dmg",
                browserDownloadURL: URL(string: "https://example.com/a.dmg")!
            ),
            UpdateChecker.GitHubReleaseAsset(
                name: "GrokBuild-custom.app.zip",
                browserDownloadURL: URL(string: "https://example.com/custom.zip")!
            ),
        ]

        let selected = UpdateChecker.selectDownloadAsset(from: assets, tagName: "v9.9.9")
        XCTAssertEqual(selected?.absoluteString, "https://example.com/custom.zip")
    }

    func testSelectDownloadAssetReturnsNilWhenMissing() {
        let assets = [
            UpdateChecker.GitHubReleaseAsset(
                name: "notes.txt",
                browserDownloadURL: URL(string: "https://example.com/notes.txt")!
            ),
        ]

        XCTAssertNil(UpdateChecker.selectDownloadAsset(from: assets, tagName: "v0.2.0"))
    }

    func testIsNotarizedReleaseDetectsReleaseTitle() {
        XCTAssertTrue(UpdateChecker.isNotarizedRelease(
            name: "v0.1.10 (Notarized)",
            body: nil
        ))
        XCTAssertTrue(UpdateChecker.isNotarizedRelease(
            name: "v0.1.10 (42) (Notarized)",
            body: nil
        ))
        XCTAssertFalse(UpdateChecker.isNotarizedRelease(
            name: "v0.1.11 (Unsigned)",
            body: nil
        ))
    }

    func testIsNotarizedReleaseDetectsReleaseNotesFallback() {
        XCTAssertTrue(UpdateChecker.isNotarizedRelease(
            name: "v0.1.10",
            body: "This version is properly code-signed and notarized. No Gatekeeper warnings."
        ))
    }

    func testIsNotarizedReleaseIgnoresDrafts() {
        XCTAssertFalse(UpdateChecker.isNotarizedRelease(
            name: "v0.1.10 (Notarized)",
            body: nil,
            draft: true
        ))
    }

    func testLatestNotarizedReleaseSkipsUnsignedLatest() {
        let unsigned = UpdateChecker.GitHubReleaseSummary(
            tagName: "v0.1.11",
            name: "v0.1.11 (Unsigned)",
            body: "Unsigned build",
            htmlURL: URL(string: "https://example.com/unsigned")!,
            publishedAt: Date(),
            draft: false,
            assets: []
        )
        let notarized = UpdateChecker.GitHubReleaseSummary(
            tagName: "v0.1.10",
            name: "v0.1.10 (Notarized)",
            body: "This version is properly code-signed and notarized.",
            htmlURL: URL(string: "https://example.com/notarized")!,
            publishedAt: Date().addingTimeInterval(-86_400),
            draft: false,
            assets: []
        )

        let latest = UpdateChecker.latestNotarizedRelease(from: [unsigned, notarized])
        XCTAssertEqual(latest?.tagName, "v0.1.10")
    }

    func testGrokCLIStatusParsesUpToDateResponse() {
        let json = """
        {"currentVersion":"0.2.60","latestVersion":"0.2.60","updateAvailable":false,"channel":"stable","installer":"brew"}
        """

        let status = UpdateChecker.grokCLIStatus(fromCheckOutput: json, stderr: "")

        guard case .upToDate(let info) = status.state else {
            return XCTFail("Expected upToDate, got \(status.state)")
        }
        XCTAssertEqual(info.current, "0.2.60")
        XCTAssertEqual(info.latest, "0.2.60")
        XCTAssertEqual(info.channel, "stable")
        XCTAssertEqual(info.installer, "brew")
        XCTAssertFalse(status.updateAvailable)
    }

    func testGrokCLIStatusParsesUpdateAvailableResponse() {
        let json = """
        {"currentVersion":"0.2.59","latestVersion":"0.2.60","updateAvailable":true,"channel":"stable"}
        """

        let status = UpdateChecker.grokCLIStatus(fromCheckOutput: json, stderr: "")

        guard case .updateAvailable(let info) = status.state else {
            return XCTFail("Expected updateAvailable, got \(status.state)")
        }
        XCTAssertEqual(info.current, "0.2.59")
        XCTAssertEqual(info.latest, "0.2.60")
        XCTAssertEqual(info.channel, "stable")
        XCTAssertTrue(status.updateAvailable)
        XCTAssertEqual(status.latestVersion, "0.2.60")
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

final class UpdateSettingsStoreTests: XCTestCase {
    func testShouldNotifyWhenUpdateAvailableAndNotDismissed() {
        let release = UpdateChecker.AppRelease(
            installedVersion: "0.1.0",
            latestVersion: "0.2.0",
            tagName: "v0.2.0",
            releaseURL: URL(string: "https://example.com")!,
            downloadURL: URL(string: "https://example.com/app.zip"),
            publishedAt: nil,
            updateAvailable: true
        )

        UpdateSettingsStore.dismissedVersion = nil
        XCTAssertTrue(UpdateSettingsStore.shouldNotify(for: release))

        UpdateSettingsStore.skipVersion("0.2.0")
        XCTAssertFalse(UpdateSettingsStore.shouldNotify(for: release))
    }

    func testAutoCheckEnabledDefaultsToTrueWhenUnset() {
        let key = UpdateSettingsKeys.autoCheckEnabled
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        XCTAssertTrue(UpdateSettingsStore.autoCheckEnabled)
    }

    func testShouldNotifyCLIWhenUpdateAvailableAndNotDismissed() {
        let status = UpdateChecker.GrokCLIStatus(
            state: .updateAvailable(
                UpdateChecker.GrokCLIVersionInfo(
                    current: "0.2.59",
                    latest: "0.2.60",
                    channel: "stable",
                    installer: nil
                )
            )
        )

        UpdateSettingsStore.dismissedCLIVersion = nil
        XCTAssertTrue(UpdateSettingsStore.shouldNotifyCLI(for: status))

        UpdateSettingsStore.skipCLIVersion("0.2.60")
        XCTAssertFalse(UpdateSettingsStore.shouldNotifyCLI(for: status))
    }
}
