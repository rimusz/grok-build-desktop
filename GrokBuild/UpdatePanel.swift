import AppKit

@MainActor
enum UpdatePanel {
    private static let appName = "GrokBuild"
    private static let skipAppVersionTitle = "Skip GrokBuild Version"
    private static let skipCLIVersionTitle = "Skip grok CLI Version"
    private static var panel: NSPanel?
    private static var panelDelegate: PanelDelegate?
    private static var host: UpdatePanelHost?

    static func show(
        app: Result<UpdateChecker.AppRelease, Error>,
        cli: UpdateChecker.GrokCLIStatus,
        onDismiss: @escaping () -> Void
    ) {
        NSApp.activate(ignoringOtherApps: true)

        let panelHost = UpdatePanelHost(app: app, cli: cli, onDismiss: onDismiss)
        host = panelHost

        let content = panelHost.presentation
        let panelWidth = computedPanelWidth(for: content)
        let rootView = panelHost.makeRootView(panelWidth: panelWidth)
        rootView.layoutSubtreeIfNeeded()
        let size = NSSize(width: panelWidth, height: rootView.fittingSize.height)

        if let panel {
            panel.contentView = rootView
            panel.setContentSize(size)
            configureWindow(panel)
            let delegate = PanelDelegate(onClose: cleanupAndDismiss(onDismiss: onDismiss))
            panel.delegate = delegate
            panelDelegate = delegate
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            panelHost.attach(panel: panel)
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

        let delegate = PanelDelegate(onClose: cleanupAndDismiss(onDismiss: onDismiss))
        window.delegate = delegate
        panelDelegate = delegate

        window.center()
        window.makeKeyAndOrderFront(nil)
        panel = window
        panelHost.attach(panel: window)
    }

    static func refreshIfVisible() {
        guard let panel, let host else { return }
        let content = host.presentation
        let panelWidth = computedPanelWidth(for: content)
        let rootView = host.makeRootView(panelWidth: panelWidth)
        rootView.layoutSubtreeIfNeeded()
        panel.contentView = rootView
        panel.setContentSize(NSSize(width: panelWidth, height: rootView.fittingSize.height))
    }

    private static func cleanupAndDismiss(onDismiss: @escaping () -> Void) -> () -> Void {
        {
            UpdatePanel.host = nil
            UpdatePanel.panelDelegate = nil
            onDismiss()
        }
    }

    private static func computedPanelWidth(for content: UpdatePanelHost.Presentation) -> CGFloat {
        let horizontalPadding: CGFloat = 72
        let minimumWidth: CGFloat = 320
        return max(minimumWidth, ceil(measuredContentWidth(for: content) + horizontalPadding))
    }

    private static func configureWindow(_ window: NSWindow) {
        window.title = ""
        window.titleVisibility = .hidden
        window.appearance = NSApp.appearance
    }

    private static func measuredContentWidth(for content: UpdatePanelHost.Presentation) -> CGFloat {
        var maxWidth = AboutStyle.iconDisplaySize
        maxWidth = max(maxWidth, textWidth(appName, font: AboutStyle.appNameFont))

        for line in content.body.components(separatedBy: "\n") {
            maxWidth = max(maxWidth, textWidth(line, font: AboutStyle.bodyFont))
        }

        let buttonFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let buttonTitles: [String?] = [
            content.appPrimaryButtonTitle,
            content.appShowSkipButton ? skipAppVersionTitle : nil,
            content.cliPrimaryButtonTitle,
            content.cliShowSkipButton ? skipCLIVersionTitle : nil,
        ]
        for title in buttonTitles.compactMap({ $0 }) {
            maxWidth = max(maxWidth, textWidth(title, font: buttonFont) + 28)
        }

        return maxWidth
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

@MainActor
private final class UpdatePanelHost: NSObject {
    struct Presentation {
        let statusLine: String
        let body: String
        let appUpdateAvailable: Bool
        let appReleaseURL: URL?
        let canInstallInApp: Bool
        let cliUpdateAvailable: Bool
        let progressText: String?
        let showProgress: Bool
        let progressIndeterminate: Bool
        let progressValue: Double
        let appPrimaryButtonTitle: String?
        let appPrimaryButtonEnabled: Bool
        let appShowSkipButton: Bool
        let cliPrimaryButtonTitle: String?
        let cliPrimaryButtonEnabled: Bool
        let cliShowSkipButton: Bool
    }

    private let app: Result<UpdateChecker.AppRelease, Error>
    private var cli: UpdateChecker.GrokCLIStatus
    private let onDismiss: () -> Void
    private var appPhaseObserver: NSObjectProtocol?
    private var cliPhaseObserver: NSObjectProtocol?
    private weak var panel: NSPanel?

    private(set) var presentation: Presentation

    init(
        app: Result<UpdateChecker.AppRelease, Error>,
        cli: UpdateChecker.GrokCLIStatus,
        onDismiss: @escaping () -> Void
    ) {
        self.app = app
        self.cli = cli
        self.onDismiss = onDismiss
        self.presentation = Self.makePresentation(app: app, cli: cli)
        super.init()

        appPhaseObserver = NotificationCenter.default.addObserver(
            forName: .grokBuildUpdaterPhaseChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPresentation()
            }
        }

        cliPhaseObserver = NotificationCenter.default.addObserver(
            forName: .grokBuildCLIUpdaterPhaseChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPresentation()
            }
        }
    }

    deinit {
        if let appPhaseObserver {
            NotificationCenter.default.removeObserver(appPhaseObserver)
        }
        if let cliPhaseObserver {
            NotificationCenter.default.removeObserver(cliPhaseObserver)
        }
    }

    func attach(panel: NSPanel) {
        self.panel = panel
    }

    func makeRootView(panelWidth: CGFloat) -> NSView {
        let content = presentation
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

        let nameLabel = centeredLabel("GrokBuild", font: AboutStyle.appNameFont)

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

        var bottomAnchor = bodyLabel.bottomAnchor
        var constraints: [NSLayoutConstraint] = [
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

        if content.showProgress {
            let progressLabel = centeredLabel(content.progressText ?? "", font: AboutStyle.bodyFont)
            let progress = NSProgressIndicator()
            progress.isIndeterminate = content.progressIndeterminate
            if !content.progressIndeterminate {
                progress.minValue = 0
                progress.maxValue = 1
                progress.doubleValue = content.progressValue
            }
            progress.translatesAutoresizingMaskIntoConstraints = false
            if content.progressIndeterminate {
                progress.startAnimation(nil)
            }

            container.addSubview(progressLabel)
            container.addSubview(progress)

            constraints += [
                progressLabel.topAnchor.constraint(equalTo: bottomAnchor, constant: 12),
                progressLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

                progress.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 8),
                progress.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                progress.widthAnchor.constraint(equalToConstant: min(panelWidth - 80, 260)),
            ]
            bottomAnchor = progress.bottomAnchor
        }

        let outerStack = NSStackView()
        outerStack.orientation = .vertical
        outerStack.alignment = .centerX
        outerStack.spacing = 12
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        if content.appUpdateAvailable || content.appPrimaryButtonTitle != nil {
            outerStack.addArrangedSubview(
                makeButtonStack(
                    primaryTitle: content.appPrimaryButtonTitle,
                    primaryEnabled: content.appPrimaryButtonEnabled,
                    primaryAction: #selector(appPrimaryAction(_:)),
                    secondaryTitle: nil,
                    secondaryAction: nil,
                    skipTitle: content.appShowSkipButton ? UpdatePanel.skipAppVersionTitle : nil,
                    skipAction: #selector(skipAppVersion(_:))
                )
            )
        }

        if content.cliUpdateAvailable || content.cliPrimaryButtonTitle != nil {
            outerStack.addArrangedSubview(
                makeButtonStack(
                    primaryTitle: content.cliPrimaryButtonTitle,
                    primaryEnabled: content.cliPrimaryButtonEnabled,
                    primaryAction: #selector(cliPrimaryAction(_:)),
                    secondaryTitle: nil,
                    secondaryAction: nil,
                    skipTitle: content.cliShowSkipButton ? UpdatePanel.skipCLIVersionTitle : nil,
                    skipAction: #selector(skipCLIVersion(_:))
                )
            )
        }

        if !outerStack.arrangedSubviews.isEmpty {
            container.addSubview(outerStack)
            constraints += [
                outerStack.topAnchor.constraint(equalTo: bottomAnchor, constant: 16),
                outerStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                outerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            ]
        } else {
            constraints += [
                bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            ]
        }

        NSLayoutConstraint.activate(constraints)
        container.layoutSubtreeIfNeeded()
        effect.heightAnchor.constraint(equalToConstant: container.fittingSize.height).isActive = true
        return effect
    }

    private func makeButtonStack(
        primaryTitle: String?,
        primaryEnabled: Bool,
        primaryAction: Selector,
        secondaryTitle: String?,
        secondaryAction: Selector?,
        skipTitle: String?,
        skipAction: Selector?
    ) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8

        if let primaryTitle {
            let button = NSButton(title: primaryTitle, target: self, action: primaryAction)
            button.bezelStyle = .push
            button.bezelColor = .controlAccentColor
            button.contentTintColor = .white
            button.isEnabled = primaryEnabled
            stack.addArrangedSubview(button)
        }

        if let secondaryTitle, let secondaryAction {
            let button = NSButton(title: secondaryTitle, target: self, action: secondaryAction)
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            stack.addArrangedSubview(button)
        }

        if let skipTitle, let skipAction {
            let button = NSButton(title: skipTitle, target: self, action: skipAction)
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            stack.addArrangedSubview(button)
        }

        return stack
    }

