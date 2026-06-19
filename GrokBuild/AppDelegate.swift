import AppKit
import SwiftUI
import Darwin   // POSIX: open, O_EXCL, close, write, kill, getpid

class AppDelegate: NSObject, NSApplicationDelegate {
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
        if let appIcon = loadAppIcon() {
            NSApp.applicationIconImage = appIcon
        }

        statusBarController = StatusBarController()
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

        if let content = try? String(contentsOf: pidFile).trimmingCharacters(in: .whitespacesAndNewlines),
           let filePid = Int32(content),
           filePid == getpid() {
            try? FileManager.default.removeItem(at: pidFile)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func openMainWindow() {
        // If a window is already open, just bring it forward
        if let existing = NSApp.windows.first(where: { $0.contentViewController is NSHostingController<ContentView> }) {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = ContentView()
        let hosting = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "GrokBuild"
        window.contentViewController = hosting
        window.setFrameAutosaveName("MainWindow")
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    private func loadAppIcon() -> NSImage? {
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            for name in ["AppIcon.png", "AppIcon.icns"] {
                let path = execDir.appendingPathComponent(name).path
                if FileManager.default.fileExists(atPath: path),
                   let image = NSImage(contentsOfFile: path) {
                    return image
                }
            }
        }

        if let image = NSImage(named: "AppIcon") {
            return image
        }

        for name in ["AppIcon", "AppIcon1024"] {
            if let path = Bundle.main.path(forResource: name, ofType: "png"),
               let image = NSImage(contentsOfFile: path) {
                return image
            }
            if let path = Bundle.main.path(forResource: name, ofType: "icns"),
               let image = NSImage(contentsOfFile: path) {
                return image
            }
        }

        return nil
    }

    @objc private func openMainWindowRequested() {
        openMainWindow()
    }
}
