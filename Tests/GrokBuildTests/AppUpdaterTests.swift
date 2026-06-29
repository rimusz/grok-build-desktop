import XCTest
@testable import GrokBuild

final class AppUpdaterTests: XCTestCase {
#if DEBUG
    @MainActor
    func testSimulatedAppDownloadReachesReadyToInstall() async {
        UpdateDebugSimulator.apply(.app)

        guard let release = UpdateScheduler.cachedAppRelease else {
            return XCTFail("Expected simulated app release.")
        }

        await AppUpdater.shared.downloadAndVerify(release: release)

        guard case .readyToInstall(_, let version) = AppUpdater.shared.phase else {
            return XCTFail("Expected simulated download to finish ready to install.")
        }
        XCTAssertEqual(version, UpdateDebugSimulator.simulatedAppVersion)

        await UpdateDebugSimulator.clear()
        AppUpdater.shared.reset()
    }
#endif
}
