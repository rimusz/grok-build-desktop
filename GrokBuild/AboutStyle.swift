import AppKit

/// Visual metrics aligned with the standard macOS About panel (`orderFrontStandardAboutPanel`).
enum AboutStyle {
    static let panelWidth: CGFloat = 396
    /// The About panel renders the app icon at roughly this size on screen.
    static let iconDisplaySize: CGFloat = 64

    static var appNameFont: NSFont {
        .boldSystemFont(ofSize: NSFont.systemFontSize)
    }

    static var bodyFont: NSFont {
        .systemFont(ofSize: NSFont.smallSystemFontSize)
    }

    static var versionFont: NSFont {
        .systemFont(ofSize: NSFont.smallSystemFontSize)
    }

    static var versionColor: NSColor {
        .secondaryLabelColor
    }

    static func icon() -> NSImage? {
        guard let source = AppIconProvider.image() else { return nil }
        let side = iconDisplaySize
        let size = NSSize(width: side, height: side)
        let scaled = NSImage(size: size)
        scaled.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: size))
        scaled.unlockFocus()
        return scaled
    }
}
