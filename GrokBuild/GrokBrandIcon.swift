import AppKit

enum GrokBrandIcon {
    /// Grok mark used in the menu bar and empty chat welcome state.
    static func mark() -> NSImage? {
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            for name in ["MenuBarIcon@2x.png", "MenuBarIcon.png", "MenuBarIcon@3x.png"] {
                let path = execDir.appendingPathComponent(name).path
                if FileManager.default.fileExists(atPath: path),
                   let image = NSImage(contentsOfFile: path) {
                    return image
                }
            }
        }

        for name in ["MenuBarIcon@2x.png", "MenuBarIcon.png"] {
            if FileManager.default.fileExists(atPath: name),
               let image = NSImage(contentsOfFile: name) {
                return image
            }
        }

        if let image = NSImage(named: "MenuBarIcon") {
            return image
        }

        for name in ["MenuBarIcon@2x", "MenuBarIcon", "MenuBarIcon@3x"] {
            if let path = Bundle.main.path(forResource: name, ofType: "png"),
               let image = NSImage(contentsOfFile: path) {
                return image
            }
        }

        return nil
    }
}
