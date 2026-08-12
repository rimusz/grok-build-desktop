import SwiftUI
import AppKit

/// In-app diagnostics + broken-auth recovery, inspired by Grok-UI's `doctor` panel.
///
/// Collects environment facts (CLI path, version, auth, config.toml, Browser/Computer Use
/// readiness, Node.js for the Cursor bridge, Cursor bridge reachability) via `DoctorInputs`,
/// maps them to rows with the pure `DoctorReport`, and offers remediations: install the grok CLI,
/// run `grok login`, and install Node.js when missing/too old.
struct DoctorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var inputs = DoctorInputs()
    @State private var isRunning = false
    @State private var probeBridges = false

    private var checks: [DoctorCheck] { DoctorReport.checks(from: inputs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let remediation = DoctorReport.primaryRemediation(inputs) {
                remediationBanner(remediation)
            }

            VStack(spacing: 0) {
                ForEach(checks) { check in
                    row(check)
                    if check.id != checks.last?.id { Divider() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.6)))

            Toggle("Probe managed Cursor bridge (127.0.0.1:18787)", isOn: $probeBridges)
                .font(.caption)
                .onChange(of: probeBridges) { _, _ in Task { await run() } }

            HStack {
                Button {
                    Task { await run() }
                } label: {
                    Label(isRunning ? "Checking…" : "Re-run checks", systemImage: "arrow.clockwise")
                }
                .disabled(isRunning)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
        .task { await run() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "stethoscope")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.12)))
            VStack(alignment: .leading, spacing: 4) {
                Text("Doctor")
                    .font(.title3.weight(.semibold))
                Text("Checks your grok CLI setup so parallel sessions start cleanly.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func remediationBanner(_ remediation: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(remediation)
                    .font(.callout.weight(.semibold))
                Text(remediation == "Run grok login"
                     ? "Authenticate the grok CLI, then re-run checks."
                     : "Install the grok CLI from the official docs, then re-run checks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if remediation == "Run grok login" {
                Button("Open Terminal…") { openLoginInTerminal() }
            } else {
                Button("Install guide…") {
                    NSWorkspace.shared.open(URL(string: "https://docs.x.ai/build/overview")!)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.10)))
    }

    private func row(_ check: DoctorCheck) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: check.status.symbolName)
                .foregroundStyle(color(for: check.status))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 6) {
                Text(check.title)
                    .font(.callout.weight(.medium))
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if check.key == "node", check.status == .warning {
                    HStack(spacing: 10) {
                        Button("Install with Homebrew…") { openNodeBrewInstallInTerminal() }
                            .controlSize(.small)
                        Button("nodejs.org…") {
                            NSWorkspace.shared.open(CursorBridge.NodeRequirement.homepageURL)
                        }
                        .buttonStyle(.link)
                        .controlSize(.small)
                    }
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for status: DoctorCheck.Status) -> Color {
        switch status {
        case .ok: return .green
        case .warning: return .orange
        case .failed: return .red
        case .info: return .secondary
        }
    }

    @MainActor
    private func run() async {
        isRunning = true
        defer { isRunning = false }

        let cliURL = GrokCLIService.locateGrokCLI()
        let version = cliURL == nil ? "" : await GrokCLIService.versionDisplayLine()
        let authed = GrokAuthProbe.isLikelyAuthenticated()
        let configPresent = FileManager.default.fileExists(atPath: CustomModelStore.configURL.path)
        let browserEnabled = UserDefaults.standard.bool(forKey: BrowserSettingsKeys.appliedEnabled)
        let computerUseEnabled = UserDefaults.standard.bool(forKey: "grokbuild.computerUse.applied.enabled")
        let node = CursorBridgeRuntime.probeNode()

        var bridgeCount: Int? = nil
        if probeBridges {
            let result = await CursorBridge.probeManaged()
            bridgeCount = result.isOnline ? 1 : 0
        }

        inputs = DoctorInputs(
            cliFound: cliURL != nil,
            versionDisplay: version.replacingOccurrences(of: "grok CLI: ", with: ""),
            authenticated: authed,
            configPresent: configPresent,
            browserEnabled: browserEnabled,
            computerUseEnabled: computerUseEnabled,
            reachableBridgeCount: bridgeCount,
            nodeFound: node.isFound,
            nodeVersionDisplay: node.versionDisplay,
            nodeMeetsMinimum: node.meetsMinimum
        )
    }

    private func openLoginInTerminal() {
        let script = "tell application \"Terminal\" to do script \"grok login\"\ntell application \"Terminal\" to activate"
        if let apple = NSAppleScript(source: script) {
            var err: NSDictionary?
            apple.executeAndReturnError(&err)
        }
    }

    private func openNodeBrewInstallInTerminal() {
        let command = CursorBridge.NodeRequirement.brewInstallCommand
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\" to do script \"\(escaped)\"\ntell application \"Terminal\" to activate"
        if let apple = NSAppleScript(source: script) {
            var err: NSDictionary?
            apple.executeAndReturnError(&err)
        }
    }
}
