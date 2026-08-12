import Foundation

/// A single diagnostic line in the Doctor sheet / onboarding wizard.
///
/// Pure value type so the environment probing (CLI present? authed? config.toml? bridge up?) can
/// be assembled and unit-tested without touching the live UI. Inspired by Grok-UI's `doctor`
/// panel, adapted to GrokBuild's native shell.
struct DoctorCheck: Identifiable, Hashable, Sendable {
    enum Status: String, Sendable {
        case ok
        case warning
        case failed
        case info

        var symbolName: String {
            switch self {
            case .ok: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .failed: return "xmark.octagon.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    /// Stable identifier for the row (also used to look up remediation).
    var key: String
    /// Short title (e.g. "grok CLI").
    var title: String
    /// One-line detail. Avoid leaking machine-specific absolute paths in user-facing copy.
    var detail: String
    var status: Status

    var id: String { key }
}

/// Raw inputs collected by the app before mapping to `DoctorCheck` rows. Separating collection
/// (impure) from mapping (pure) keeps the mapping testable.
struct DoctorInputs: Sendable, Equatable {
    /// Whether a `grok` binary was located on disk / PATH.
    var cliFound: Bool
    /// Short version string (e.g. `0.2.93 [stable]`), empty when unknown.
    var versionDisplay: String
    /// Whether the grok CLI has cached credentials (`~/.grok/auth.json`).
    var authenticated: Bool
    /// Whether `~/.grok/config.toml` exists.
    var configPresent: Bool
    /// Whether browser tools are enabled in settings.
    var browserEnabled: Bool
    /// Whether computer use is enabled in settings.
    var computerUseEnabled: Bool
    /// Number of reachable Cursor bridge endpoints (nil = not probed).
    var reachableBridgeCount: Int?
    /// Whether a Node.js binary was found (needed for the managed Cursor bridge).
    var nodeFound: Bool
    /// Raw `node --version` text when available.
    var nodeVersionDisplay: String
    /// Whether the located Node meets the Cursor bridge minimum (≥ 22.13).
    var nodeMeetsMinimum: Bool

    init(
        cliFound: Bool = false,
        versionDisplay: String = "",
        authenticated: Bool = false,
        configPresent: Bool = false,
        browserEnabled: Bool = false,
        computerUseEnabled: Bool = false,
        reachableBridgeCount: Int? = nil,
        nodeFound: Bool = false,
        nodeVersionDisplay: String = "",
        nodeMeetsMinimum: Bool = false
    ) {
        self.cliFound = cliFound
        self.versionDisplay = versionDisplay
        self.authenticated = authenticated
        self.configPresent = configPresent
        self.browserEnabled = browserEnabled
        self.computerUseEnabled = computerUseEnabled
        self.reachableBridgeCount = reachableBridgeCount
        self.nodeFound = nodeFound
        self.nodeVersionDisplay = nodeVersionDisplay
        self.nodeMeetsMinimum = nodeMeetsMinimum
    }
}

/// Pure mapping from `DoctorInputs` to an ordered list of `DoctorCheck` rows.
enum DoctorReport {
    static func checks(from inputs: DoctorInputs) -> [DoctorCheck] {
        var rows: [DoctorCheck] = []

        rows.append(DoctorCheck(
            key: "cli",
            title: "grok CLI",
            detail: inputs.cliFound ? "Found on your system." : "Not found — install the grok CLI to use GrokBuild.",
            status: inputs.cliFound ? .ok : .failed
        ))

        rows.append(DoctorCheck(
            key: "version",
            title: "CLI version",
            detail: inputs.versionDisplay.isEmpty ? "Version unavailable." : inputs.versionDisplay,
            status: inputs.cliFound ? (inputs.versionDisplay.isEmpty ? .warning : .ok) : .info
        ))

        rows.append(DoctorCheck(
            key: "auth",
            title: "Authentication",
            detail: inputs.authenticated ? "Signed in." : "Signed out — run grok login to authenticate.",
            status: inputs.authenticated ? .ok : (inputs.cliFound ? .warning : .info)
        ))

        rows.append(DoctorCheck(
            key: "config",
            title: "config.toml",
            detail: inputs.configPresent ? "Present in your grok config directory." : "Not created yet — it appears after first use.",
            status: inputs.configPresent ? .ok : .info
        ))

        rows.append(DoctorCheck(
            key: "browser",
            title: "Browser tools",
            detail: inputs.browserEnabled ? "Enabled." : "Disabled.",
            status: .info
        ))

        rows.append(DoctorCheck(
            key: "computerUse",
            title: "Computer Use",
            detail: inputs.computerUseEnabled ? "Enabled." : "Disabled.",
            status: .info
        ))

        rows.append(DoctorCheck(
            key: "node",
            title: "Node.js",
            detail: CursorBridge.NodeRequirement.detail(
                found: inputs.nodeFound,
                versionDisplay: inputs.nodeVersionDisplay,
                meetsMinimum: inputs.nodeMeetsMinimum
            ),
            status: inputs.nodeMeetsMinimum ? .ok : .warning
        ))

        if let count = inputs.reachableBridgeCount {
            rows.append(DoctorCheck(
                key: "cursorBridge",
                title: "Cursor bridge",
                detail: count > 0 ? "Managed bridge reachable on 127.0.0.1:18787." : "Managed bridge not reachable.",
                status: count > 0 ? .ok : .info
            ))
        }

        return rows
    }

    /// True when nothing is blocking a working session (CLI present + authenticated).
    static func isHealthy(_ inputs: DoctorInputs) -> Bool {
        inputs.cliFound && inputs.authenticated
    }

    /// The most urgent remediation headline, or nil when healthy.
    static func primaryRemediation(_ inputs: DoctorInputs) -> String? {
        if !inputs.cliFound { return "Install the grok CLI" }
        if !inputs.authenticated { return "Run grok login" }
        return nil
    }
}
