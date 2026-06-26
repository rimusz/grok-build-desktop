import AppKit
import ApplicationServices
import Foundation
import Security

struct ComputerUseBackendStatus: Sendable, Equatable {
    var isInstalled: Bool
    var isReady: Bool
    var executablePath: String?
    var version: String?
    var diagnostic: String

    static let unavailable = ComputerUseBackendStatus(
        isInstalled: false,
        isReady: false,
        executablePath: nil,
        version: nil,
        diagnostic: "agent-desktop is not installed."
    )
}

struct ComputerUsePermissionStatus: Sendable, Equatable {
    var accessibility: String
    var screenRecording: String
    var diagnostic: String
    var guidance: String?

    static let unavailable = ComputerUsePermissionStatus(
        accessibility: "unknown",
        screenRecording: "unknown",
        diagnostic: "Permission status is unavailable until agent-desktop is installed.",
        guidance: nil
    )

    var isReady: Bool {
        accessibility == "granted"
    }
}

struct AccessibilityTrustProbe: Sendable, Equatable {
    var helperGranted: Bool
    var agentDesktopGranted: Bool
    var helperExecutablePath: String
    var agentDesktopOutput: String
    var probeError: String?
}

enum ComputerUseService {
    private struct CommandResult: Sendable {
        var output: String
        var exitCode: Int32
    }

