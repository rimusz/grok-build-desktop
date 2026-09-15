import Foundation

/// Whether the transcript should follow new content or stay put with a jump control.
///
/// Dock-style chat: stay pinned to the latest turn while the user is at the bottom;
/// if they scroll up, streaming must not yank the viewport. Pure so tests do not
/// need a live `ScrollView`.
enum TranscriptScrollPolicy: Sendable {
    /// Distance from the content bottom (points) still treated as "at latest".
    static let pinThreshold: CGFloat = 64

    static func isPinnedToBottom(contentHeight: CGFloat, visibleMaxY: CGFloat) -> Bool {
        contentHeight - visibleMaxY < pinThreshold
    }

    static func shouldFollowLatest(isPinnedToBottom: Bool) -> Bool {
        isPinnedToBottom
    }

    static func shouldShowJumpToLatest(isPinnedToBottom: Bool, hasTranscript: Bool) -> Bool {
        hasTranscript && !isPinnedToBottom
    }
}
