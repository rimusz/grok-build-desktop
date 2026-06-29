import Foundation

@MainActor
enum UpdateScheduler {
    private static var schedulerTask: Task<Void, Never>?
    private(set) static var cachedAppRelease: UpdateChecker.AppRelease?
    private(set) static var cachedCLIStatus: UpdateChecker.GrokCLIStatus?

    static var hasActionableAppUpdate: Bool {
        guard let release = cachedAppRelease else { return false }
        return UpdateSettingsStore.shouldNotify(for: release)
    }

    static var hasActionableCLIUpdate: Bool {
        guard let status = cachedCLIStatus else { return false }
        return UpdateSettingsStore.shouldNotifyCLI(for: status)
    }

    static var hasAnyActionableUpdate: Bool {
        hasActionableAppUpdate || hasActionableCLIUpdate
    }

    static func setCachedCLIStatus(_ status: UpdateChecker.GrokCLIStatus) {
        cachedCLIStatus = status
    }

    static func start() {
        guard schedulerTask == nil else { return }

        schedulerTask = Task {
            try? await Task.sleep(for: .seconds(UpdateSettingsStore.launchCheckDelay))
            await performCheck(trigger: .launch)

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(UpdateSettingsStore.checkInterval))
                await performCheck(trigger: .periodic)
            }
        }
    }

    static func checkNow() async {
        await performCheck(trigger: .manual)
    }

    static func cachedResults() -> (app: Result<UpdateChecker.AppRelease, Error>, cli: UpdateChecker.GrokCLIStatus)? {
        guard cachedAppRelease != nil || cachedCLIStatus != nil else { return nil }
        let app: Result<UpdateChecker.AppRelease, Error>
        if let release = cachedAppRelease {
            app = .success(release)
        } else {
            app = .failure(NSError(
                domain: "GrokBuildUpdates",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No cached GrokBuild release check is available yet."]
            ))
        }
        return (app, cachedCLIStatus ?? UpdateChecker.GrokCLIStatus(state: .checkFailed("Not checked yet.")))
    }

    private enum Trigger {
        case launch, periodic, manual
    }

    private static func performCheck(trigger: Trigger) async {
        if trigger != .manual, !UpdateSettingsStore.autoCheckEnabled {
            return
        }

        async let appResult = fetchAppRelease()
        async let cliStatus = UpdateChecker.checkGrokCLI()
        let (app, cli) = await (appResult, cliStatus)

        cachedCLIStatus = cli
        UpdateSettingsStore.lastCheckDate = Date()

        switch app {
        case .success(let release):
            cachedAppRelease = release
        case .failure:
            break
        }

        NotificationCenter.default.post(name: .grokBuildUpdateStateChanged, object: nil)

        if hasAnyActionableUpdate {
            var userInfo: [String: Any] = [:]
            if hasActionableAppUpdate, let release = cachedAppRelease {
                userInfo["appVersion"] = release.latestVersion
            }
            if hasActionableCLIUpdate, let latest = cli.latestVersion {
                userInfo["cliVersion"] = latest
            }
            NotificationCenter.default.post(
                name: .grokBuildUpdateAvailable,
                object: nil,
                userInfo: userInfo
            )
        }
    }

    private static func fetchAppRelease() async -> Result<UpdateChecker.AppRelease, Error> {
        do {
            return .success(try await UpdateChecker.checkAppRelease())
        } catch {
            return .failure(error)
        }
    }

#if DEBUG
    static func setCachedAppRelease(_ release: UpdateChecker.AppRelease?) {
        cachedAppRelease = release
    }

    static func postSimulatedUpdateNotifications() {
        NotificationCenter.default.post(name: .grokBuildUpdateStateChanged, object: nil)

        guard hasAnyActionableUpdate else { return }

        var userInfo: [String: Any] = [:]
        if hasActionableAppUpdate, let release = cachedAppRelease {
            userInfo["appVersion"] = release.latestVersion
        }
        if hasActionableCLIUpdate, let latest = cachedCLIStatus?.latestVersion {
            userInfo["cliVersion"] = latest
        }
        NotificationCenter.default.post(
            name: .grokBuildUpdateAvailable,
            object: nil,
            userInfo: userInfo
        )
    }
#endif
}
