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

enum ExternalBrowserAppID: String, CaseIterable, Identifiable {
    case chrome
    case brave
    case edge
    case arc
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chrome: return "Google Chrome"
        case .brave: return "Brave Browser"
        case .edge: return "Microsoft Edge"
        case .arc: return "Arc"
        case .custom: return "Custom app..."
        }
    }

    var defaultAppURL: URL? {
        let path: String
        switch self {
        case .chrome:
            path = "/Applications/Google Chrome.app"
        case .brave:
            path = "/Applications/Brave Browser.app"
        case .edge:
            path = "/Applications/Microsoft Edge.app"
        case .arc:
            path = "/Applications/Arc.app"
        case .custom:
            return nil
        }

        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static var installedChoices: [ExternalBrowserAppID] {
        let installed = ExternalBrowserAppID.allCases.filter { app in
            app == .custom || app.defaultAppURL != nil
        }
        return installed.contains(.custom) ? installed : installed + [.custom]
    }
}

enum BrowserRuntimeMode: String, CaseIterable, Identifiable {
    case managed
    case external

    var id: String { rawValue }
}

/// Quick-setup presets for common browser-automation targets. Each preset returns
/// settings tuned for that target (runtime mode, app, CDP URL, profile, visibility),
/// leaving `enabled` and `backend` untouched so the toggle stays under user control.
enum BrowserPreset: String, CaseIterable, Identifiable {
    case grokCom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grokCom: return "grok.com (existing Chrome)"
        }
    }

    var summary: String {
        switch self {
        case .grokCom:
            return "External Chrome with a separate `grok-com` profile and visible window, so you can log into grok.com once and let the agent drive Imagine, skills, and connectors."
        }
    }

    var profileName: String {
        switch self {
        case .grokCom: return "grok-com"
        }
    }

    /// Applies the preset to `settings` without changing `enabled` or `backend`.
    func applied(to settings: BrowserSettings) -> BrowserSettings {
        var updated = settings
        switch self {
        case .grokCom:
            updated.runtimeMode = .external
            updated.externalBrowserAppID = .chrome
            updated.externalBrowserAppPath = ""
            updated.cdpURL = "http://127.0.0.1:9222"
            updated.profileName = profileName
            updated.showBrowserWindow = true
            updated.autoStartExternalBrowser = true
        }
        return updated
    }
}

struct BrowserSettings: Sendable, Equatable {
    var enabled: Bool
    var backend: BrowserBackendID
    var runtimeMode: BrowserRuntimeMode
    var cdpURL: String
    var profileName: String
    var showBrowserWindow: Bool
    var externalBrowserAppID: ExternalBrowserAppID
    var externalBrowserAppPath: String
    var autoStartExternalBrowser: Bool

    init(
        enabled: Bool,
        backend: BrowserBackendID,
        runtimeMode: BrowserRuntimeMode = .managed,
        cdpURL: String,
        profileName: String,
        showBrowserWindow: Bool,
        externalBrowserAppID: ExternalBrowserAppID = .chrome,
        externalBrowserAppPath: String = "",
        autoStartExternalBrowser: Bool = true
    ) {
        self.enabled = enabled
        self.backend = backend
        self.runtimeMode = runtimeMode
        self.cdpURL = cdpURL
        self.profileName = profileName
        self.showBrowserWindow = showBrowserWindow
        self.externalBrowserAppID = externalBrowserAppID
        self.externalBrowserAppPath = externalBrowserAppPath
        self.autoStartExternalBrowser = autoStartExternalBrowser
    }

    static let defaults = BrowserSettings(
        enabled: false,
        backend: .agentBrowser,
        runtimeMode: .managed,
        cdpURL: "",
        profileName: "",
        showBrowserWindow: false,
        externalBrowserAppID: .chrome,
        externalBrowserAppPath: "",
        autoStartExternalBrowser: true
    )
}

