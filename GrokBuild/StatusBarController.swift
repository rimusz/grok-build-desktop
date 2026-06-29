import AppKit
import SwiftUI

enum GrokStatus {
    case idle, ready, busy, error
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
                let status: GrokStatus
                switch raw {
                case "ready": status = .ready
                case "busy": status = .busy
                case "error": status = .error
                default: status = .idle
                }
                self?.updateIcon(for: status)
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

        updateIcon(for: .idle)
        updateAuthIndicator(authenticated: true)
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

    private var grokBuildTitleItem: NSMenuItem!
    private var updateCheckItem: NSMenuItem!
    private func setupMenu() {
        grokBuildTitleItem = NSMenuItem(title: menuTitle(authenticated: true), action: nil, keyEquivalent: "")
        grokBuildTitleItem.isEnabled = false
        menu.addItem(grokBuildTitleItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About GrokBuild", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        updateCheckItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateCheckItem.target = self
        menu.addItem(updateCheckItem)

#if DEBUG
        menu.addItem(.separator())
        menu.addItem(makeSimulateUpdatesMenuItem())
#endif

        menu.addItem(.separator())

        let viewUsageItem = NSMenuItem(title: "View Usage on grok.com…", action: #selector(openUsagePage), keyEquivalent: "")
        viewUsageItem.target = self
        menu.addItem(viewUsageItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open GrokBuild", action: #selector(openGrokBuild), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let newSessionItem = NSMenuItem(title: "New Session", action: #selector(newSession), keyEquivalent: "n")
        newSessionItem.target = self
        menu.addItem(newSessionItem)

        let sessionsItem = NSMenuItem(title: "Browse Sessions…", action: #selector(browseSessions), keyEquivalent: "")
        sessionsItem.target = self
        menu.addItem(sessionsItem)

        menu.addItem(.separator())

        let chooseWorkspace = NSMenuItem(title: "Add Project…", action: #selector(chooseWorkspace), keyEquivalent: "")
        chooseWorkspace.target = self
        menu.addItem(chooseWorkspace)

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
        showMainWindow()
    }

    @objc private func newSession() {
        showMainWindow()
        NotificationCenter.default.post(name: .newSessionRequested, object: nil)
    }

    @objc private func browseSessions() {
        showMainWindow()
        NotificationCenter.default.post(name: .sessionsRequested, object: nil)
    }

    @objc private func chooseWorkspace() {
        NotificationCenter.default.post(name: .chooseWorkspaceRequested, object: nil)
        showMainWindow()
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

            if UpdateScheduler.hasAnyActionableUpdate {
                self?.showMainWindow()
            } else {
                await UpdateUI.presentUpdatePanel(refresh: false) { [weak self] in
                    self?.resetUpdateMenuItem()
                }
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
        if UpdateScheduler.hasAnyActionableUpdate {
            updateCheckItem.title = "Upgrade Available…"
        } else {
            updateCheckItem.title = "Check for Updates…"
        }
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

        let dotColor: NSColor
        switch status {
        case .ready:
            dotColor = .systemGreen
        case .busy:
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
            let size = NSSize(width: 22, height: 22)
            let composedImage = NSImage(size: size, flipped: false) { rect in
                icon.draw(in: rect)
                let dotSize: CGFloat = 7
                let dotRect = NSRect(x: rect.width - dotSize - 2, y: 2, width: dotSize, height: dotSize)
                dotColor.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
                return true
            }
            composedImage.isTemplate = true
            button.image = composedImage
        }
    }

    private func updateAuthIndicator(authenticated: Bool) {
        let color = authenticated ? NSColor.systemGreen : NSColor.systemRed
        grokBuildTitleItem.image = dotImage(color: color)
        grokBuildTitleItem.title = menuTitle(authenticated: authenticated)
    }

    private func menuTitle(authenticated: Bool) -> String {
        authenticated
            ? "GrokBuild connected to grok cli"
            : "GrokBuild not connected to grok cli"
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
