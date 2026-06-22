import Foundation

enum BrowserBackendID: String, CaseIterable, Identifiable {
    case agentBrowser = "agent-browser"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .agentBrowser: return "agent-browser"
        }
    }
}

struct BrowserSettings: Sendable, Equatable {
    var enabled: Bool
    var backend: BrowserBackendID
    var cdpURL: String
    var profileName: String

    static let defaults = BrowserSettings(
        enabled: false,
        backend: .agentBrowser,
        cdpURL: "",
        profileName: ""
    )
}

enum BrowserSettingsKeys {
    static let enabled = "grokbuild.browser.enabled"
    static let backend = "grokbuild.browser.backend"
    static let cdpURL = "grokbuild.browser.cdpURL"
    static let profileName = "grokbuild.browser.profileName"
}

enum BrowserSettingsStore {
    static func load() -> BrowserSettings {
        let defaults = UserDefaults.standard
        let backendRaw = defaults.string(forKey: BrowserSettingsKeys.backend)
            ?? BrowserSettings.defaults.backend.rawValue

        return BrowserSettings(
            enabled: defaults.object(forKey: BrowserSettingsKeys.enabled) as? Bool
                ?? BrowserSettings.defaults.enabled,
            backend: BrowserBackendID(rawValue: backendRaw) ?? BrowserSettings.defaults.backend,
            cdpURL: defaults.string(forKey: BrowserSettingsKeys.cdpURL)
                ?? BrowserSettings.defaults.cdpURL,
            profileName: defaults.string(forKey: BrowserSettingsKeys.profileName)
                ?? BrowserSettings.defaults.profileName
        )
    }

    static func save(_ settings: BrowserSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.enabled, forKey: BrowserSettingsKeys.enabled)
        defaults.set(settings.backend.rawValue, forKey: BrowserSettingsKeys.backend)
        defaults.set(settings.cdpURL, forKey: BrowserSettingsKeys.cdpURL)
        defaults.set(settings.profileName, forKey: BrowserSettingsKeys.profileName)
    }
}

