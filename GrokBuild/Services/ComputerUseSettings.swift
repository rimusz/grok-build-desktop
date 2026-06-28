import Foundation

enum ComputerUseBackendID: String, CaseIterable, Identifiable {
    case agentDesktop = "agent-desktop"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .agentDesktop: return "agent-desktop"
        }
    }
}

enum ComputerUsePermissionPolicy: String, CaseIterable, Identifiable {
    case auto
    case ask
    case deny

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .ask: return "Ask"
        case .deny: return "Deny"
        }
    }
}

enum ComputerUseScreenshotMode: String, CaseIterable, Identifiable {
    case accessibilityFirst = "accessibility-first"
    case screenshotsAllowed = "screenshots-allowed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .accessibilityFirst: return "Accessibility First"
        case .screenshotsAllowed: return "Screenshots Allowed"
        }
    }
}

struct ComputerUseSettings: Sendable, Equatable {
    var enabled: Bool
    var backend: ComputerUseBackendID
    var agentDesktopPath: String
    var permissionPolicy: ComputerUsePermissionPolicy
    var maxSteps: Int
    var commandTimeoutSeconds: Int
    var screenshotMode: ComputerUseScreenshotMode
    var includeScreenshots: Bool
    var allowPhysicalMouse: Bool
    var sessionName: String

    init(
        enabled: Bool,
        backend: ComputerUseBackendID,
        agentDesktopPath: String,
        permissionPolicy: ComputerUsePermissionPolicy,
        maxSteps: Int,
        commandTimeoutSeconds: Int,
        screenshotMode: ComputerUseScreenshotMode,
        includeScreenshots: Bool,
        allowPhysicalMouse: Bool,
        sessionName: String
    ) {
        self.enabled = enabled
        self.backend = backend
        self.agentDesktopPath = agentDesktopPath
        self.permissionPolicy = permissionPolicy
        self.maxSteps = maxSteps
        self.commandTimeoutSeconds = commandTimeoutSeconds
        self.screenshotMode = screenshotMode
        self.includeScreenshots = includeScreenshots
        self.allowPhysicalMouse = allowPhysicalMouse
        self.sessionName = sessionName
    }

    static let defaults = ComputerUseSettings(
        enabled: false,
        backend: .agentDesktop,
        agentDesktopPath: "",
        permissionPolicy: .ask,
        maxSteps: 24,
        commandTimeoutSeconds: 60,
        screenshotMode: .accessibilityFirst,
        includeScreenshots: false,
        allowPhysicalMouse: false,
        sessionName: "grokbuild"
    )
}

enum ComputerUseSettingsKeys {
    static let enabled = "grokbuild.computerUse.enabled"
    static let backend = "grokbuild.computerUse.backend"
    static let agentDesktopPath = "grokbuild.computerUse.agentDesktopPath"
    static let permissionPolicy = "grokbuild.computerUse.permissionPolicy"
    static let maxSteps = "grokbuild.computerUse.maxSteps"
    static let commandTimeoutSeconds = "grokbuild.computerUse.commandTimeoutSeconds"
    static let screenshotMode = "grokbuild.computerUse.screenshotMode"
    static let includeScreenshots = "grokbuild.computerUse.includeScreenshots"
    static let allowPhysicalMouse = "grokbuild.computerUse.allowPhysicalMouse"
    static let sessionName = "grokbuild.computerUse.sessionName"
    static let cursorIntegrationEnabled = "grokbuild.computerUse.cursorIntegration.enabled"

