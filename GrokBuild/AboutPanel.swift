import AppKit

enum AboutPanel {
    static let repositoryURL = "https://github.com/rimusz/grok-build-desktop"

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }

    private static var options: [NSApplication.AboutPanelOptionKey: Any] {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "GrokBuild",
            .version: AppVersion.display,
            .credits: credits
        ]

        if let icon = AppIconProvider.image() {
            options[.applicationIcon] = icon
        }

        return options
    }

    private static var credits: NSAttributedString {
        let text = """
        Native SwiftUI Mac frontend for the Grok Build CLI.
        \(repositoryURL)
        """
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        )
        let urlRange = (text as NSString).range(of: repositoryURL)
        if urlRange.location != NSNotFound, let url = URL(string: repositoryURL) {
            attributed.addAttributes([
                .link: url,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: urlRange)
        }
        return attributed
    }
}
