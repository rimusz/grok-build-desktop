import AppKit
import Foundation
@preconcurrency import UserNotifications

/// Local Notification Center banner when a turn finishes, or when grok starts waiting
/// on the user, and GrokBuild is not the frontmost app. Off by default (Settings → App).
///
/// Copy rules are pure. Delivery checks authorization and stays quiet if the user denied it.
enum TurnBackgroundNotice {
    static let sessionIDUserInfoKey = "sessionID"

    enum Kind: String, Sendable {
        case replyReady
        case needsInput
    }

    struct Copy: Equatable, Sendable {
        var title: String
        var body: String
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: GrokSettingsKeys.notifyOnUnfocusedFinish)
    }

    /// Same gate as the completion chime: enabled, and the app is not frontmost.
    static func shouldNotify(enabled: Bool, appActive: Bool) -> Bool {
        enabled && !appActive
    }

    static func title(sessionTitle: String, projectName: String, privacyEnabled: Bool) -> String {
        let session = PrivacyMode.redactLabel(sessionTitle, placeholder: "Session", enabled: privacyEnabled)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let project = PrivacyMode.redactLabel(projectName, placeholder: "Project", enabled: privacyEnabled)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let shownSession = session.isEmpty ? "Session" : session
        if project.isEmpty { return shownSession }
        return "\(shownSession) · \(project)"
    }

    /// First line of the reply, or "Reply ready" when there is nothing safe to preview.
    static func replyBody(_ preview: String, limit: Int = 140) -> String {
        let collapsed = preview
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.isEmpty { return "Reply ready" }
        guard collapsed.count > limit, limit > 1 else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: limit - 1)
        return String(collapsed[..<end]) + "…"
    }

    static func copy(
        kind: Kind,
        sessionTitle: String,
        projectName: String,
        replyPreview: String,
        privacyEnabled: Bool
    ) -> Copy {
        Copy(
            title: title(sessionTitle: sessionTitle, projectName: projectName, privacyEnabled: privacyEnabled),
            body: kind == .needsInput ? "Needs input" : replyBody(replyPreview)
        )
    }

    /// Asks once. Later denials are left alone.
    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    @MainActor
    static func postIfNeeded(
        kind: Kind,
        sessionID: UUID?,
        sessionTitle: String,
        projectName: String,
        replyPreview: String
    ) {
        guard shouldNotify(enabled: isEnabled, appActive: NSApp.isActive) else { return }
        guard let sessionID else { return }
        let rendered = copy(
            kind: kind,
            sessionTitle: sessionTitle,
            projectName: projectName,
            replyPreview: replyPreview,
            privacyEnabled: PrivacyMode.isEnabled
        )
        let content = UNMutableNotificationContent()
        content.title = rendered.title
        content.body = rendered.body
        content.userInfo = [sessionIDUserInfoKey: sessionID.uuidString]
        let request = UNNotificationRequest(
            identifier: "\(sessionID.uuidString).\(kind.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                UNUserNotificationCenter.current().add(request)
            default:
                break
            }
        }
    }
}
