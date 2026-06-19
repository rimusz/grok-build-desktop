import AppKit
import SwiftUI

enum GrokStatus {
    case idle, ready, busy, error
}

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var menu: NSMenu
    private var popover: NSPopover?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()

        super.init()

        setupStatusItem()
        setupMenu()

        statusItem.menu = menu
        menu.delegate = self

        // Single-instance support: listen for "show me" requests from other launches
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleExternalShowPopover),
            name: NSNotification.Name("com.grokdeck.showPopover"),
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
        usageItem.title = "Usage: (fetching...)"
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        // Menu bar icon is in GrokDeck/Resources/Assets.xcassets/MenuBarIcon.imageset/
        // The packaging script copies the PNGs into Contents/Resources/.
        // We prefer NSImage(named:) or direct resource lookup; falls back to SF Symbol.
        let iconImage: NSImage? = loadTemplateIcon()

        if let image = iconImage {
            image.size = NSSize(width: 22, height: 22)
            image.isTemplate = true  // Important: makes it adapt to light/dark menu bar and system tint
            button.image = image
        } else {
            // Fallback
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "GrokDeck")
        }

        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(statusItemClicked)
    }

    private func setupPopover() {
        if popover != nil { return }
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 900, height: 550) // smaller footprint than full window
        pop.behavior = .transient
        let hosting = NSHostingController(rootView: ContentView())
        pop.contentViewController = hosting
        popover = pop
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        setupPopover()
        if let pop = popover {
            if pop.isShown {
                pop.performClose(nil)
            } else {
                pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    /// Robustly load the menu bar icon for both packaged .app and bare `swift build` / `make run` binaries.
    private func loadTemplateIcon() -> NSImage? {
        // 1. Prefer explicit flat icons next to the executable.
        // This ensures `make run` / direct binary always gets the freshly copied versions
        // (bypasses potentially stale SPM resource bundles in .build/.../GrokDeck_GrokDeck.bundle)
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

    private var grokDeckTitleItem: NSMenuItem!
    private var usageItem: NSMenuItem!

    private func setupMenu() {
        // Status with auth dot
        grokDeckTitleItem = NSMenuItem(title: "GrokDeck", action: nil, keyEquivalent: "")
        grokDeckTitleItem.isEnabled = false
        menu.addItem(grokDeckTitleItem)

        usageItem = NSMenuItem(title: "Usage", action: nil, keyEquivalent: "")
        usageItem.isEnabled = false
        menu.addItem(usageItem)

        let viewUsageItem = NSMenuItem(title: "View full usage on grok.com...", action: #selector(openUsagePage), keyEquivalent: "")
        viewUsageItem.target = self
        menu.addItem(viewUsageItem)

        menu.addItem(.separator())

        // Open the UI (popover)
        let openItem = NSMenuItem(title: "Open GrokDeck", action: #selector(openGrokDeck), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        // New Session
        let newSessionItem = NSMenuItem(title: "New Session", action: #selector(newSession), keyEquivalent: "n")
        newSessionItem.target = self
        menu.addItem(newSessionItem)

        menu.addItem(.separator())

        // Quick actions
        let chooseWorkspace = NSMenuItem(title: "Choose Workspace…", action: #selector(chooseWorkspace), keyEquivalent: "")
        chooseWorkspace.target = self
        menu.addItem(chooseWorkspace)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit GrokDeck", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func statusItemClicked() {
        showPopover()
    }

    @objc private func handleExternalShowPopover() {
        // Called via DistributedNotificationCenter when another instance
        // of the app tried to launch. Show our popover and bring us forward.
        DispatchQueue.main.async { [weak self] in
            self?.showPopover()
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func openGrokDeck() {
        showPopover()
    }

    @objc private func newSession() {
        showPopover()
        NotificationCenter.default.post(name: .newSessionRequested, object: nil)
    }

    @objc private func chooseWorkspace() {
        NotificationCenter.default.post(name: .chooseWorkspaceRequested, object: nil)
        showPopover()
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
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "GrokDeck")
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
        grokDeckTitleItem.image = dotImage(color: color)
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

    private func fetchUsage() async {
        let usageText = await fetchGlobalMonthlyUsage()
        await MainActor.run {
            usageItem.title = usageText
        }
    }

    private func getAuthToken() -> String? {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".grok/auth.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for (_, value) in json {
            if let dict = value as? [String: Any], let key = dict["key"] as? String, !key.isEmpty {
                return key
            }
        }
        return nil
    }

    private func fetchGlobalMonthlyUsage() async -> String {
        guard let token = getAuthToken() else {
            return await Self.fetchRecentTokenUsage()
        }

        let candidates = [
            "https://grok.com/api/usage",
            "https://grok.com/api/billing?format=credits",
            "https://api.grok.com/v1/usage",
            "https://api.x.ai/v1/usage",
            "https://code.grok.com/api/usage"
        ]

        for urlString in candidates {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 6.0

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Common shapes we might see
                        let used = (json["used"] as? Int) ?? (json["credits_used"] as? Int) ?? (json["tokens_used"] as? Int)
                        let limit = (json["limit"] as? Int) ?? (json["credits_limit"] as? Int) ?? (json["tokens_limit"] as? Int) ?? (json["quota"] as? Int)
                        if let used = used, let limit = limit, limit > 0 {
                            let pct = Int((Double(used) / Double(limit)) * 100)
                            return "Usage: \(used.formatted()) / \(limit.formatted()) (\(pct)%)"
                        }
                        // Try nested billing cycle
                        if let cycle = (json["billing_cycle"] as? [String: Any]) ?? (json["cycle"] as? [String: Any]) {
                            let u = (cycle["used"] as? Int) ?? (cycle["credits_used"] as? Int)
                            let l = (cycle["limit"] as? Int) ?? (cycle["credits_limit"] as? Int)
                            if let u = u, let l = l, l > 0 {
                                let pct = Int((Double(u) / Double(l)) * 100)
                                return "Usage: \(u.formatted()) / \(l.formatted()) (\(pct)%)"
                            }
                        }
                    }
                }
            } catch {
                continue
            }
        }

        // Fall back to local per-session context usage (still free)
        return await Self.fetchRecentTokenUsage()
    }

    private static func fetchRecentTokenUsage() async -> String {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let sessionsRoot = home.appendingPathComponent(".grok/sessions")

        guard let sessionDirs = try? fm.contentsOfDirectory(at: sessionsRoot, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return "Usage: (no data)"
        }

        if sessionDirs.isEmpty {
            return "Usage: (no sessions yet — select workspace & chat)"
        }

        var latest: (url: URL, date: Date)?
        for dir in sessionDirs where dir.hasDirectoryPath {
            let sig = dir.appendingPathComponent("signals.json")
            if fm.fileExists(atPath: sig.path) {
                if let vals = try? sig.resourceValues(forKeys: [.contentModificationDateKey]),
                   let mod = vals.contentModificationDate {
                    if latest == nil || mod > latest!.date {
                        latest = (sig, mod)
                    }
                }
            }
        }

        guard let latestSignal = latest?.url else {
            // There are session directories but no signals.json yet (common on first run)
            return "Usage: (no data yet — chat a bit to populate)"
        }

        do {
            let data = try Data(contentsOf: latestSignal)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let used = obj["contextTokensUsed"] as? Int ?? (obj["totalTokensBeforeCompaction"] as? Int ?? 0)
                let window = obj["contextWindowTokens"] as? Int ?? 200000
                if window > 0 {
                    let pct = Int(Double(used) / Double(window) * 100.0)
                    return "Usage (context): \(used.formatted()) / \(window.formatted()) (\(pct)%)"
                }
            }
        } catch {}

        return "Usage: (no data)"
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        Task { [weak self] in
            await self?.fetchUsage()
        }
    }
}