import AppKit
import SwiftUI

enum GrokStatus {
    case idle, ready, busy, error, starting

    init(rawStatus: String) {
        switch rawStatus {
        case "ready": self = .ready
        case "busy": self = .busy
        case "error": self = .error
        case "starting": self = .starting
        default: self = .idle
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle: return "Idle"
        case .ready: return "Ready"
        case .busy: return "Working"
        case .error: return "Error"
        case .starting: return "Starting"
        }
    }
}

enum StatusBarMenuCopy {
    static func menuTitle(authenticated: Bool) -> String {
        authenticated
            ? "Signed in to grok CLI"
            : "Sign in required — run grok login"
    }

    static func updateMenuTitle(hasActionableUpdate: Bool) -> String {
        hasActionableUpdate ? "Upgrade Available…" : "Check for Updates…"
    }
}

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var menu: NSMenu

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()

        super.init()

        setupStatusItem()
        setupMenu()

        statusItem.menu = menu

        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalShowMainWindow),
            name: NSNotification.Name("com.grokbuild.showMainWindow"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: .grokStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let raw = note.userInfo?["status"] as? String {
                self?.updateIcon(for: GrokStatus(rawStatus: raw))
            }
            if let auth = note.userInfo?["authenticated"] as? Bool {
                self?.updateAuthIndicator(authenticated: auth)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .grokBuildUpdateAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshUpdateMenuItem()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .grokBuildUpdateStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshUpdateMenuItem()
            }
        }

        updateIcon(for: .idle)
        updateAuthIndicator(authenticated: GrokAuthProbe.isLikelyAuthenticated())
        Task { @MainActor in
            self.refreshUpdateMenuItem()
        }
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        let iconImage: NSImage? = GrokBrandIcon.mark()

        if let image = iconImage {
            image.size = NSSize(width: 22, height: 22)
            image.isTemplate = true
            button.image = image
        } else {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "GrokBuild")
        }

        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(statusItemClicked)
    }

    private func showMainWindow() {
        NotificationCenter.default.post(name: .showMainWindowRequested, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Run after the status-item menu finishes tracking so `makeKeyAndOrderFront`
    /// does not put the main window under the leftover mouse-up (which then hits
    /// Sessions History / the selected project and leaves Settings).
    private func performAfterStatusMenuCloses(_ action: @escaping () -> Void) {
        DispatchQueue.main.async(execute: action)
    }

    private var grokBuildTitleItem: NSMenuItem!
    private var terminalLoginItem: NSMenuItem!
    private var retryConnectionItem: NSMenuItem!
    private var updateCheckItem: NSMenuItem!

    private func setupMenu() {
        grokBuildTitleItem = NSMenuItem(
            title: StatusBarMenuCopy.menuTitle(authenticated: GrokAuthProbe.isLikelyAuthenticated()),
            action: nil,
            keyEquivalent: ""
        )
        grokBuildTitleItem.isEnabled = false
        menu.addItem(grokBuildTitleItem)

        terminalLoginItem = NSMenuItem(
            title: "Run `grok login` in Terminal…",
            action: #selector(openTerminalForLogin),
            keyEquivalent: ""
        )
        terminalLoginItem.target = self
        terminalLoginItem.isHidden = true
        menu.addItem(terminalLoginItem)

        retryConnectionItem = NSMenuItem(title: "Retry Connection", action: #selector(retryConnection), keyEquivalent: "")
        retryConnectionItem.target = self
        retryConnectionItem.isHidden = true
        menu.addItem(retryConnectionItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open GrokBuild", action: #selector(openGrokBuild), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let newSessionItem = NSMenuItem(title: "New Session", action: #selector(newSession), keyEquivalent: "n")
        newSessionItem.target = self
        menu.addItem(newSessionItem)

        let sessionsItem = NSMenuItem(title: SessionsHistoryCopy.menuItem, action: #selector(browseSessions), keyEquivalent: "")
        sessionsItem.target = self
        menu.addItem(sessionsItem)

        let chooseWorkspace = NSMenuItem(title: "Add Project…", action: #selector(chooseWorkspace), keyEquivalent: "")
        chooseWorkspace.target = self
        menu.addItem(chooseWorkspace)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        updateCheckItem = NSMenuItem(
            title: StatusBarMenuCopy.updateMenuTitle(hasActionableUpdate: false),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateCheckItem.target = self
        menu.addItem(updateCheckItem)

#if DEBUG
        menu.addItem(makeSimulateUpdatesMenuItem())
#endif

        let viewUsageItem = NSMenuItem(title: "View Usage on grok.com…", action: #selector(openUsagePage), keyEquivalent: "")
        viewUsageItem.target = self
        menu.addItem(viewUsageItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About GrokBuild", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit GrokBuild", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func statusItemClicked() {
        showMainWindow()
    }

    @objc private func handleExternalShowMainWindow() {
        DispatchQueue.main.async { [weak self] in
            self?.showMainWindow()
        }
    }

    deinit {
        DistributedNotificationCenter.default.removeObserver(self)
    }

    @objc private func openGrokBuild() {
        performAfterStatusMenuCloses { [weak self] in
            self?.showMainWindow()
        }
    }

    @objc private func newSession() {
        performAfterStatusMenuCloses { [weak self] in
            self?.showMainWindow()
            NotificationCenter.default.post(name: .newSessionRequested, object: nil)
        }
    }

    @objc private func browseSessions() {
        performAfterStatusMenuCloses { [weak self] in
            self?.showMainWindow()
            NotificationCenter.default.post(name: .sessionsRequested, object: nil)
        }
    }

    @objc private func chooseWorkspace() {
        performAfterStatusMenuCloses { [weak self] in
            NotificationCenter.default.post(name: .chooseWorkspaceRequested, object: nil)
            self?.showMainWindow()
        }
    }

    @objc private func openSettings() {
        performAfterStatusMenuCloses { [weak self] in
            self?.showMainWindow()
            NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
        }
    }

    @objc private func retryConnection() {
        performAfterStatusMenuCloses { [weak self] in
            self?.showMainWindow()
            NotificationCenter.default.post(name: .retryConnectionRequested, object: nil)
        }
    }

    @objc private func openTerminalForLogin() {
        let script = """
        tell application "Terminal"
            activate
            do script "grok login"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error != nil {
                if let url = URL(string: "file:///System/Applications/Utilities/Terminal.app") {
                    NSWorkspace.shared.open(url)
                }
            }
        } else if let url = URL(string: "file:///System/Applications/Utilities/Terminal.app") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showAbout() {
        AboutPanel.show()
    }

    @objc private func checkForUpdates() {
        updateCheckItem.isEnabled = false
        updateCheckItem.title = "Checking for Updates…"

        Task { @MainActor [weak self] in
            self?.statusItem.menu?.cancelTracking()
            await UpdateScheduler.checkNow()
            self?.resetUpdateMenuItem()

            await UpdateUI.presentUpdatePanel(refresh: false) { [weak self] in
                self?.resetUpdateMenuItem()
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openUsagePage() {
        if let url = URL(string: "https://grok.com/?_s=usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private func resetUpdateMenuItem() {
        refreshUpdateMenuItem()
        updateCheckItem.isEnabled = true
    }

    @MainActor
    private func refreshUpdateMenuItem() {
        updateCheckItem.title = StatusBarMenuCopy.updateMenuTitle(
            hasActionableUpdate: UpdateScheduler.hasAnyActionableUpdate
        )
    }

#if DEBUG
    private func makeSimulateUpdatesMenuItem() -> NSMenuItem {
        let submenu = NSMenu()

        let appItem = NSMenuItem(
            title: "App Update Available",
            action: #selector(simulateAppUpdate),
            keyEquivalent: ""
        )
        appItem.target = self
        submenu.addItem(appItem)

        let cliItem = NSMenuItem(
            title: "grok CLI Update Available",
            action: #selector(simulateCLIUpdate),
            keyEquivalent: ""
        )
        cliItem.target = self
        submenu.addItem(cliItem)

        let bothItem = NSMenuItem(
            title: "Both Updates Available",
            action: #selector(simulateBothUpdates),
            keyEquivalent: ""
        )
        bothItem.target = self
        submenu.addItem(bothItem)

        submenu.addItem(.separator())

        let clearItem = NSMenuItem(
            title: "Clear Simulation",
            action: #selector(clearSimulatedUpdates),
            keyEquivalent: ""
        )
        clearItem.target = self
        submenu.addItem(clearItem)

        let item = NSMenuItem(title: "Simulate Updates", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func simulateAppUpdate() {
        Task { @MainActor in
            UpdateDebugSimulator.apply(.app)
            self.refreshUpdateMenuItem()
        }
    }

    @objc private func simulateCLIUpdate() {
        Task { @MainActor in
            UpdateDebugSimulator.apply(.cli)
            self.refreshUpdateMenuItem()
        }
    }

    @objc private func simulateBothUpdates() {
        Task { @MainActor in
            UpdateDebugSimulator.apply(.both)
            self.refreshUpdateMenuItem()
        }
    }

    @objc private func clearSimulatedUpdates() {
        Task { @MainActor in
            await UpdateDebugSimulator.clear()
            self.refreshUpdateMenuItem()
        }
    }
#endif

    private func updateIcon(for status: GrokStatus) {
        guard let button = statusItem.button else { return }

        button.setAccessibilityValue(status.accessibilityLabel)

        let dotColor: NSColor
        switch status {
        case .ready:
            dotColor = .systemGreen
        case .busy, .starting:
            dotColor = .systemBlue
        case .error:
            dotColor = .systemRed
        case .idle:
            dotColor = .clear
        }

        let baseIcon: NSImage? = GrokBrandIcon.mark()
        if let img = baseIcon {
            if img.size.width > 20 {
                img.size = NSSize(width: 22, height: 22)
            }
            img.isTemplate = true
        }

        guard let icon = baseIcon else {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "GrokBuild")
            return
        }

        icon.size = NSSize(width: 22, height: 22)

        if dotColor == .clear {
            button.image = icon
        } else {
            let labelColor = menuBarLabelColor(for: button)
            let tintedIcon = tinted(icon, color: labelColor)
            let size = NSSize(width: 22, height: 22)
            let composedImage = NSImage(size: size, flipped: false) { rect in
                tintedIcon.draw(in: rect)
                let dotSize: CGFloat = 7
                let dotRect = NSRect(x: rect.width - dotSize - 2, y: 2, width: dotSize, height: dotSize)
                dotColor.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
                return true
            }
            composedImage.isTemplate = false
            button.image = composedImage
        }
    }

    private func menuBarLabelColor(for button: NSStatusBarButton) -> NSColor {
        var color = NSColor.labelColor
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor
        }
        return color
    }

    private func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let out = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        out.isTemplate = false
        return out
    }

    private func updateAuthIndicator(authenticated: Bool) {
        let color = authenticated ? NSColor.systemGreen : NSColor.systemRed
        grokBuildTitleItem.image = dotImage(color: color)
        grokBuildTitleItem.title = StatusBarMenuCopy.menuTitle(authenticated: authenticated)
        terminalLoginItem.isHidden = authenticated
        retryConnectionItem.isHidden = authenticated
    }

    private func dotImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size, flipped: false) { _ in
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 10, height: 10)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
