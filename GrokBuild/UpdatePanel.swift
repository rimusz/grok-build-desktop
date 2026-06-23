import AppKit

@MainActor
enum UpdatePanel {
    private static let appName = "GrokBuild"
    private static var panel: NSPanel?
    private static var panelDelegate: PanelDelegate?
    private static var retainedAction: OpenReleaseAction?

    static func show(
        app: Result<UpdateChecker.AppRelease, Error>,
        cli: UpdateChecker.GrokCLIStatus,
        onDismiss: @escaping () -> Void
    ) {
        NSApp.activate(ignoringOtherApps: true)

        let content = makePresentation(app: app, cli: cli)
        let panelWidth = computedPanelWidth(for: content)
        let rootView = makeRootView(content: content, panelWidth: panelWidth)
        rootView.layoutSubtreeIfNeeded()
        let size = NSSize(width: panelWidth, height: rootView.fittingSize.height)

        if let panel {
            panel.contentView = rootView
            panel.setContentSize(size)
            configureWindow(panel)
            let delegate = PanelDelegate(onClose: onDismiss)
            panel.delegate = delegate
            panelDelegate = delegate
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
        window.title = ""
        window.contentView = rootView
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        configureWindow(window)

        let delegate = PanelDelegate {
            onDismiss()
        }
        window.delegate = delegate
        panelDelegate = delegate

        window.center()
        window.makeKeyAndOrderFront(nil)
        panel = window
    }

    private struct Presentation {
        let statusLine: String
        let body: String
        let appUpdateAvailable: Bool
        let appReleaseURL: URL?
    }

    private static func makePresentation(
        app: Result<UpdateChecker.AppRelease, Error>,
        cli: UpdateChecker.GrokCLIStatus
    ) -> Presentation {
        var appSection: String?
        var appReleaseURL: URL?
        var appUpdateAvailable = false
        var anyUpdateAvailable = cli.updateAvailable

        switch app {
        case .success(let release):
            appReleaseURL = release.releaseURL
            appUpdateAvailable = release.updateAvailable
            anyUpdateAvailable = anyUpdateAvailable || release.updateAvailable

            appSection = [
                "GrokBuild",
                "Installed: \(release.installedVersion)",
                "Latest: \(release.latestVersion)",
            ].joined(separator: "\n")
        case .failure(let error):
            appSection = "GrokBuild\nCould not check for updates: \(error.localizedDescription)"
        }

        if cli.updateAvailable {
            anyUpdateAvailable = true
        }

        let statusLine: String
        if anyUpdateAvailable {
            statusLine = "Updates Available"
        } else if case .failure = app, case .checkFailed = cli.state {
            statusLine = "Could Not Check for Updates"
        } else {
            statusLine = "Everything Is Up to Date"
        }

        let sections = [grokCLISection(for: cli.state), appSection]
            .compactMap { $0 }
            .joined(separator: "\n\n")

        let body = [statusLine, sections].joined(separator: "\n\n")

        return Presentation(
            statusLine: statusLine,
            body: body,
            appUpdateAvailable: appUpdateAvailable,
            appReleaseURL: appReleaseURL
        )
    }

    private static func computedPanelWidth(for content: Presentation) -> CGFloat {
        let horizontalPadding: CGFloat = 72
        let minimumWidth: CGFloat = 300
        return max(minimumWidth, ceil(measuredContentWidth(for: content) + horizontalPadding))
    }

    private static func configureWindow(_ window: NSWindow) {
        window.title = ""
        window.titleVisibility = .hidden
        window.appearance = NSApp.appearance
    }

    private static func measuredContentWidth(for content: Presentation) -> CGFloat {
        var maxWidth = AboutStyle.iconDisplaySize
        maxWidth = max(maxWidth, textWidth(appName, font: AboutStyle.appNameFont))

        for line in content.body.components(separatedBy: "\n") {
            maxWidth = max(maxWidth, textWidth(line, font: AboutStyle.bodyFont))
        }

        if content.appUpdateAvailable {
            let buttonFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            maxWidth = max(maxWidth, textWidth("Open Release", font: buttonFont) + 28)
        }

        return maxWidth
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func makeRootView(content: Presentation, panelWidth: CGFloat) -> NSView {
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

        let bodyLabel = NSTextField(wrappingLabelWithString: content.body)
        bodyLabel.font = AboutStyle.bodyFont
        bodyLabel.textColor = .labelColor
        bodyLabel.alignment = .center
        bodyLabel.isSelectable = true
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.preferredMaxLayoutWidth = panelWidth - 40
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(container)
        container.addSubview(iconView)
        container.addSubview(nameLabel)
        container.addSubview(bodyLabel)

        var constraints = [
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

            bodyLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 12),
            bodyLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            bodyLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
        ]

        if content.appUpdateAvailable, let releaseURL = content.appReleaseURL {
            let action = OpenReleaseAction(url: releaseURL)
            retainedAction = action

            let openButton = NSButton(title: "Open Release", target: action, action: #selector(OpenReleaseAction.open(_:)))
            openButton.bezelStyle = .push
            openButton.bezelColor = .controlAccentColor
            openButton.contentTintColor = .white
            openButton.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(openButton)

            constraints += [
                bodyLabel.bottomAnchor.constraint(equalTo: openButton.topAnchor, constant: -16),
                openButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                openButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            ]
        } else {
            constraints += [
                bodyLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            ]
        }

        NSLayoutConstraint.activate(constraints)
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

    private static func grokCLISection(for state: UpdateChecker.GrokCLIStatus.State) -> String {
        switch state {
        case .upToDate(let current, let latest, let channel):
            var lines = [
                "grok CLI",
                "Installed: \(current)",
                "Latest: \(latest)",
            ]
            if let channel, !channel.isEmpty {
                lines.append("Channel: \(channel)")
            }
            return lines.joined(separator: "\n")
        case .updateAvailable(let current, let latest, let channel):
            var lines = [
                "grok CLI",
                "Installed: \(current)",
                "Latest: \(latest)",
            ]
            if let channel, !channel.isEmpty {
                lines.append("Channel: \(channel)")
            }
            lines.append("")
            lines.append("To update, run in Terminal:")
            lines.append("  grok update")
            return lines.joined(separator: "\n")
        case .notInstalled:
            return """
            grok CLI
            Not installed.

            Install the grok CLI, then run:
              grok login
            """
        case .checkFailed(let message):
            return """
            grok CLI
            Could not check for updates: \(message)
            """
        }
    }
}

private final class PanelDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private final class OpenReleaseAction: NSObject {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    @objc func open(_ sender: Any?) {
        NSWorkspace.shared.open(url)
    }
}
