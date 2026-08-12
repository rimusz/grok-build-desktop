import Foundation
import AppKit

/// Optional chime when a turn finishes and the app window is not focused, so users running
/// parallel sessions notice a completed reply. Off by default; toggled in Settings → App.
///
/// The decision (`shouldPlay`) is pure for testing; playback reads live app-active state.
enum TurnCompletionSound {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: GrokSettingsKeys.soundOnUnfocusedFinish)
    }

    /// Pure rule: play only when enabled and the app is not the active/frontmost app.
    static func shouldPlay(enabled: Bool, appActive: Bool) -> Bool {
        enabled && !appActive
    }

    /// Plays the completion sound when the setting is on and the app is unfocused.
    @MainActor
    static func playIfNeeded() {
        guard shouldPlay(enabled: isEnabled, appActive: NSApp.isActive) else { return }
        NSSound(named: "Glass")?.play()
    }
}
