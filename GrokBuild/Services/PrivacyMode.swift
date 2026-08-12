import Foundation

/// Display-only redaction for screenshots / screen shares. Never mutates persisted data.
enum PrivacyMode {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: GrokSettingsKeys.privacyMode)
    }

    /// Redacts a filesystem path to `••••/<lastComponent>` when privacy mode is on.
    static func path(_ string: String) -> String {
        guard isEnabled else { return string }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let name = URL(fileURLWithPath: trimmed).lastPathComponent
        return name.isEmpty ? "••••" : "••••/\(name)"
    }

    static func path(_ url: URL) -> String {
        path(url.path)
    }

    /// Project / workspace display name.
    static func projectName(_ name: String) -> String {
        guard isEnabled else { return name }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Project" }
        return "Project"
    }

    /// Session title shown in the sidebar / dashboard.
    static func sessionTitle(_ title: String) -> String {
        guard isEnabled else { return title }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Session" }
        return "Session"
    }

    /// Pure helpers for unit tests (ignore global UserDefaults).
    static func redactPath(_ string: String, enabled: Bool) -> String {
        guard enabled else { return string }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let name = URL(fileURLWithPath: trimmed).lastPathComponent
        return name.isEmpty ? "••••" : "••••/\(name)"
    }

    static func redactLabel(_ label: String, placeholder: String, enabled: Bool) -> String {
        guard enabled else { return label }
        return placeholder
    }
}
