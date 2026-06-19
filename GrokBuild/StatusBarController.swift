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

        // Single-instance support: listen for "show me" requests from other launches
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleExternalShowMainWindow),
            name: NSNotification.Name("com.grokbuild.showMainWindow"),
            object: nil
        )

        // Observe status for live dot indicator
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

        updateIcon(for: .idle)
        updateAuthIndicator(authenticated: true) // default until we know
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        // Menu bar icon is in GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset/
        // The packaging script copies the PNGs into Contents/Resources/.
        // We prefer NSImage(named:) or direct resource lookup; falls back to SF Symbol.
        let iconImage: NSImage? = loadTemplateIcon()

        if let image = iconImage {
            image.size = NSSize(width: 22, height: 22)
            image.isTemplate = true  // Important: makes it adapt to light/dark menu bar and system tint
            button.image = image
        } else {
            // Fallback
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

    /// Robustly load the menu bar icon for both packaged .app and bare `swift build` / `make run` binaries.
    private func loadTemplateIcon() -> NSImage? {
        // 1. Prefer explicit flat icons next to the executable.
        // This ensures `make run` / direct binary always gets the freshly copied versions
        // (bypasses potentially stale SPM resource bundles in .build/.../GrokBuild_GrokBuild.bundle)
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            for name in ["MenuBarIcon@2x.png", "MenuBarIcon.png", "MenuBarIcon@3x.png"] {
                let direct = execDir.appendingPathComponent(name).path
                if FileManager.default.fileExists(atPath: direct),
                   let img = NSImage(contentsOfFile: direct) {
                    return img
                }
            }
        }

        // 2. Also check current working directory
        for name in ["MenuBarIcon@2x.png", "MenuBarIcon.png"] {
            if FileManager.default.fileExists(atPath: name),
               let img = NSImage(contentsOfFile: name) {
                return img
            }
        }

        // 3. Asset catalog name (best for properly packaged .app bundles)
        if let image = NSImage(named: "MenuBarIcon") {
            return image
        }

        // 4. Standard bundle resource lookup (flat PNGs)
        let candidates = ["MenuBarIcon@2x", "MenuBarIcon", "MenuBarIcon@3x"]
        for name in candidates {
            if let path = Bundle.main.path(forResource: name, ofType: "png") {
                if let img = NSImage(contentsOfFile: path) {
                    return img
                }
            }
        }

        // 5. xcassets subdir fallback (SPM sometimes puts them here)
        for name in ["MenuBarIcon@2x", "MenuBarIcon", "MenuBarIcon@3x"] {
            if let path = Bundle.main.path(forResource: name, ofType: "png", inDirectory: "Assets.xcassets/MenuBarIcon.imageset") {
                if let img = NSImage(contentsOfFile: path) {
                    return img
                }
            }
        }

        return nil
    }

    private var grokBuildTitleItem: NSMenuItem!
    private var grokVersionItem: NSMenuItem!
    private func setupMenu() {
        // Status with auth dot
        grokBuildTitleItem = NSMenuItem(title: "GrokBuild", action: nil, keyEquivalent: "")
        grokBuildTitleItem.isEnabled = false
        menu.addItem(grokBuildTitleItem)

        grokVersionItem = NSMenuItem(title: "grok CLI: checking…", action: nil, keyEquivalent: "")
        grokVersionItem.isEnabled = false
        menu.addItem(grokVersionItem)
        loadGrokVersion()

        menu.addItem(.separator())

        let viewUsageItem = NSMenuItem(title: "View Usage on grok.com…", action: #selector(openUsagePage), keyEquivalent: "")
        viewUsageItem.target = self
        menu.addItem(viewUsageItem)

        menu.addItem(.separator())

        // Open the normal Dock app window
        let openItem = NSMenuItem(title: "Open GrokBuild", action: #selector(openGrokBuild), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        // New Session
        let newSessionItem = NSMenuItem(title: "New Session", action: #selector(newSession), keyEquivalent: "n")
        newSessionItem.target = self
        menu.addItem(newSessionItem)

        let sessionsItem = NSMenuItem(title: "Browse Sessions…", action: #selector(browseSessions), keyEquivalent: "")
        sessionsItem.target = self
        menu.addItem(sessionsItem)

        menu.addItem(.separator())

        // Quick actions
        let chooseWorkspace = NSMenuItem(title: "Choose Project…", action: #selector(chooseWorkspace), keyEquivalent: "")
        chooseWorkspace.target = self
        menu.addItem(chooseWorkspace)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit GrokBuild", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func loadGrokVersion() {
        Task { [weak self] in
            let title: String
            do {
                let output = try await GrokCLIService()
                    .run(["--version"])
                    .stdout
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                title = output.isEmpty ? "grok CLI: version unavailable" : "grok CLI: \(self?.formatGrokVersion(output) ?? output)"
            } catch {
                title = "grok CLI: not found"
            }

            await self?.setGrokVersionTitle(title)
        }
    }

    @MainActor
    private func setGrokVersionTitle(_ title: String) {
        grokVersionItem.title = title
    }

    private func formatGrokVersion(_ output: String) -> String {
        // `grok --version` returns: "grok 0.2.56 (hash) [stable]".
        let withoutName = output.replacingOccurrences(
            of: #"^grok\s+"#,
            with: "",
            options: .regularExpression
        )
        return withoutName.replacingOccurrences(
            of: #"\s+\([^)]+\)"#,
            with: "",
            options: .regularExpression
        )
    }

    @objc private func statusItemClicked() {
        showMainWindow()
    }

    @objc private func handleExternalShowMainWindow() {
        // Called via DistributedNotificationCenter when another instance
        // of the app tried to launch. Show the main window and bring us forward.
        DispatchQueue.main.async { [weak self] in
            self?.showMainWindow()
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openUsagePage() {
        if let url = URL(string: "https://grok.com/?_s=usage") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Status dot indicator (reused from referenced repo)

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

        let baseIcon: NSImage? = loadTemplateIcon()
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
            // No status dot — use the base template icon directly (cleanest rendering, no extra composition)
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
            // The main symbol is template-tinted; the dot is drawn on top in its native color
            composedImage.isTemplate = true
            button.image = composedImage
        }
    }

    private func updateAuthIndicator(authenticated: Bool) {
        let color = authenticated ? NSColor.systemGreen : NSColor.systemRed
        grokBuildTitleItem.image = dotImage(color: color)
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