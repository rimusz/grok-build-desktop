import Foundation

enum UpdateChecker {
    struct AppRelease: Sendable {
        let installedVersion: String
        let latestVersion: String
        let releaseURL: URL
        let updateAvailable: Bool
    }

    struct GrokCLIStatus: Sendable {
        enum State: Sendable {
            case upToDate(current: String, latest: String, channel: String?)
            case updateAvailable(current: String, latest: String, channel: String?)
            case notInstalled
            case checkFailed(String)
        }

        let state: State

        var updateAvailable: Bool {
            if case .updateAvailable = state { return true }
            return false
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private struct GrokUpdateCheckResponse: Decodable {
        let currentVersion: String?
        let latestVersion: String?
        let updateAvailable: Bool?
        let channel: String?
        let error: String?
    }

    static func checkAppRelease() async throws -> AppRelease {
        let release = try await fetchLatestAppRelease()
        let installed = AppVersion.short
        let latest = normalizedVersion(release.tagName)
        return AppRelease(
            installedVersion: installed,
            latestVersion: latest,
            releaseURL: release.htmlURL,
            updateAvailable: compareVersions(latest, installed) == .orderedDescending
        )
    }

    static func checkGrokCLI() async -> GrokCLIStatus {
        do {
            let result = try await GrokCLIService()
                .run(["update", "--check", "--json"], allowFailure: true)

            let payload = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = payload.data(using: .utf8),
                  let response = try? JSONDecoder().decode(GrokUpdateCheckResponse.self, from: data) else {
                let detail = [result.stdout, result.stderr]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                let message = detail.isEmpty ? "Could not parse grok update check output." : detail
                return GrokCLIStatus(state: .checkFailed(message))
            }

            if let error = response.error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
                return GrokCLIStatus(state: .checkFailed(error))
            }

            let current = response.currentVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let latest = response.latestVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !current.isEmpty, !latest.isEmpty else {
                return GrokCLIStatus(state: .checkFailed("grok update --check did not return version information."))
            }

            let channel = response.channel?.trimmingCharacters(in: .whitespacesAndNewlines)
            if response.updateAvailable == true {
                return GrokCLIStatus(state: .updateAvailable(current: current, latest: latest, channel: channel))
            }
            return GrokCLIStatus(state: .upToDate(current: current, latest: latest, channel: channel))
        } catch GrokCLIService.CLIError.notFound {
            return GrokCLIStatus(state: .notInstalled)
        } catch {
            return GrokCLIStatus(state: .checkFailed(error.localizedDescription))
        }
    }

    private static func fetchLatestAppRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/rimusz/grok-build-desktop/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "GrokBuildUpdates",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not fetch the latest GrokBuild release from GitHub."]
            )
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    static func normalizedVersion(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[vV]"#, with: "", options: .regularExpression)
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
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

    private static func versionComponents(_ value: String) -> [Int] {
        normalizedVersion(value)
            .split(separator: ".")
            .map { component in
                let numericPrefix = component.prefix { $0.isNumber }
                return Int(numericPrefix) ?? 0
            }
    }
}
