#if DEBUG
import Foundation

@MainActor
enum UpdateDebugSimulator {
    static let simulatedAppVersion = "99.0.0"
    static let simulatedCLIVersion = "99.0.0"

    private(set) static var isCLISimulationActive = false
    private(set) static var isAppSimulationActive = false

    enum Scenario {
        case app
        case cli
        case both
    }

    static func isSimulatedAppRelease(_ release: UpdateChecker.AppRelease) -> Bool {
        release.latestVersion == simulatedAppVersion
            && release.downloadURL == nil
            && release.updateAvailable
    }

    static func isSimulatedCLIStatus(_ status: UpdateChecker.GrokCLIStatus?) -> Bool {
        guard case .updateAvailable(let info) = status?.state else { return false }
        return info.latest == simulatedCLIVersion && info.channel?.contains("simulated") == true
    }

    static func apply(_ scenario: Scenario) {
        UpdateSettingsStore.dismissedVersion = nil
        UpdateSettingsStore.dismissedCLIVersion = nil
        GrokCLIUpdater.shared.reset()
        AppUpdater.shared.reset()

        switch scenario {
        case .app:
            isAppSimulationActive = true
            isCLISimulationActive = false
            UpdateScheduler.setCachedAppRelease(simulatedAppRelease())
            if isSimulatedCLIStatus(UpdateScheduler.cachedCLIStatus) {
                Task { UpdateScheduler.setCachedCLIStatus(await UpdateChecker.checkGrokCLI()) }
            }
        case .cli:
            isAppSimulationActive = false
            isCLISimulationActive = true
            UpdateScheduler.setCachedAppRelease(nil)
            UpdateScheduler.setCachedCLIStatus(simulatedCLIStatus())
        case .both:
            isAppSimulationActive = true
            isCLISimulationActive = true
            UpdateScheduler.setCachedAppRelease(simulatedAppRelease())
            UpdateScheduler.setCachedCLIStatus(simulatedCLIStatus())
        }

        UpdateScheduler.postSimulatedUpdateNotifications()
    }

    static func clearSimulationFlags() {
        isAppSimulationActive = false
    }

    static func clear() async {
        isAppSimulationActive = false
        isCLISimulationActive = false
        GrokCLIUpdater.shared.reset()
        AppUpdater.shared.reset()
        await UpdateScheduler.checkNow()
    }

    static func simulatedAppUpToDateRelease() -> UpdateChecker.AppRelease {
        UpdateChecker.AppRelease(
            installedVersion: simulatedAppVersion,
            latestVersion: simulatedAppVersion,
            tagName: "v\(simulatedAppVersion)",
            releaseURL: URL(string: "https://github.com/rimusz/grok-build-desktop/releases/latest")!,
            downloadURL: nil,
            publishedAt: Date(),
            updateAvailable: false
        )
    }

    static func simulatedCLIUpToDateStatus() -> UpdateChecker.GrokCLIStatus {
        UpdateChecker.GrokCLIStatus(
            state: .upToDate(
                UpdateChecker.GrokCLIVersionInfo(
                    current: simulatedCLIVersion,
                    latest: simulatedCLIVersion,
                    channel: "stable (simulated)",
                    installer: "simulated"
                )
            )
        )
    }

    private static func simulatedAppRelease() -> UpdateChecker.AppRelease {
        UpdateChecker.AppRelease(
            installedVersion: AppVersion.short,
            latestVersion: simulatedAppVersion,
            tagName: "v\(simulatedAppVersion)",
            releaseURL: URL(string: "https://github.com/rimusz/grok-build-desktop/releases/latest")!,
            downloadURL: nil,
            publishedAt: Date(),
            updateAvailable: true
        )
    }

    private static func simulatedCLIStatus() -> UpdateChecker.GrokCLIStatus {
        UpdateChecker.GrokCLIStatus(
            state: .updateAvailable(
                UpdateChecker.GrokCLIVersionInfo(
                    current: currentCLIVersion() ?? "0.0.0",
                    latest: simulatedCLIVersion,
                    channel: "stable (simulated)",
                    installer: "simulated"
                )
            )
        )
    }

    private static func currentCLIVersion() -> String? {
        switch UpdateScheduler.cachedCLIStatus?.state {
        case .upToDate(let info), .updateAvailable(let info):
            return info.current
        default:
            return nil
        }
    }
}
#endif