    static func bundledAgentDesktopURL() -> URL? {
        guard let directory = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        let candidate = directory.appendingPathComponent("agent-desktop")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    static func usesBundledAgentDesktop(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) -> Bool {
        guard let bundled = bundledAgentDesktopURL(),
              let resolved = executableURL(settings: settings) else {
            return false
        }
        return resolved.path == bundled.path
    }

    static func executableURL(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) -> URL? {
        let configured = settings.agentDesktopPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            let url = URL(fileURLWithPath: (configured as NSString).expandingTildeInPath)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }

        if let bundled = bundledAgentDesktopURL() {
            return bundled
        }

        if let path = ProcessInfo.processInfo.environment["AGENT_DESKTOP_PATH"], !path.isEmpty {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }

        for candidate in [
            "/opt/homebrew/bin/agent-desktop",
            "/usr/local/bin/agent-desktop",
            "\(NSHomeDirectory())/.local/bin/agent-desktop",
            "\(NSHomeDirectory())/bin/agent-desktop"
        ] where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(directory))
                    .appendingPathComponent("agent-desktop")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }

    static func helperURL() -> URL? {
        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            let candidate = executableDirectory.appendingPathComponent("GrokBuildComputerUseMCP")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        for configuration in ["release", "debug"] {
            var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            for _ in 0..<4 {
                let candidate = directory
                    .appendingPathComponent(".build")
                    .appendingPathComponent(configuration)
                    .appendingPathComponent("GrokBuildComputerUseMCP")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
                directory.deleteLastPathComponent()
            }
        }

        return nil
    }

    static func computerUseMCPConfig(
        settings: ComputerUseSettings = ComputerUseSettingsStore.load(),
        helperOverride: URL? = nil,
        agentDesktopOverride: URL? = nil
    ) -> MCPServerConfig? {
        guard settings.enabled,
              settings.backend == .agentDesktop,
              let helper = helperOverride ?? helperURL() else {
            return nil
        }

        var env: [String: String] = [
            "GROKBUILD_COMPUTER_USE_POLICY": settings.permissionPolicy.rawValue,
            "GROKBUILD_COMPUTER_USE_TIMEOUT": String(settings.commandTimeoutSeconds),
            "GROKBUILD_COMPUTER_USE_MAX_STEPS": String(settings.maxSteps),
            "GROKBUILD_COMPUTER_USE_SCREENSHOTS": settings.includeScreenshots ? "true" : "false",
            "GROKBUILD_COMPUTER_USE_ALLOW_PHYSICAL_MOUSE": settings.allowPhysicalMouse ? "true" : "false",
            "GROKBUILD_COMPUTER_USE_SESSION": normalizedSessionName(settings.sessionName)
        ]

        if let executable = agentDesktopOverride ?? executableURL(settings: settings) {
            env["AGENT_DESKTOP_PATH"] = executable.path
        }

        return MCPServerConfig(
            name: "grokbuild-computer-use",
            transport: .stdio,
            command: helper.path,
            args: [],
            env: env
        )
    }

    static func configurationIssue(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) -> String? {
        guard settings.backend == .agentDesktop else {
            return "Computer Use backend is not configured."
        }
        guard helperURL() != nil else {
            return "Computer Use MCP helper is missing. Rebuild the app."
        }
        guard executableURL(settings: settings) != nil else {
            return "Install agent-desktop first."
        }
        return nil
    }

    static func status(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) async -> ComputerUseBackendStatus {
        guard let executable = executableURL(settings: settings) else { return .unavailable }
        let versionResult = try? await run([executable.path, "version"], timeout: 8)
        let permissionResult = try? await runResult([executable.path, "permissions"], timeout: 8)
        let version = versionResult.flatMap(parseVersion)
        let diagnostic = permissionResult?.output.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "agent-desktop found at \(executable.path)."

        return ComputerUseBackendStatus(
            isInstalled: true,
            isReady: permissionResult?.exitCode == 0,
            executablePath: executable.path,
            version: version?.isEmpty == false ? version : nil,
            diagnostic: diagnostic
        )
    }

    static func permissionStatus(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) async -> ComputerUsePermissionStatus {
        guard executableURL(settings: settings) != nil else { return .unavailable }

        let grokBuildGranted = localAccessibilityGranted()
        let probe = await helperAccessibilityProbe(settings: settings)
        var cliStatus: ComputerUsePermissionStatus

        if let probe, !probe.agentDesktopOutput.isEmpty {
            cliStatus = parsePermissions(probe.agentDesktopOutput)
        } else if let executable = executableURL(settings: settings) {
            do {
                let output = try await run([executable.path, "permissions"], timeout: 8)
                cliStatus = parsePermissions(output)
            } catch {
                cliStatus = ComputerUsePermissionStatus(
                    accessibility: "unknown",
                    screenRecording: "unknown",
                    diagnostic: error.localizedDescription,
                    guidance: nil
                )
            }
        } else {
            cliStatus = .unavailable
        }

        return resolvePermissionStatus(
            cliStatus: cliStatus,
            grokBuildGranted: grokBuildGranted,
            probe: probe,
            settings: settings
        )
    }

    static func localAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    static var runningExecutablePath: String {
        Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.arguments[0]
    }

    static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var bundleIdentifier: String? {
        Bundle.main.bundleIdentifier
    }

    static func helperAccessibilityProbe(
        settings: ComputerUseSettings = ComputerUseSettingsStore.load()
    ) async -> AccessibilityTrustProbe? {
        guard let helper = helperURL(),
              let agentDesktop = executableURL(settings: settings) else {
            return nil
        }

        var environment = ProcessInfo.processInfo.environment
        environment["AGENT_DESKTOP_PATH"] = agentDesktop.path

        do {
            let output = try await run(
                [helper.path, "--check-permissions"],
                timeout: 12,
                environment: environment
            )
            return parseAccessibilityTrustProbe(output)
        } catch {
            return AccessibilityTrustProbe(
                helperGranted: false,
                agentDesktopGranted: false,
                helperExecutablePath: helper.path,
                agentDesktopOutput: "",
                probeError: error.localizedDescription
            )
        }
    }

    static func parseAccessibilityTrustProbe(_ output: String) -> AccessibilityTrustProbe? {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return AccessibilityTrustProbe(
            helperGranted: json["helper_accessibility_granted"] as? Bool ?? false,
            agentDesktopGranted: json["agent_desktop_granted"] as? Bool ?? false,
            helperExecutablePath: json["helper_executable"] as? String ?? "",
            agentDesktopOutput: json["agent_desktop_output"] as? String ?? "",
            probeError: nil
        )
    }

    static func resolvePermissionStatus(
        cliStatus: ComputerUsePermissionStatus,
        grokBuildGranted: Bool,
        probe: AccessibilityTrustProbe?,
        settings: ComputerUseSettings = ComputerUseSettingsStore.load()
    ) -> ComputerUsePermissionStatus {
        let helperGranted = probe?.helperGranted ?? false
        let agentDesktopGranted = probe?.agentDesktopGranted ?? false
        let cliGranted = cliStatus.accessibility == "granted"
        // Bundled agent-desktop is signed with the app bundle id; GrokBuild access is enough.
        let granted: Bool
        if usesBundledAgentDesktop(settings: settings) {
            granted = grokBuildGranted || helperGranted || agentDesktopGranted || cliGranted
        } else {
            granted = agentDesktopGranted || grokBuildGranted || helperGranted || cliGranted
        }

        var resolved = cliStatus
        if granted {
            resolved.accessibility = "granted"
            resolved.guidance = nil
        } else {
            resolved.guidance = accessibilityGuidance(probe: probe, settings: settings)
        }
        resolved.diagnostic = permissionDiagnosticText(
            cliStatus: cliStatus,
            grokBuildGranted: grokBuildGranted,
            probe: probe,
            settings: settings
        )
        return resolved
    }

    static func mergedPermissionStatus(
        _ status: ComputerUsePermissionStatus,
        localAccessibilityGranted: Bool
    ) -> ComputerUsePermissionStatus {
        resolvePermissionStatus(
            cliStatus: status,
            grokBuildGranted: localAccessibilityGranted,
            probe: nil
        )
    }

    static func accessibilityGuidance(
        probe: AccessibilityTrustProbe?,
        settings: ComputerUseSettings = ComputerUseSettingsStore.load()
    ) -> String {
        if usesBundledAgentDesktop(settings: settings) {
            var lines = [
                "Enable \(hostAppName) in System Settings → Privacy & Security → Accessibility.",
                "agent-desktop is bundled inside this app and shares the same permission.",
                "Add this app with the + button:",
                appBundlePath
            ]
            if let cdHash = codeSignatureCDHash() {
                lines.append("If GrokBuild is already listed but still denied, remove it and add again (signature CDHash: \(cdHash.prefix(12))…).")
            } else {
                lines.append("If GrokBuild is already listed but still denied, remove it and add again after `make app`.")
            }
            return lines.joined(separator: "\n")
        }

        let agentDesktopPath = executableURL(settings: settings)?.path ?? "agent-desktop"
        var lines = [
            "Computer Use runs through agent-desktop. In System Settings → Privacy & Security → Accessibility, enable both:",
            "1. \(hostAppName) (this app)",
            "2. agent-desktop at \(agentDesktopPath)"
        ]

        if isBundledApp {
            lines.append(
                "If \(hostAppName) is already listed, remove it and add it again after `make app` — macOS ties permission to the app signature."
            )
        } else {
            lines.append(
                "Running executable: \(runningExecutablePath)"
            )
        }

        if let probe, !probe.helperGranted {
            lines.append("If problems persist, also allow GrokBuildComputerUseMCP.")
        }

        return lines.joined(separator: "\n")
    }

    static func permissionDiagnosticText(
        cliStatus: ComputerUsePermissionStatus,
        grokBuildGranted: Bool,
        probe: AccessibilityTrustProbe?,
        settings: ComputerUseSettings = ComputerUseSettingsStore.load()
    ) -> String {
        let agentDesktopPath = executableURL(settings: settings)?.path ?? "unknown"
        let bundled = usesBundledAgentDesktop(settings: settings)
        var lines = [
            "App bundle: \(appBundlePath)",
            "Running executable: \(runningExecutablePath)",
            "Bundle identifier: \(bundleIdentifier ?? "none")",
            "Bundled app: \(isBundledApp ? "yes" : "no")",
            "agent-desktop path: \(agentDesktopPath)",
            "agent-desktop bundled: \(bundled ? "yes" : "no")",
            "GrokBuild Accessibility: \(grokBuildGranted ? "granted" : "denied")"
        ]

        if let cdHash = codeSignatureCDHash() {
            lines.append("App signature CDHash: \(cdHash)")
        }

        if let probe {
            lines.append("Helper executable: \(probe.helperExecutablePath)")
            lines.append("Helper Accessibility: \(probe.helperGranted ? "granted" : "denied")")
            lines.append("agent-desktop (via helper): \(probe.agentDesktopGranted ? "granted" : "denied")")
            if let probeError = probe.probeError, !probeError.isEmpty {
                lines.append("Helper probe error: \(probeError)")
            }
        }

        if grokBuildGranted || probe?.helperGranted == true || probe?.agentDesktopGranted == true {
            lines.append("Required Accessibility clients are trusted by macOS.")
        }

        let cliText = cliStatus.diagnostic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cliText.isEmpty {
            lines.append("")
            lines.append("agent-desktop output:")
            lines.append(cliText)
        }

        return lines.joined(separator: "\n")
    }

    static func requestPermissions(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) async throws -> String {
        guard executableURL(settings: settings) != nil else {
            throw NSError(
                domain: "ComputerUseService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "agent-desktop is not installed."]
            )
        }

        let grokBuildGranted = await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            return promptForLocalAccessibility()
        }

        var lines = [
            "GrokBuild accessibility: \(grokBuildGranted ? "granted" : "not granted yet")"
        ]

        if usesBundledAgentDesktop(settings: settings) {
            if !grokBuildGranted {
                await MainActor.run { openAccessibilitySettings() }
                lines.append("Opened Accessibility settings.")
                lines.append("Remove any existing GrokBuild entry, click +, and choose:")
                lines.append(appBundlePath)
                if let cdHash = codeSignatureCDHash() {
                    lines.append("Current app signature CDHash: \(cdHash)")
                    lines.append("macOS ties Accessibility to this signature; re-adding is required after each rebuild.")
                }
            }
            return lines.joined(separator: "\n")
        }

        if !grokBuildGranted {
            await MainActor.run { openAccessibilitySettings() }
        }

        if let helper = helperURL(), let agentDesktop = executableURL(settings: settings) {
            var environment = ProcessInfo.processInfo.environment
            environment["AGENT_DESKTOP_PATH"] = agentDesktop.path
            let helperOutput = try await run(
                [helper.path, "--request-permissions"],
                timeout: 30,
                environment: environment
            )
            lines.append(helperOutput)
        } else if let executable = executableURL(settings: settings) {
            let output = try await run([executable.path, "permissions", "--request"], timeout: 30)
            lines.append(output)
        }

        return lines.joined(separator: "\n")
    }

    static var appBundlePath: String {
        Bundle.main.bundleURL.path
    }

    static func codeSignatureCDHash() -> String? {
        let bundleURL = Bundle.main.bundleURL as CFURL
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: 0), &information) == errSecSuccess,
              let info = information as? [String: Any] else {
            return nil
        }

        if let cdHashes = info["cdhashes"] as? [Data], let first = cdHashes.first {
            return first.map { String(format: "%02x", $0) }.joined()
        }

        if let unique = info[kSecCodeInfoUnique as String] as? Data {
            return unique.map { String(format: "%02x", $0) }.joined()
        }

        return nil
    }

    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    @MainActor
    static func promptForLocalAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func openAccessibilitySettings() {
        NSApp.activate(ignoringOtherApps: true)
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            ?? URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    static var hostAppName: String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !name.isEmpty {
            return name
        }
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }
        return "GrokBuild"
    }

    static func commandPreview(_ args: [String], settings: ComputerUseSettings = ComputerUseSettingsStore.load()) -> [String] {
        [executableURL(settings: settings)?.path ?? "agent-desktop"] + args
    }

    static func normalizedSessionName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ComputerUseSettings.defaults.sessionName : trimmed
    }

    static func parseVersion(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return trimmed.isEmpty ? nil : trimmed
        }

        if let data = json["data"] as? [String: Any],
           let version = data["version"] as? String,
           !version.isEmpty {
            return version
        }
        if let version = json["version"] as? String, !version.isEmpty {
            return version
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    static func parsePermissions(_ output: String) -> ComputerUsePermissionStatus {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ComputerUsePermissionStatus(
                accessibility: "unknown",
                screenRecording: "unknown",
                diagnostic: output.isEmpty ? "No permission diagnostics returned." : output,
                guidance: nil
            )
        }

        let payload = (json["data"] as? [String: Any]) ?? json

        func normalizedState(from value: Any?) -> String? {
            switch value {
            case let string as String where !string.isEmpty:
                return string.lowercased()
            case let granted as Bool:
                return granted ? "granted" : "denied"
            default:
                return nil
            }
        }

        func permissionState(for key: String) -> String? {
            if let dict = payload[key] as? [String: Any] {
                return normalizedState(from: dict["state"]) ?? normalizedState(from: dict["granted"])
            }
            return normalizedState(from: payload[key])
        }

        let legacyGranted = normalizedState(from: payload["granted"])
        let hasStructuredScreenRecording = payload["screen_recording"] != nil || payload["screenRecording"] != nil

        let accessibility = permissionState(for: "accessibility")
            ?? legacyGranted
            ?? "unknown"

        let screenRecording: String
        if hasStructuredScreenRecording {
            screenRecording = permissionState(for: "screen_recording")
                ?? permissionState(for: "screenRecording")
                ?? "unknown"
        } else if legacyGranted != nil {
            // agent-desktop v1.0 only reports a combined granted flag.
            screenRecording = "not reported"
        } else {
            screenRecording = "unknown"
        }

        return ComputerUsePermissionStatus(
            accessibility: accessibility,
            screenRecording: screenRecording,
            diagnostic: output,
            guidance: permissionGuidance(accessibility: accessibility, payload: payload)
        )
    }

    static func permissionGuidance(accessibility: String, payload: [String: Any], appName: String = hostAppName) -> String? {
        guard accessibility != "granted" else { return nil }
        if let rewritten = rewritePermissionSuggestion(payload["suggestion"] as? String, appName: appName) {
            return rewritten
        }
        return "Open System Settings → Privacy & Security → Accessibility and enable \(appName)."
    }

    static func rewritePermissionSuggestion(_ suggestion: String?, appName: String) -> String? {
        guard let suggestion else { return nil }
        let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.localizedCaseInsensitiveContains("terminal") {
            return "Open System Settings → Privacy & Security → Accessibility and enable \(appName)."
        }

        return trimmed.replacingOccurrences(
            of: "your terminal application",
            with: appName,
            options: [.caseInsensitive]
        )
    }

    private static func run(_ command: [String], timeout: TimeInterval, environment: [String: String]? = nil) async throws -> String {
        let result = try await runResult(command, timeout: timeout, environment: environment)
        if result.exitCode != 0 {
            throw NSError(
                domain: "ComputerUseService",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: result.output.isEmpty ? "Command failed." : result.output]
            )
        }
        return result.output
    }

    private static func runResult(
        _ command: [String],
        timeout: TimeInterval,
        environment: [String: String]? = nil
    ) async throws -> CommandResult {
        guard let executable = command.first else {
            throw NSError(domain: "ComputerUseService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing command."])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(command.dropFirst())
            if let environment {
                process.environment = environment
            }
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            final class ResumeBox: @unchecked Sendable {
                let lock = NSLock()
                var didResume = false
            }
            let box = ResumeBox()

            @Sendable
            func finish(_ result: Result<CommandResult, Error>) {
                box.lock.lock()
                guard !box.didResume else {
                    box.lock.unlock()
                    return
                }
                box.didResume = true
                box.lock.unlock()
                continuation.resume(with: result)
            }

            process.terminationHandler = { process in
                let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                finish(.success(CommandResult(output: out.isEmpty ? err : out, exitCode: process.terminationStatus)))
            }

            do {
                try process.run()
            } catch {
                finish(.failure(error))
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                    finish(.failure(NSError(
                        domain: "ComputerUseService",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "agent-desktop command timed out."]
                    )))
                }
            }
        }
    }
}