    @objc private func appPrimaryAction(_ sender: NSButton) {
        guard case .success(let release) = app else { return }

        switch AppUpdater.shared.phase {
        case .readyToInstall(let extractedAppURL, _):
            confirmAppInstall(version: release.latestVersion) {
                AppUpdater.shared.installAndRestart(extractedAppURL: extractedAppURL)
            }
        case .idle, .failed:
#if DEBUG
            let canInstall = release.canInstallInApp
                || UpdateDebugSimulator.isAppSimulationActive
                || UpdateDebugSimulator.isSimulatedAppRelease(release)
#else
            let canInstall = release.canInstallInApp
#endif
            guard canInstall else {
                openReleaseNotes(sender)
                return
            }
            Task {
                await AppUpdater.shared.downloadAndVerify(release: release)
            }
        case .downloading, .verifying, .installing:
            break
        }
    }

    @objc private func cliPrimaryAction(_ sender: NSButton) {
        switch GrokCLIUpdater.shared.phase {
        case .success:
            UpdateUI.restartLiveSessions()
            onDismiss()
            panel?.close()
        case .idle, .failed:
            confirmCLIUpdate {
                Task {
                    await GrokCLIUpdater.shared.updateCLI()
                }
            }
        case .updating:
            break
        }
    }

    @objc private func openReleaseNotes(_ sender: Any?) {
        guard case .success(let release) = app else { return }
        NSWorkspace.shared.open(release.releaseURL)
    }

