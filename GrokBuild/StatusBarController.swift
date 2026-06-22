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
        let iconImage: NSImage? = GrokBrandIcon.mark()

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

    private var grokBuildTitleItem: NSMenuItem!
    private var grokVersionItem: NSMenuItem!
    private var updateCheckItem: NSMenuItem!
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

        let aboutItem = NSMenuItem(title: "About GrokBuild", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        updateCheckItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateCheckItem.target = self
        menu.addItem(updateCheckItem)

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
        let chooseWorkspace = NSMenuItem(title: "Add Project…", action: #selector(chooseWorkspace), keyEquivalent: "")
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

    @objc private func showAbout() {
        AboutPanel.show()
    }

    @objc private func checkForUpdates() {
        updateCheckItem.isEnabled = false
        updateCheckItem.title = "Checking for Updates…"

        Task { [weak self] in
            do {
                let release = try await Self.fetchLatestRelease()
                await self?.presentUpdateResult(release)
            } catch {
                await self?.presentUpdateError(error)
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

    private struct GitHubRelease: Decodable {
        let tagName: String
        let name: String?
        let htmlURL: URL

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
        }
    }

    private static func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/rimusz/grok-build-desktop/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "GrokBuildUpdates",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not fetch the latest release from GitHub."]
            )
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    @MainActor
    private func presentUpdateResult(_ release: GitHubRelease) {
        resetUpdateMenuItem()

        let current = AppVersion.short
        let latest = normalizedVersion(release.tagName)
        let hasUpdate = compareVersions(latest, current) == .orderedDescending

        let alert = NSAlert()
        alert.icon = AppIconProvider.image()
        alert.messageText = hasUpdate ? "A New GrokBuild Version Is Available" : "GrokBuild Is Up to Date"
        alert.informativeText = hasUpdate
            ? "Installed: \(current)\nLatest: \(latest)\n\nDownload the latest release from GitHub."
            : "Installed: \(current)\nLatest: \(latest)"
        alert.alertStyle = hasUpdate ? .informational : .informational
        alert.addButton(withTitle: hasUpdate ? "Open Releases" : "OK")
        if hasUpdate {
            alert.addButton(withTitle: "Cancel")
        }

        let response = alert.runModal()
        if hasUpdate, response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    @MainActor
    private func presentUpdateError(_ error: Error) {
        resetUpdateMenuItem()

        let alert = NSAlert()
        alert.icon = AppIconProvider.image()
        alert.messageText = "Could Not Check for Updates"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor
    private func resetUpdateMenuItem() {
        updateCheckItem.title = "Check for Updates…"
        updateCheckItem.isEnabled = true
    }

    private func normalizedVersion(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[vV]"#, with: "", options: .regularExpression)
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }

        return .orderedSame
    }

    private func versionComponents(_ value: String) -> [Int] {
        normalizedVersion(value)
            .split(separator: ".")
            .map { component in
                let numericPrefix = component.prefix { $0.isNumber }
                return Int(numericPrefix) ?? 0
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