import Foundation

@MainActor @Observable
final class GrokCLIUpdater {
    static let shared = GrokCLIUpdater()

    enum Phase: Equatable {
        case idle
        case updating
        case success(version: String)
        case failed(message: String, detail: String?)
    }

    private(set) var phase: Phase = .idle

    private init() {}

    var isBusy: Bool {
        if case .updating = phase { return true }
        return false
    }

    func reset() {
        phase = .idle
        notifyPhaseChanged()
    }

    func updateCLI() async {
#if DEBUG
        if UpdateDebugSimulator.isCLISimulationActive {
            await performSimulatedCLIUpdate()
            return
        }
#endif

        let precheck = await UpdateChecker.checkGrokCLI()
        guard precheck.updateAvailable else {
            phase = .failed(message: "No grok CLI update is available.", detail: nil)
            notifyPhaseChanged()
            return
        }

        phase = .updating
        notifyPhaseChanged()

        NotificationCenter.default.post(name: .grokBuildPrepareForShutdown, object: nil)
        try? await Task.sleep(for: .milliseconds(600))

        let service = GrokCLIService()
        let result: GrokCLIResult
        do {
            result = try await service.updateGrokCLI()
        } catch {
            phase = .failed(message: error.localizedDescription, detail: nil)
            notifyPhaseChanged()
            return
        }

        if result.exitCode != 0 {
            let detail = Self.trimmedOutput(result.combinedOutput)
            phase = .failed(
                message: "grok update failed with exit code \(result.exitCode).",
                detail: detail.isEmpty ? nil : detail
            )
            notifyPhaseChanged()
            return
        }

        let postcheck = await UpdateChecker.checkGrokCLI()
        UpdateScheduler.setCachedCLIStatus(postcheck)

        switch postcheck.state {
        case .upToDate(let info):
            phase = .success(version: info.current)
            NotificationCenter.default.post(name: .grokBuildCLIUpdated, object: nil)
            NotificationCenter.default.post(name: .grokBuildUpdateStateChanged, object: nil)
            notifyPhaseChanged()
        case .updateAvailable(let info):
            let detail = Self.trimmedOutput(result.combinedOutput)
            phase = .failed(
                message: "grok update finished but version \(info.current) is still behind \(info.latest).",
                detail: detail.isEmpty ? nil : detail
            )
            notifyPhaseChanged()
        case .notInstalled:
            phase = .failed(message: "grok CLI was not found after updating.", detail: nil)
            notifyPhaseChanged()
        case .checkFailed(let message):
            phase = .failed(message: "Could not verify grok CLI after updating: \(message)", detail: nil)
            notifyPhaseChanged()
        }
    }

    nonisolated static func trimmedOutput(_ value: String, limit: Int = 1200) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "\n…"
    }

    nonisolated static func failureMessage(from result: GrokCLIResult) -> String {
        let detail = trimmedOutput(result.combinedOutput)
        if detail.isEmpty {
            return "grok update failed with exit code \(result.exitCode)."
        }
        return "grok update failed with exit code \(result.exitCode).\n\(detail)"
    }

    private func notifyPhaseChanged() {
        NotificationCenter.default.post(name: .grokBuildCLIUpdaterPhaseChanged, object: self)
    }

#if DEBUG
    private func performSimulatedCLIUpdate() async {
        phase = .updating
        notifyPhaseChanged()

        NotificationCenter.default.post(name: .grokBuildPrepareForShutdown, object: nil)
        try? await Task.sleep(for: .milliseconds(600))
        try? await Task.sleep(for: .seconds(1.2))

        let simulatedVersion = UpdateDebugSimulator.simulatedCLIVersion
        UpdateScheduler.setCachedCLIStatus(UpdateDebugSimulator.simulatedCLIUpToDateStatus())

        phase = .success(version: simulatedVersion)
        NotificationCenter.default.post(name: .grokBuildCLIUpdated, object: nil)
        NotificationCenter.default.post(name: .grokBuildUpdateStateChanged, object: nil)
        notifyPhaseChanged()
    }
#endif
}
