import AppKit
import Foundation

@MainActor @Observable
final class AppUpdater {
    static let shared = AppUpdater()

    enum Phase: Equatable {
        case idle
        case downloading(progress: Double)
        case verifying
        case readyToInstall(extractedAppURL: URL, version: String)
        case installing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private var activeRelease: UpdateChecker.AppRelease?
    private var downloadTask: URLSessionDownloadTask?
    private var downloadObservation: NSKeyValueObservation?

    private init() {}

    var isBusy: Bool {
        switch phase {
        case .idle, .failed, .readyToInstall:
            return false
        case .downloading, .verifying, .installing:
            return true
        }
    }

    func reset() {
        cancelDownload()
        phase = .idle
        activeRelease = nil
    }

    func downloadAndVerify(release: UpdateChecker.AppRelease) async {
#if DEBUG
        if UpdateDebugSimulator.isAppSimulationActive
            || UpdateDebugSimulator.isSimulatedAppRelease(release) {
            await performSimulatedDownloadAndVerify(release: release)
            return
        }
#endif

        guard release.canInstallInApp, let downloadURL = release.downloadURL else {
            phase = .failed("No installable release asset was found.")
            notifyPhaseChanged()
            return
        }

        activeRelease = release
        phase = .downloading(progress: 0)
        notifyPhaseChanged()

        let updatesRoot = Self.updatesDirectory()
        do {
            try FileManager.default.createDirectory(at: updatesRoot, withIntermediateDirectories: true)
            try Self.cleanupOldDownloads(in: updatesRoot, keepingVersion: release.latestVersion)

            let zipURL = updatesRoot.appendingPathComponent("\(UpdateChecker.appName)-\(release.tagName).app.zip")
            if FileManager.default.fileExists(atPath: zipURL.path) {
                try FileManager.default.removeItem(at: zipURL)
            }

            try await downloadFile(from: downloadURL, to: zipURL)

            phase = .verifying
            notifyPhaseChanged()

            let extractedApp = try await verifyAndExtract(zipURL: zipURL, version: release.latestVersion)
            phase = .readyToInstall(extractedAppURL: extractedApp, version: release.latestVersion)
            notifyPhaseChanged()
        } catch {
            phase = .failed(error.localizedDescription)
            notifyPhaseChanged()
        }
    }

    func installAndRestart(extractedAppURL: URL) {
#if DEBUG
        if UpdateDebugSimulator.isAppSimulationActive
            || (activeRelease.map(UpdateDebugSimulator.isSimulatedAppRelease) == true) {
            performSimulatedInstall()
            return
        }
#endif

        let targetURL = Bundle.main.bundleURL

        guard Self.isInstallTargetWritable(targetURL) else {
            phase = .failed("Cannot update GrokBuild at its current location. Move the app to /Applications and try again.")
            notifyPhaseChanged()
            return
        }

        guard let helper = Self.installHelperURL() else {
            phase = .failed("Install helper script is missing from the app bundle.")
            notifyPhaseChanged()
            return
        }

        phase = .installing
        notifyPhaseChanged()

        NotificationCenter.default.post(name: .grokBuildPrepareForShutdown, object: nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            helper.path,
            "--target", targetURL.path,
            "--new-app", extractedAppURL.path,
            "--pid", String(getpid()),
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            phase = .failed("Could not launch install helper: \(error.localizedDescription)")
            notifyPhaseChanged()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }

    func cancelDownload() {
        downloadObservation?.invalidate()
        downloadObservation = nil
        downloadTask?.cancel()
        downloadTask = nil
    }

    private func downloadFile(from url: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let session = URLSession(configuration: .ephemeral)
            let task = session.downloadTask(with: url) { [weak self] tempURL, _, error in
                Task { @MainActor in
                    self?.downloadObservation?.invalidate()
                    self?.downloadObservation = nil
                    self?.downloadTask = nil
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tempURL else {
                    continuation.resume(throwing: NSError(
                        domain: "GrokBuildUpdater",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Download failed."]
                    ))
                    return
                }

                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            downloadTask = task
            downloadObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if case .downloading = self.phase {
                        self.phase = .downloading(progress: progress.fractionCompleted)
                        self.notifyPhaseChanged()
                    }
                }
            }
            task.resume()
        }
    }

    private func verifyAndExtract(zipURL: URL, version: String) async throws -> URL {
        let extractRoot = Self.updatesDirectory()
            .appendingPathComponent("extract-\(version)", isDirectory: true)

        if FileManager.default.fileExists(atPath: extractRoot.path) {
            try FileManager.default.removeItem(at: extractRoot)
        }
        try FileManager.default.createDirectory(at: extractRoot, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zipURL.path, extractRoot.path]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let detail = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw Self.updaterError("Could not extract update archive.\n\(detail)")
        }

