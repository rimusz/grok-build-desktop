import AppKit

enum AppIconProvider {
    static func image() -> NSImage? {
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            for name in ["AppIcon.png", "AppIcon.icns"] {
                let path = execDir.appendingPathComponent(name).path
                if FileManager.default.fileExists(atPath: path),
                   let image = NSImage(contentsOfFile: path) {
                    return sized(image)
                }
            }
        }

        if let image = NSImage(named: "AppIcon") {
            return sized(image)
        }

        for name in ["AppIcon", "AppIcon1024"] {
            if let path = Bundle.main.path(forResource: name, ofType: "png"),
               let image = NSImage(contentsOfFile: path) {
                return sized(image)
            }
            if let path = Bundle.main.path(forResource: name, ofType: "icns"),
               let image = NSImage(contentsOfFile: path) {
                return sized(image)
            }
        }

        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<3 {
            let candidate = directory.appendingPathComponent("AppIcon.png")
            if let image = NSImage(contentsOfFile: candidate.path) {
                return sized(image)
            }
            directory.deleteLastPathComponent()
        }

        if let image = NSApp.applicationIconImage, image.isValid {
            return sized(image)
        }

        return nil
    }

    private static func sized(_ image: NSImage) -> NSImage {
        image.size = NSSize(width: 128, height: 128)
        return image
    }
}
