import CoreGraphics

/// Shared main-window size policy for SwiftUI `WindowGroup` and AppKit reopen path.
enum MainWindowLayout {
    /// Comfortable floor so sidebar + composer + status pills stay readable.
    static let minimumSize = CGSize(width: 1100, height: 720)
    static let defaultSize = CGSize(width: 1200, height: 800)

    /// Composer fills the chat column (no artificial mid-width cap).
    static let composerMaxWidth: CGFloat = .infinity
}
