import AppKit
import Foundation

@MainActor
enum UpdateUI {
    /// Present the updates panel.
    /// - Parameter refresh: When `true`, re-check GitHub and grok CLI first.
    ///   When `false`, show cached status — use for the main-window banner and post-check "up to date" results.
    static func presentUpdatePanel(refresh: Bool = true, onDismiss: @escaping () -> Void = {}) async {
        if refresh {
            await UpdateScheduler.checkNow()
        }

        let cli = UpdateScheduler.cachedCLIStatus
            ?? UpdateChecker.GrokCLIStatus(state: .checkFailed("Not checked yet."))

        let app: Result<UpdateChecker.AppRelease, Error>
        if let release = UpdateScheduler.cachedAppRelease {
            app = .success(release)
        } else if let cached = UpdateScheduler.cachedResults()?.app {
            app = cached
        } else if refresh {
            app = await fetchAppUpdateResult()
        } else {
            app = .failure(NSError(
                domain: "GrokBuildUpdates",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "No update check has run yet. Choose Check for Updates… to refresh."]
            ))
        }

        UpdatePanel.show(app: app, cli: cli, onDismiss: onDismiss)
    }

    static func restartLiveSessions() {
        NotificationCenter.default.post(name: .grokBuildRestartSessionsRequested, object: nil)
    }

    private static func fetchAppUpdateResult() async -> Result<UpdateChecker.AppRelease, Error> {
        do {
            return .success(try await UpdateChecker.checkAppRelease())
        } catch {
            return .failure(error)
        }
    }
}