enum BrowserSettingsKeys {
    static let enabled = "grokbuild.browser.enabled"
    static let backend = "grokbuild.browser.backend"
    static let runtimeMode = "grokbuild.browser.runtimeMode"
    static let cdpURL = "grokbuild.browser.cdpURL"
    static let profileName = "grokbuild.browser.profileName"
    static let showBrowserWindow = "grokbuild.browser.showBrowserWindow"
    static let externalBrowserAppID = "grokbuild.browser.externalBrowserAppID"
    static let externalBrowserAppPath = "grokbuild.browser.externalBrowserAppPath"
    static let autoStartExternalBrowser = "grokbuild.browser.autoStartExternalBrowser"
    static let appliedEnabled = "grokbuild.browser.applied.enabled"
    static let appliedBackend = "grokbuild.browser.applied.backend"
    static let appliedRuntimeMode = "grokbuild.browser.applied.runtimeMode"
    static let appliedCDPURL = "grokbuild.browser.applied.cdpURL"
    static let appliedProfileName = "grokbuild.browser.applied.profileName"
    static let appliedShowBrowserWindow = "grokbuild.browser.applied.showBrowserWindow"
    static let appliedExternalBrowserAppID = "grokbuild.browser.applied.externalBrowserAppID"
    static let appliedExternalBrowserAppPath = "grokbuild.browser.applied.externalBrowserAppPath"
    static let appliedAutoStartExternalBrowser = "grokbuild.browser.applied.autoStartExternalBrowser"
}

enum BrowserSettingsStore {
    static func load() -> BrowserSettings {
        let defaults = UserDefaults.standard
        let backendRaw = defaults.string(forKey: BrowserSettingsKeys.backend)
            ?? BrowserSettings.defaults.backend.rawValue
        let runtimeModeRaw = defaults.string(forKey: BrowserSettingsKeys.runtimeMode)
            ?? BrowserSettings.defaults.runtimeMode.rawValue
        let externalBrowserRaw = defaults.string(forKey: BrowserSettingsKeys.externalBrowserAppID)
            ?? BrowserSettings.defaults.externalBrowserAppID.rawValue

        return BrowserSettings(
            enabled: defaults.object(forKey: BrowserSettingsKeys.enabled) as? Bool
                ?? BrowserSettings.defaults.enabled,
            backend: BrowserBackendID(rawValue: backendRaw) ?? BrowserSettings.defaults.backend,
            runtimeMode: BrowserRuntimeMode(rawValue: runtimeModeRaw) ?? BrowserSettings.defaults.runtimeMode,
            cdpURL: defaults.string(forKey: BrowserSettingsKeys.cdpURL)
                ?? BrowserSettings.defaults.cdpURL,
            profileName: defaults.string(forKey: BrowserSettingsKeys.profileName)
                ?? BrowserSettings.defaults.profileName,
            showBrowserWindow: defaults.object(forKey: BrowserSettingsKeys.showBrowserWindow) as? Bool
                ?? BrowserSettings.defaults.showBrowserWindow,
            externalBrowserAppID: ExternalBrowserAppID(rawValue: externalBrowserRaw)
                ?? BrowserSettings.defaults.externalBrowserAppID,
            externalBrowserAppPath: defaults.string(forKey: BrowserSettingsKeys.externalBrowserAppPath)
                ?? BrowserSettings.defaults.externalBrowserAppPath,
            autoStartExternalBrowser: defaults.object(forKey: BrowserSettingsKeys.autoStartExternalBrowser) as? Bool
                ?? BrowserSettings.defaults.autoStartExternalBrowser
        )
    }

