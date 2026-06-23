import AppKit

enum AboutPanel {
    static let repositoryURL = "https://github.com/rimusz/grok-build-desktop"

    private static let appName = "GrokBuild"
    @MainActor private static var panel: NSPanel?

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        Task {
            let cliVersionLine = await GrokCLIService.versionDisplayLine()
            await MainActor.run {
                present(cliVersionLine: cliVersionLine)
            }
        }
    }

    @MainActor
    private static func present(cliVersionLine: String) {
        let panelWidth = AboutStyle.panelWidth
        let rootView = makeRootView(cliVersionLine: cliVersionLine, panelWidth: panelWidth)
        rootView.layoutSubtreeIfNeeded()
        let size = NSSize(width: panelWidth, height: rootView.fittingSize.height)

        if let panel {
            panel.contentView = rootView
            panel.setContentSize(size)
            configureWindow(panel)
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = rootView
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        configureWindow(window)
        window.center()
        window.makeKeyAndOrderFront(nil)
        panel = window
    }

    private static func configureWindow(_ window: NSWindow) {
        window.title = ""
        window.titleVisibility = .hidden
        window.appearance = NSApp.appearance
    }

    private static func makeRootView(cliVersionLine: String, panelWidth: CGFloat) -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .underPageBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.image = AboutStyle.icon()
        iconView.imageScaling = .scaleNone
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = centeredLabel(appName, font: AboutStyle.appNameFont)
        let versionLabel = centeredLabel(
            "Version \(AppVersion.display)",
            font: AboutStyle.versionFont,
            color: AboutStyle.versionColor
        )
        let cliLabel = centeredLabel(
            cliVersionLine,
            font: AboutStyle.versionFont,
            color: AboutStyle.versionColor
        )

        let descriptionLabel = NSTextField(wrappingLabelWithString: "Native SwiftUI Mac frontend for the Grok Build CLI.")
        descriptionLabel.font = AboutStyle.bodyFont
        descriptionLabel.textColor = .labelColor
        descriptionLabel.alignment = .center
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.preferredMaxLayoutWidth = panelWidth - 40
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        let linkLabel = NSTextField(labelWithString: "")
        linkLabel.isSelectable = true
        linkLabel.isEditable = false
        linkLabel.drawsBackground = false
        linkLabel.isBezeled = false
        linkLabel.alignment = .center
        linkLabel.translatesAutoresizingMaskIntoConstraints = false
        linkLabel.attributedStringValue = linkAttributedString()

        effect.addSubview(container)
        container.addSubview(iconView)
        container.addSubview(nameLabel)
        container.addSubview(versionLabel)
        container.addSubview(cliLabel)
        container.addSubview(descriptionLabel)
        container.addSubview(linkLabel)

        NSLayoutConstraint.activate([
            effect.widthAnchor.constraint(equalToConstant: panelWidth),

            container.topAnchor.constraint(equalTo: effect.topAnchor),
            container.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: effect.bottomAnchor),

            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: AboutStyle.iconDisplaySize),
            iconView.heightAnchor.constraint(equalToConstant: AboutStyle.iconDisplaySize),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            nameLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            nameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            versionLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            versionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            versionLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),

            cliLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 2),
            cliLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            cliLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            cliLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),

            descriptionLabel.topAnchor.constraint(equalTo: cliLabel.bottomAnchor, constant: 12),
            descriptionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            descriptionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            linkLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 8),
            linkLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            linkLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            linkLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            linkLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])

        container.layoutSubtreeIfNeeded()
        effect.heightAnchor.constraint(equalToConstant: container.fittingSize.height).isActive = true
        return effect
    }

    private static func centeredLabel(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static func linkAttributedString() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        return NSAttributedString(
            string: repositoryURL,
            attributes: [
                .font: AboutStyle.bodyFont,
                .link: URL(string: repositoryURL)!,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }
}
