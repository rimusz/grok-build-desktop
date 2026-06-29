import Foundation

enum UpdateSettingsKeys {
    static let autoCheckEnabled = "grokbuild.updates.autoCheckEnabled"
    static let dismissedVersion = "grokbuild.updates.dismissedVersion"
    static let dismissedCLIVersion = "grokbuild.updates.dismissedCLIVersion"
    static let lastCheckDate = "grokbuild.updates.lastCheckDate"
}

enum UpdateSettingsStore {
    static let checkInterval: TimeInterval = 24 * 60 * 60
    static let launchCheckDelay: TimeInterval = 30

    static var autoCheckEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: UpdateSettingsKeys.autoCheckEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: UpdateSettingsKeys.autoCheckEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UpdateSettingsKeys.autoCheckEnabled)
        }
    }

    static var dismissedVersion: String? {
        get {
            let value = UserDefaults.standard.string(forKey: UpdateSettingsKeys.dismissedVersion)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: UpdateSettingsKeys.dismissedVersion)
            } else {
                UserDefaults.standard.removeObject(forKey: UpdateSettingsKeys.dismissedVersion)
            }
        }
    }

    static var lastCheckDate: Date? {
        get {
            UserDefaults.standard.object(forKey: UpdateSettingsKeys.lastCheckDate) as? Date
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: UpdateSettingsKeys.lastCheckDate)
            } else {
                UserDefaults.standard.removeObject(forKey: UpdateSettingsKeys.lastCheckDate)
            }
        }
    }

    static func shouldNotify(for release: UpdateChecker.AppRelease) -> Bool {
        guard release.updateAvailable else { return false }
        return dismissedVersion != release.latestVersion
    }

    static func skipVersion(_ version: String) {
        dismissedVersion = UpdateChecker.normalizedVersion(version)
        NotificationCenter.default.post(name: .grokBuildUpdateStateChanged, object: nil)
    }

    static var dismissedCLIVersion: String? {
        get {
            let value = UserDefaults.standard.string(forKey: UpdateSettingsKeys.dismissedCLIVersion)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: UpdateSettingsKeys.dismissedCLIVersion)
            } else {
                UserDefaults.standard.removeObject(forKey: UpdateSettingsKeys.dismissedCLIVersion)
            }
        }
    }

    static func shouldNotifyCLI(for status: UpdateChecker.GrokCLIStatus) -> Bool {
        guard let latest = status.latestVersion else { return false }
        return dismissedCLIVersion != latest
    }

    static func skipCLIVersion(_ version: String) {
        dismissedCLIVersion = UpdateChecker.normalizedVersion(version)
        NotificationCenter.default.post(name: .grokBuildUpdateStateChanged, object: nil)
    }
}