    static func save(_ settings: BrowserSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.enabled, forKey: BrowserSettingsKeys.enabled)
        defaults.set(settings.backend.rawValue, forKey: BrowserSettingsKeys.backend)
        defaults.set(settings.runtimeMode.rawValue, forKey: BrowserSettingsKeys.runtimeMode)
        defaults.set(settings.cdpURL, forKey: BrowserSettingsKeys.cdpURL)
        defaults.set(settings.profileName, forKey: BrowserSettingsKeys.profileName)
        defaults.set(settings.showBrowserWindow, forKey: BrowserSettingsKeys.showBrowserWindow)
        defaults.set(settings.externalBrowserAppID.rawValue, forKey: BrowserSettingsKeys.externalBrowserAppID)
        defaults.set(settings.externalBrowserAppPath, forKey: BrowserSettingsKeys.externalBrowserAppPath)
        defaults.set(settings.autoStartExternalBrowser, forKey: BrowserSettingsKeys.autoStartExternalBrowser)
    }

    static func loadApplied() -> BrowserSettings {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: BrowserSettingsKeys.appliedEnabled) != nil else {
            return load()
        }

        let backendRaw = defaults.string(forKey: BrowserSettingsKeys.appliedBackend)
            ?? BrowserSettings.defaults.backend.rawValue
        let runtimeModeRaw = defaults.string(forKey: BrowserSettingsKeys.appliedRuntimeMode)
            ?? BrowserSettings.defaults.runtimeMode.rawValue
        let externalBrowserRaw = defaults.string(forKey: BrowserSettingsKeys.appliedExternalBrowserAppID)
            ?? BrowserSettings.defaults.externalBrowserAppID.rawValue

        return BrowserSettings(
            enabled: defaults.object(forKey: BrowserSettingsKeys.appliedEnabled) as? Bool
                ?? BrowserSettings.defaults.enabled,
            backend: BrowserBackendID(rawValue: backendRaw) ?? BrowserSettings.defaults.backend,
            runtimeMode: BrowserRuntimeMode(rawValue: runtimeModeRaw) ?? BrowserSettings.defaults.runtimeMode,
            cdpURL: defaults.string(forKey: BrowserSettingsKeys.appliedCDPURL)
                ?? BrowserSettings.defaults.cdpURL,
            profileName: defaults.string(forKey: BrowserSettingsKeys.appliedProfileName)
                ?? BrowserSettings.defaults.profileName,
            showBrowserWindow: defaults.object(forKey: BrowserSettingsKeys.appliedShowBrowserWindow) as? Bool
                ?? BrowserSettings.defaults.showBrowserWindow,
            externalBrowserAppID: ExternalBrowserAppID(rawValue: externalBrowserRaw)
                ?? BrowserSettings.defaults.externalBrowserAppID,
            externalBrowserAppPath: defaults.string(forKey: BrowserSettingsKeys.appliedExternalBrowserAppPath)
                ?? BrowserSettings.defaults.externalBrowserAppPath,
            autoStartExternalBrowser: defaults.object(forKey: BrowserSettingsKeys.appliedAutoStartExternalBrowser) as? Bool
                ?? BrowserSettings.defaults.autoStartExternalBrowser
        )
    }

    static func saveApplied(_ settings: BrowserSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.enabled, forKey: BrowserSettingsKeys.appliedEnabled)
        defaults.set(settings.backend.rawValue, forKey: BrowserSettingsKeys.appliedBackend)
        defaults.set(settings.runtimeMode.rawValue, forKey: BrowserSettingsKeys.appliedRuntimeMode)
        defaults.set(settings.cdpURL, forKey: BrowserSettingsKeys.appliedCDPURL)
        defaults.set(settings.profileName, forKey: BrowserSettingsKeys.appliedProfileName)
        defaults.set(settings.showBrowserWindow, forKey: BrowserSettingsKeys.appliedShowBrowserWindow)
        defaults.set(settings.externalBrowserAppID.rawValue, forKey: BrowserSettingsKeys.appliedExternalBrowserAppID)
        defaults.set(settings.externalBrowserAppPath, forKey: BrowserSettingsKeys.appliedExternalBrowserAppPath)
        defaults.set(settings.autoStartExternalBrowser, forKey: BrowserSettingsKeys.appliedAutoStartExternalBrowser)
    }
}