    @objc private func skipAppVersion(_ sender: NSButton) {
        guard case .success(let release) = app else { return }
        UpdateSettingsStore.skipVersion(release.latestVersion)
        onDismiss()
        panel?.close()
    }

    @objc private func skipCLIVersion(_ sender: NSButton) {
        guard let latest = cli.latestVersion else { return }
        UpdateSettingsStore.skipCLIVersion(latest)
        onDismiss()
        panel?.close()
    }

    private func confirmAppInstall(version: String, onConfirm: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Install GrokBuild \(version)?"
        alert.informativeText = "GrokBuild will quit, replace itself with the new version, and reopen. Save any work first."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install and Restart")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            onConfirm()
        }
    }

    private func confirmCLIUpdate(onConfirm: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Update grok CLI?"
        alert.informativeText = "Live Grok sessions will stop while the CLI updates. You can restart them afterward."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update grok CLI")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            onConfirm()
        }
    }

    private func refreshPresentation() {
        if let cached = UpdateScheduler.cachedCLIStatus {
            cli = cached
        }
        presentation = Self.makePresentation(app: app, cli: cli)
        UpdatePanel.refreshIfVisible()
    }

    private static func makePresentation(
        app: Result<UpdateChecker.AppRelease, Error>,
        cli: UpdateChecker.GrokCLIStatus
    ) -> Presentation {
        var appSection: String?
        var appReleaseURL: URL?
        var appUpdateAvailable = false
        var canInstallInApp = false
        let cliUpdateAvailable = UpdateSettingsStore.shouldNotifyCLI(for: cli)
        var anyUpdateAvailable = cliUpdateAvailable

        switch app {
        case .success(let release):
            appReleaseURL = release.releaseURL
            appUpdateAvailable = UpdateSettingsStore.shouldNotify(for: release)
            canInstallInApp = release.canInstallInApp
#if DEBUG
            if appUpdateAvailable,
               UpdateDebugSimulator.isAppSimulationActive
                || UpdateDebugSimulator.isSimulatedAppRelease(release) {
                canInstallInApp = true
            }
#endif
            anyUpdateAvailable = anyUpdateAvailable || appUpdateAvailable

            let installedAhead = UpdateChecker.compareVersions(
                release.installedVersion,
                release.latestVersion
            ) == .orderedDescending

            var lines = [
                "GrokBuild",
                "Installed: \(release.installedVersion)",
                "Latest release: \(release.latestVersion)",
            ]
            if installedAhead {
                lines.append("Status: Installed build is newer than the latest GitHub release.")
            } else if release.updateAvailable {
                lines.append("Status: Update available.")
            } else {
                lines.append("Status: Up to date.")
            }
            appSection = lines.joined(separator: "\n")
        case .failure(let error):
            appSection = "GrokBuild\nCould not check for updates: \(error.localizedDescription)"
        }

        let appUpdater = AppUpdater.shared
        let cliUpdater = GrokCLIUpdater.shared
        let cliBusy = cliUpdater.isBusy
        let appBusy = appUpdater.isBusy

        var progressText: String?
        var showProgress = false
        var progressIndeterminate = false
        var progressValue = 0.0
        var appPrimaryButtonTitle: String?
        var appPrimaryButtonEnabled = !cliBusy
        let appShowSkipButton = appUpdateAvailable
        var cliPrimaryButtonTitle: String?
        var cliPrimaryButtonEnabled = !appBusy
        var cliShowSkipButton = cliUpdateAvailable

        switch appUpdater.phase {
        case .idle:
            if appUpdateAvailable {
                appPrimaryButtonTitle = canInstallInApp ? "Update App" : "Open Release Page"
            }
        case .downloading(let progress):
            showProgress = true
            progressValue = progress
            progressText = "Downloading GrokBuild… \(Int(progress * 100))%"
            appPrimaryButtonTitle = "Downloading…"
            appPrimaryButtonEnabled = false
            cliPrimaryButtonEnabled = false
        case .verifying:
            showProgress = true
            progressText = "Verifying GrokBuild download…"
            progressValue = 0
            appPrimaryButtonTitle = "Verifying…"
            appPrimaryButtonEnabled = false
            cliPrimaryButtonEnabled = false
        case .readyToInstall(_, let version):
            progressText = "Ready to install GrokBuild \(version)."
            appPrimaryButtonTitle = "Install and Restart"
        case .installing:
            showProgress = true
            progressIndeterminate = true
            progressText = "Installing GrokBuild update…"
            appPrimaryButtonTitle = "Installing…"
            appPrimaryButtonEnabled = false
            cliPrimaryButtonEnabled = false
        case .failed(let message):
            progressText = message
            if appUpdateAvailable {
                appPrimaryButtonTitle = canInstallInApp ? "Retry Update" : "Open Release Page"
            }
        }

        switch cliUpdater.phase {
        case .idle:
            if cliUpdateAvailable {
                cliPrimaryButtonTitle = "Update grok CLI"
            }
        case .updating:
            showProgress = true
            progressIndeterminate = true
            progressText = "Updating grok CLI…"
            cliPrimaryButtonTitle = "Updating…"
            cliPrimaryButtonEnabled = false
            appPrimaryButtonEnabled = false
        case .success(let version):
            progressText = "grok CLI updated to \(version)."
            cliPrimaryButtonTitle = "Restart Sessions"
            cliShowSkipButton = false
        case .failed(let message, let detail):
            var lines = [message]
            if let detail, !detail.isEmpty {
                lines.append(detail)
            }
            progressText = lines.joined(separator: "\n\n")
            if cliUpdateAvailable {
                cliPrimaryButtonTitle = "Retry Update"
            }
        }

        let statusLine: String
        if anyUpdateAvailable {
            statusLine = "Updates Available"
        } else if case .failure = app, case .checkFailed = cli.state {
            statusLine = "Could Not Check for Updates"
        } else if case .success(let release) = app,
                  UpdateChecker.compareVersions(release.installedVersion, release.latestVersion) == .orderedDescending {
            statusLine = "No Updates Available"
        } else {
            statusLine = "Everything Is Up to Date"
        }

        let sections = [Self.grokCLISection(for: cli.state), appSection]
            .compactMap { $0 }
            .joined(separator: "\n\n")

        var bodyParts = [statusLine]
        if !anyUpdateAvailable, statusLine == "No Updates Available" {
            bodyParts.append("Nothing to install right now.")
        }
        bodyParts.append(sections)
        if let progressText, !progressText.isEmpty, !showProgress {
            bodyParts.append(progressText)
        }
        let body = bodyParts.joined(separator: "\n\n")

        return Presentation(
            statusLine: statusLine,
            body: body,
            appUpdateAvailable: appUpdateAvailable,
            appReleaseURL: appReleaseURL,
            canInstallInApp: canInstallInApp,
            cliUpdateAvailable: cliUpdateAvailable,
            progressText: progressText,
            showProgress: showProgress,
            progressIndeterminate: progressIndeterminate,
            progressValue: progressValue,
            appPrimaryButtonTitle: appPrimaryButtonTitle,
            appPrimaryButtonEnabled: appPrimaryButtonEnabled,
            appShowSkipButton: appShowSkipButton,
            cliPrimaryButtonTitle: cliPrimaryButtonTitle,
            cliPrimaryButtonEnabled: cliPrimaryButtonEnabled,
            cliShowSkipButton: cliShowSkipButton
        )
    }

    private func centeredLabel(_ text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static func grokCLISection(for state: UpdateChecker.GrokCLIStatus.State) -> String {
        switch state {
        case .upToDate(let info), .updateAvailable(let info):
            var lines = [
                "grok CLI",
                "Installed: \(info.current)",
                "Latest: \(info.latest)",
            ]
            if let channel = info.channel, !channel.isEmpty {
                lines.append("Channel: \(channel)")
            }
            if let installer = info.installer, !installer.isEmpty {
                lines.append("Installer: \(installer)")
            }
            if case .upToDate = state {
                lines.append("Status: Up to date.")
            } else {
                lines.append("Status: Update available.")
            }
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