        guard let appURL = Self.findAppBundle(in: extractRoot) else {
            throw Self.updaterError("Downloaded archive did not contain GrokBuild.app.")
        }

        try Self.verifySignature(for: appURL)
        return appURL
    }

    private static func findAppBundle(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        if directory.pathExtension == "app" {
            return directory
        }

        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        if let direct = entries.first(where: { $0.lastPathComponent == "\(UpdateChecker.appName).app" }) {
            return direct
        }
        return entries.first(where: { $0.pathExtension == "app" })
    }

    private static func verifySignature(for appURL: URL) throws {
        let codesign = try runCommand("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", appURL.path])
        if codesign.exitCode != 0 {
            throw updaterError("Update failed code signature verification.\n\(codesign.output)")
        }

        let spctl = try runCommand("/usr/sbin/spctl", ["-a", "-t", "exec", "-vv", appURL.path])
        if spctl.exitCode != 0 {
            throw updaterError("Update failed Gatekeeper assessment.\n\(spctl.output)")
        }

        if let installedTeamID = teamIdentifier(for: Bundle.main.bundleURL),
           !installedTeamID.isEmpty,
           let updateTeamID = teamIdentifier(for: appURL),
           !updateTeamID.isEmpty,
           installedTeamID != updateTeamID {
            throw updaterError("Update was signed by a different developer (\(updateTeamID)) than the installed app (\(installedTeamID)).")
        }
    }

    static func teamIdentifier(for appURL: URL) -> String? {
        guard let result = try? runCommand("/usr/bin/codesign", ["-dv", "--verbose=4", appURL.path]) else {
            return nil
        }
        for line in result.output.components(separatedBy: .newlines) {
            if line.hasPrefix("TeamIdentifier=") {
                let value = line.replacingOccurrences(of: "TeamIdentifier=", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value == "not set" ? nil : value
            }
        }
        return nil
    }

    static func installHelperURL() -> URL? {
        if let resource = Bundle.main.url(forResource: "grokbuild-install-update", withExtension: nil) {
            return resource
        }

        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<4 {
            let candidate = directory
                .appendingPathComponent("..")
                .appendingPathComponent("scripts")
                .appendingPathComponent("grokbuild-install-update.sh")
                .standardized
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }

        return nil
    }

    static func updatesDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GrokBuild", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
    }

    static func isInstallTargetWritable(_ targetURL: URL) -> Bool {
        if let values = try? targetURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]),
           values.volumeIsReadOnly == true {
            return false
        }

        let parent = targetURL.deletingLastPathComponent()
        return FileManager.default.isWritableFile(atPath: parent.path)
    }

    private static func cleanupOldDownloads(in directory: URL, keepingVersion: String) throws {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }

        for entry in entries {
            let name = entry.lastPathComponent
            if name.contains(keepingVersion) { continue }
            if name.hasSuffix(".app.zip") || name.hasPrefix("extract-") {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    private static func runCommand(_ launchPath: String, _ arguments: [String]) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    private static func updaterError(_ message: String) -> NSError {
        NSError(domain: "GrokBuildUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func notifyPhaseChanged() {
        NotificationCenter.default.post(name: .grokBuildUpdaterPhaseChanged, object: self)
    }

#if DEBUG
    private func performSimulatedDownloadAndVerify(release: UpdateChecker.AppRelease) async {
        activeRelease = release
        phase = .downloading(progress: 0)
        notifyPhaseChanged()

        for step in 1...10 {
            try? await Task.sleep(for: .milliseconds(120))
            phase = .downloading(progress: Double(step) / 10.0)
            notifyPhaseChanged()
        }

        phase = .verifying
        notifyPhaseChanged()
        try? await Task.sleep(for: .milliseconds(700))

        phase = .readyToInstall(extractedAppURL: Bundle.main.bundleURL, version: release.latestVersion)
        notifyPhaseChanged()
    }

    private func performSimulatedInstall() {
        let targetURL = Bundle.main.bundleURL

        guard let helper = Self.installHelperURL() else {
            phase = .failed("Install helper script is missing from the app bundle.")
            notifyPhaseChanged()
            return
        }

        phase = .installing
        notifyPhaseChanged()

        NotificationCenter.default.post(name: .grokBuildPrepareForShutdown, object: nil)

        UpdateSettingsStore.skipVersion(UpdateDebugSimulator.simulatedAppVersion)
        UpdateDebugSimulator.clearSimulationFlags()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            helper.path,
            "--relaunch-only",
            "--target", targetURL.path,
            "--pid", String(getpid()),
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            phase = .failed("Could not launch install helper: \(error.localizedDescription)")
            notifyPhaseChanged()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }
#endif
}