    static let appliedEnabled = "grokbuild.computerUse.applied.enabled"
    static let appliedBackend = "grokbuild.computerUse.applied.backend"
    static let appliedAgentDesktopPath = "grokbuild.computerUse.applied.agentDesktopPath"
    static let appliedPermissionPolicy = "grokbuild.computerUse.applied.permissionPolicy"
    static let appliedMaxSteps = "grokbuild.computerUse.applied.maxSteps"
    static let appliedCommandTimeoutSeconds = "grokbuild.computerUse.applied.commandTimeoutSeconds"
    static let appliedScreenshotMode = "grokbuild.computerUse.applied.screenshotMode"
    static let appliedIncludeScreenshots = "grokbuild.computerUse.applied.includeScreenshots"
    static let appliedAllowPhysicalMouse = "grokbuild.computerUse.applied.allowPhysicalMouse"
    static let appliedSessionName = "grokbuild.computerUse.applied.sessionName"
    static let appliedCursorIntegrationEnabled = "grokbuild.computerUse.applied.cursorIntegration.enabled"
}

enum ComputerUseSettingsStore {
    static func load() -> ComputerUseSettings {
        load(prefix: .current)
    }

    static func save(_ settings: ComputerUseSettings) {
        save(settings, prefix: .current)
    }

