import Foundation
import XCTest

/// Packaging contracts for codesign / Hardened Runtime (see issue #17).
final class PackagingEntitlementsTests: XCTestCase {
    func testGrokBuildEntitlementsIncludeAudioInputForHardenedRuntime() throws {
        let url = try entitlementsURL()
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = plist as? [String: Any] else {
            return XCTFail("Expected entitlements dictionary at \(url.path)")
        }

        XCTAssertEqual(dict["com.apple.security.cs.allow-unsigned-executable-memory"] as? Bool, true)
        // Without device.audio-input, notarized Hardened Runtime builds never prompt for Microphone
        // and Voice control records silence (GitHub issue #17).
        XCTAssertEqual(dict["com.apple.security.device.audio-input"] as? Bool, true)
    }

    func testCodesignScriptReferencesEntitlementsFile() throws {
        let root = try repoRoot()
        let script = try String(contentsOf: root.appendingPathComponent("scripts/codesign-app-bundle.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("GrokBuild.entitlements"))
        XCTAssertTrue(script.contains("--entitlements"))
        XCTAssertTrue(script.contains("--options runtime"))
    }

    // MARK: - Helpers

    private func entitlementsURL() throws -> URL {
        let url = try repoRoot().appendingPathComponent("scripts/GrokBuild.entitlements")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing \(url.path)")
        return url
    }

    private func repoRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent() // Tests/GrokBuildTests
        url = url.deletingLastPathComponent() // Tests
        url = url.deletingLastPathComponent() // repo root
        let marker = url.appendingPathComponent("scripts/codesign-app-bundle.sh")
        guard FileManager.default.fileExists(atPath: marker.path) else {
            throw XCTSkip("Could not locate repo root from \(#filePath)")
        }
        return url
    }
}
