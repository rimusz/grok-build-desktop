import AppKit
import SwiftUI
import Darwin   // POSIX: open, O_EXCL, close, write, kill, getpid

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusBarController: StatusBarController?
    private var lockFd: Int32 = -1   // fd that holds the flock for the lifetime of the process

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce single instance with flock (advisory lock held by open fd).
        // This is race-free even for rapid `make run ; make run`.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GrokBuild")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let pidFile = support.appendingPathComponent("instance.pid")

        let fd = open(pidFile.path, O_WRONLY | O_CREAT, 0o644)
        if fd == -1 {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.grokbuild.showMainWindow"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            NSApp.terminate(nil)
            return
        }

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            // Another instance already holds the lock
            close(fd)
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.grokbuild.showMainWindow"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            NSApp.terminate(nil)
            return
        }

        // We hold the lock as long as this process (and this fd) lives
        self.lockFd = fd

        // Write PID for convenience
        lseek(fd, 0, SEEK_SET)
        let pidStr = "\(getpid())\n"
        _ = pidStr.withCString { write(fd, $0, pidStr.utf8.count) }

        // Normal app (shows in Dock, supports windows + menu bar icon)
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()
        if let appIcon = AppIconProvider.image() {
            NSApp.applicationIconImage = appIcon
        }

        statusBarController = StatusBarController()
        UpdateScheduler.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openMainWindowRequested),
            name: .showMainWindowRequested,
            object: nil
        )

        // Open a main window on launch
        openMainWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Closing the fd releases the flock.
        // We also clean the PID file only if we are the owner.
        if lockFd != -1 {
            close(lockFd)
            lockFd = -1
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GrokBuild")
        let pidFile = support.appendingPathComponent("instance.pid")

        if let content = try? String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let filePid = Int32(content),
           filePid == getpid() {
            try? FileManager.default.removeItem(at: pidFile)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    private static let mainWindowDefaultSize = NSSize(width: 1024, height: 720)
    private static let mainWindowMinimumSize = NSSize(width: 800, height: 560)

    private func openMainWindow() {
        // If a window is already open, just bring it forward
        if let existing = NSApp.windows.first(where: { $0.contentViewController is NSHostingController<ContentView> }) {
            presentMainWindow(existing)
            return
        }

        let contentView = ContentView()
        let hosting = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.mainWindowDefaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GrokBuild"
        window.delegate = self
        window.contentViewController = hosting
        window.setFrameAutosaveName("MainWindow")
        presentMainWindow(window)
    }

    private func presentMainWindow(_ window: NSWindow) {
        normalizeMainWindowFrame(window)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func normalizeMainWindowFrame(_ window: NSWindow) {
        let minSize = Self.mainWindowMinimumSize
        var frame = window.frame

        if frame.width < minSize.width || frame.height < minSize.height {
            frame.size = Self.mainWindowDefaultSize
            window.setFrame(frame, display: false)
            window.center()
            window.saveFrame(usingName: window.frameAutosaveName)
            return
        }

        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let intersection = frame.intersection(visible)
            if intersection.width < minSize.width || intersection.height < minSize.height {
                window.center()
            }
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let about = NSMenuItem(title: "About GrokBuild", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit GrokBuild", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let editMenu = NSMenu(title: "Edit")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let projectMenu = NSMenu(title: "Project")
        let projectItem = NSMenuItem()
        projectItem.submenu = projectMenu
        mainMenu.addItem(projectItem)
        let addProject = NSMenuItem(title: "Add Project…", action: #selector(chooseWorkspace), keyEquivalent: "o")
        addProject.keyEquivalentModifierMask = [.command, .shift]
        addProject.target = self
        projectMenu.addItem(addProject)

        let sessionMenu = NSMenu(title: "Session")
        let sessionItem = NSMenuItem()
        sessionItem.submenu = sessionMenu
        mainMenu.addItem(sessionItem)
        let newSession = NSMenuItem(title: "New Session", action: #selector(newSession), keyEquivalent: "n")
        newSession.target = self
        sessionMenu.addItem(newSession)
        let browseSessions = NSMenuItem(title: "Browse Sessions…", action: #selector(browseSessions), keyEquivalent: "r")
        browseSessions.keyEquivalentModifierMask = [.command, .shift]
        browseSessions.target = self
        sessionMenu.addItem(browseSessions)
        let stopGeneration = NSMenuItem(title: "Stop Generation", action: #selector(stopGeneration), keyEquivalent: ".")
        stopGeneration.target = self
        sessionMenu.addItem(stopGeneration)
        let focusInput = NSMenuItem(title: "Focus Input", action: #selector(focusInput), keyEquivalent: "l")
        focusInput.target = self
        sessionMenu.addItem(focusInput)

        let windowMenu = NSMenu(title: "Window")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func openMainWindowRequested() {
        openMainWindow()
    }

    @objc private func showAbout() {
        AboutPanel.show()
    }

    @objc private func chooseWorkspace() {
        openMainWindow()
        NotificationCenter.default.post(name: .chooseWorkspaceRequested, object: nil)
    }

    @objc private func newSession() {
        openMainWindow()
        NotificationCenter.default.post(name: .newSessionRequested, object: nil)
    }

    @objc private func browseSessions() {
        openMainWindow()
        NotificationCenter.default.post(name: .sessionsRequested, object: nil)
    }

    @objc private func stopGeneration() {
        NotificationCenter.default.post(name: .stopGenerationRequested, object: nil)
    }

    @objc private func focusInput() {
        openMainWindow()
        NotificationCenter.default.post(name: .focusInputRequested, object: nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide instead of miniaturize so frame autosave does not persist a dock-icon-sized frame.
        sender.orderOut(nil)
        return false
    }
}