    static func loadApplied() -> ComputerUseSettings {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: ComputerUseSettingsKeys.appliedEnabled) != nil else {
            return load()
        }
        return load(prefix: .applied)
    }

    static func saveApplied(_ settings: ComputerUseSettings) {
        save(settings, prefix: .applied)
    }

    /// Persists Cursor MCP environment fields without requiring a full Apply + Grok restart.
    static func saveAppliedCursorEnvironment(from settings: ComputerUseSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.permissionPolicy.rawValue, forKey: ComputerUseSettingsKeys.appliedPermissionPolicy)
        defaults.set(settings.maxSteps, forKey: ComputerUseSettingsKeys.appliedMaxSteps)
        defaults.set(settings.commandTimeoutSeconds, forKey: ComputerUseSettingsKeys.appliedCommandTimeoutSeconds)
        defaults.set(settings.includeScreenshots, forKey: ComputerUseSettingsKeys.appliedIncludeScreenshots)
        defaults.set(settings.allowPhysicalMouse, forKey: ComputerUseSettingsKeys.appliedAllowPhysicalMouse)
        defaults.set(settings.sessionName, forKey: ComputerUseSettingsKeys.appliedSessionName)
    }

    private enum KeyPrefix {
        case current
        case applied
    }

    private static func load(prefix: KeyPrefix) -> ComputerUseSettings {
        let defaults = UserDefaults.standard
        let backendRaw = defaults.string(forKey: key(.backend, prefix: prefix))
            ?? ComputerUseSettings.defaults.backend.rawValue
        let policyRaw = defaults.string(forKey: key(.permissionPolicy, prefix: prefix))
            ?? ComputerUseSettings.defaults.permissionPolicy.rawValue
        let screenshotModeRaw = defaults.string(forKey: key(.screenshotMode, prefix: prefix))
            ?? ComputerUseSettings.defaults.screenshotMode.rawValue

        return ComputerUseSettings(
            enabled: defaults.object(forKey: key(.enabled, prefix: prefix)) as? Bool
                ?? ComputerUseSettings.defaults.enabled,
            backend: ComputerUseBackendID(rawValue: backendRaw) ?? ComputerUseSettings.defaults.backend,
            agentDesktopPath: defaults.string(forKey: key(.agentDesktopPath, prefix: prefix))
                ?? ComputerUseSettings.defaults.agentDesktopPath,
            permissionPolicy: ComputerUsePermissionPolicy(rawValue: policyRaw)
                ?? ComputerUseSettings.defaults.permissionPolicy,
            maxSteps: defaults.object(forKey: key(.maxSteps, prefix: prefix)) as? Int
                ?? ComputerUseSettings.defaults.maxSteps,
            commandTimeoutSeconds: defaults.object(forKey: key(.commandTimeoutSeconds, prefix: prefix)) as? Int
                ?? ComputerUseSettings.defaults.commandTimeoutSeconds,
            screenshotMode: ComputerUseScreenshotMode(rawValue: screenshotModeRaw)
                ?? ComputerUseSettings.defaults.screenshotMode,
            includeScreenshots: defaults.object(forKey: key(.includeScreenshots, prefix: prefix)) as? Bool
                ?? ComputerUseSettings.defaults.includeScreenshots,
            allowPhysicalMouse: defaults.object(forKey: key(.allowPhysicalMouse, prefix: prefix)) as? Bool
                ?? ComputerUseSettings.defaults.allowPhysicalMouse,
            sessionName: defaults.string(forKey: key(.sessionName, prefix: prefix))
                ?? ComputerUseSettings.defaults.sessionName
        )
    }

    private static func save(_ settings: ComputerUseSettings, prefix: KeyPrefix) {
        let defaults = UserDefaults.standard
        defaults.set(settings.enabled, forKey: key(.enabled, prefix: prefix))
        defaults.set(settings.backend.rawValue, forKey: key(.backend, prefix: prefix))
        defaults.set(settings.agentDesktopPath, forKey: key(.agentDesktopPath, prefix: prefix))
        defaults.set(settings.permissionPolicy.rawValue, forKey: key(.permissionPolicy, prefix: prefix))
        defaults.set(settings.maxSteps, forKey: key(.maxSteps, prefix: prefix))
        defaults.set(settings.commandTimeoutSeconds, forKey: key(.commandTimeoutSeconds, prefix: prefix))
        defaults.set(settings.screenshotMode.rawValue, forKey: key(.screenshotMode, prefix: prefix))
        defaults.set(settings.includeScreenshots, forKey: key(.includeScreenshots, prefix: prefix))
        defaults.set(settings.allowPhysicalMouse, forKey: key(.allowPhysicalMouse, prefix: prefix))
        defaults.set(settings.sessionName, forKey: key(.sessionName, prefix: prefix))
    }

    private enum KeyKind {
        case enabled
        case backend
        case agentDesktopPath
        case permissionPolicy
        case maxSteps
        case commandTimeoutSeconds
        case screenshotMode
        case includeScreenshots
        case allowPhysicalMouse
        case sessionName
    }

    private static func key(_ kind: KeyKind, prefix: KeyPrefix) -> String {
        switch (kind, prefix) {
        case (.enabled, .current): return ComputerUseSettingsKeys.enabled
        case (.backend, .current): return ComputerUseSettingsKeys.backend
        case (.agentDesktopPath, .current): return ComputerUseSettingsKeys.agentDesktopPath
        case (.permissionPolicy, .current): return ComputerUseSettingsKeys.permissionPolicy
        case (.maxSteps, .current): return ComputerUseSettingsKeys.maxSteps
        case (.commandTimeoutSeconds, .current): return ComputerUseSettingsKeys.commandTimeoutSeconds
        case (.screenshotMode, .current): return ComputerUseSettingsKeys.screenshotMode
        case (.includeScreenshots, .current): return ComputerUseSettingsKeys.includeScreenshots
        case (.allowPhysicalMouse, .current): return ComputerUseSettingsKeys.allowPhysicalMouse
        case (.sessionName, .current): return ComputerUseSettingsKeys.sessionName
        case (.enabled, .applied): return ComputerUseSettingsKeys.appliedEnabled
        case (.backend, .applied): return ComputerUseSettingsKeys.appliedBackend
        case (.agentDesktopPath, .applied): return ComputerUseSettingsKeys.appliedAgentDesktopPath
        case (.permissionPolicy, .applied): return ComputerUseSettingsKeys.appliedPermissionPolicy
        case (.maxSteps, .applied): return ComputerUseSettingsKeys.appliedMaxSteps
        case (.commandTimeoutSeconds, .applied): return ComputerUseSettingsKeys.appliedCommandTimeoutSeconds
        case (.screenshotMode, .applied): return ComputerUseSettingsKeys.appliedScreenshotMode
        case (.includeScreenshots, .applied): return ComputerUseSettingsKeys.appliedIncludeScreenshots
        case (.allowPhysicalMouse, .applied): return ComputerUseSettingsKeys.appliedAllowPhysicalMouse
        case (.sessionName, .applied): return ComputerUseSettingsKeys.appliedSessionName
        }
    }
}
