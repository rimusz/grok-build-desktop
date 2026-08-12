import Foundation

/// Per-session activity/attention status surfaced as a dot + unread badge on the sidebar and
/// tab strip. Pure value type so the mapping from live process signals is unit-testable without
/// spinning up a real `grok` process.
///
/// Competitive parity with grok-build-vscode's session list: parallel tabs need to answer
/// "which session needs me?" and "which finished while I was away?" at a glance.
enum SessionActivityStatus: String, Sendable, CaseIterable {
    /// No live turn; nothing waiting for the user.
    case idle
    /// A turn is in progress (streaming / grok is busy).
    case working
    /// Grok is blocked on the user: a permission prompt, plan approval, or question.
    case needsInput
    /// The last turn finished but the user has not focused this session since.
    case finishedUnread
    /// The session ended in an error / failed connection.
    case error

    /// Whether this status should draw attention (badge / colored dot) when unfocused.
    var demandsAttention: Bool {
        switch self {
        case .needsInput, .finishedUnread, .error: return true
        case .idle, .working: return false
        }
    }

    /// Short, screen-reader-friendly label for the accessibility tree and tooltips.
    var accessibilityLabel: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .needsInput: return "Needs input"
        case .finishedUnread: return "Finished, unread"
        case .error: return "Error"
        }
    }

    /// SF Symbol name used for the sidebar/tab badge.
    var symbolName: String {
        switch self {
        case .idle: return "circle"
        case .working: return "circle.dotted"
        case .needsInput: return "exclamationmark.circle.fill"
        case .finishedUnread: return "circle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

/// Inputs used to derive a `SessionActivityStatus`. Kept separate from `ChatStore` so the
/// resolution rules can be tested in isolation.
struct SessionStatusInputs: Sendable, Equatable {
    /// A turn is currently streaming.
    var isStreaming: Bool
    /// Grok is waiting on the user (permission / plan / question prompts pending).
    var isAwaitingUser: Bool
    /// The underlying process failed / connection errored.
    var hasError: Bool
    /// The session produced at least one assistant reply the user has not yet seen.
    var hasUnreadCompletion: Bool

    init(
        isStreaming: Bool = false,
        isAwaitingUser: Bool = false,
        hasError: Bool = false,
        hasUnreadCompletion: Bool = false
    ) {
        self.isStreaming = isStreaming
        self.isAwaitingUser = isAwaitingUser
        self.hasError = hasError
        self.hasUnreadCompletion = hasUnreadCompletion
    }
}

/// Pure mapping from live signals to a `SessionActivityStatus`.
///
/// Priority order (highest first): needs-input → error → working → finished-unread → idle.
/// Needs-input wins over working because a blocked turn still reports "busy" but the user
/// action is what unblocks it. Error wins over working so a failed turn does not look active.
enum SessionStatusResolver {
    static func resolve(_ inputs: SessionStatusInputs) -> SessionActivityStatus {
        if inputs.isAwaitingUser { return .needsInput }
        if inputs.hasError { return .error }
        if inputs.isStreaming { return .working }
        if inputs.hasUnreadCompletion { return .finishedUnread }
        return .idle
    }
}
