import Foundation

/// Pure helpers for GrokBuild’s managed Cursor OpenAI bridge (`CursorBridgeRuntime` on port `18787`).
///
/// Probes `GET /v1/models` and maps advertised model ids into `CustomModelStore` entries
/// (`base_url` + `api_backend`). Unit-testable without a live sidecar.
enum CursorBridge {
    /// Loopback endpoint for the managed sidecar.
    struct Endpoint: Identifiable, Hashable, Sendable {
        /// Loopback base URL including the `/v1` suffix, e.g. `http://127.0.0.1:18787/v1`.
        var baseURL: String
        /// Human label shown in diagnostics.
        var label: String
        /// Project tag for logs / help text.
        var project: String

        var id: String { baseURL }

        /// TCP port parsed from the base URL, when present.
        var port: Int? { CursorBridge.port(from: baseURL) }
    }

    /// The only supported local bridge endpoint (GrokBuild-managed sidecar).
    static let managedEndpoint = Endpoint(
        baseURL: "http://127.0.0.1:18787/v1",
        label: "GrokBuild managed",
        project: "grokbuild/cursor-bridge"
    )

    /// The default api_backend for the Cursor bridge (OpenAI `chat.completions`).
    static let defaultAPIBackend: ModelAPIBackend = .chatCompletions

    /// Result of validating a Cursor API key before save / bridge start.
    struct APIKeyValidation: Equatable, Sendable {
        var isValid: Bool
        var message: String

        static let missing = APIKeyValidation(
            isValid: false,
            message: "A Cursor API key is required to install the Cursor bridge."
        )

        static func rejected(_ detail: String = "") -> APIKeyValidation {
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return APIKeyValidation(
                    isValid: false,
                    message: "Cursor API key was rejected. Paste a valid key from cursor.com/dashboard → Integrations."
                )
            }
            return APIKeyValidation(
                isValid: false,
                message: "Cursor API key was rejected: \(trimmed)"
            )
        }

        static let ok = APIKeyValidation(isValid: true, message: "API key accepted.")
    }

    /// True when the draft looks like a non-empty Cursor key candidate (not a full auth check).
    static func looksLikeAPIKey(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return false }
        // Cursor dashboard keys commonly use a `key_` prefix; still allow other long tokens.
        if trimmed.hasPrefix("key_") { return true }
        return trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }

    /// Maps the validate-key script exit code + stderr into a structured result (pure).
    static func validationResult(exitCode: Int32, stderr: String) -> APIKeyValidation {
        switch exitCode {
        case 0:
            return .ok
        case 2:
            return .missing
        default:
            return .rejected(NodeTLS.userFacingRejection(stderr))
        }
    }

    /// Node's TLS store (not the macOS keychain). Dock/`open` launches omit shell vars such as
    /// `NODE_EXTRA_CA_CERTS`, so Zscaler SSL inspection fails with "Network request failed"
    /// while URLSession providers (MiniMax, Cline) still work.
    enum NodeTLS {
        static let extraCACertsKey = "NODE_EXTRA_CA_CERTS"
        static let overrideKey = "GROKBUILD_NODE_EXTRA_CA_CERTS"

        /// Common IT / Zscaler PEM locations. First existing file wins.
        static func wellKnownPEMPaths(home: String) -> [String] {
            [
                "\(home)/IT-Certs/package-route.pem",
                "\(home)/IT-Certs/ZscalerRootCA.pem",
                "\(home)/IT-Certs/zscaler.pem",
                "\(home)/.zscaler/cert.pem",
            ]
        }

        static func resolvedExtraCACertsPath(
            environment: [String: String],
            home: String,
            fileExists: (String) -> Bool
        ) -> String? {
            func valid(_ raw: String?) -> String? {
                let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !trimmed.isEmpty, fileExists(trimmed) else { return nil }
                return trimmed
            }
            if let existing = valid(environment[extraCACertsKey]) { return existing }
            if let override = valid(environment[overrideKey]) { return override }
            return wellKnownPEMPaths(home: home).first { fileExists($0) }
        }

        static func apply(
            to environment: inout [String: String],
            home: String = NSHomeDirectory(),
            fileExists: (String) -> Bool = { FileManager.default.isReadableFile(atPath: $0) }
        ) {
            guard let path = resolvedExtraCACertsPath(
                environment: environment,
                home: home,
                fileExists: fileExists
            ) else { return }
            environment[extraCACertsKey] = path
        }

        /// Appends a TLS-proxy hint when Node reports a generic fetch failure.
        static func userFacingRejection(_ stderr: String) -> String {
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.localizedCaseInsensitiveContains("Network request failed") else {
                return trimmed
            }
            let hint = "Corporate TLS proxy such as Zscaler: Node does not use the macOS keychain — GrokBuild looks for ~/IT-Certs/package-route.pem or NODE_EXTRA_CA_CERTS / GROKBUILD_NODE_EXTRA_CA_CERTS."
            return "\(trimmed)\n\(hint)"
        }
    }

    /// Node.js requirement for the managed Cursor sidecar (`@cursor/sdk`).
    enum NodeRequirement {
        static let minimumMajor = 22
        static let minimumMinor = 13
        /// Official installers / package managers.
        static let homepageURL = URL(string: "https://nodejs.org/")!
        /// Homebrew one-liner shown / run when Node is missing or too old.
        static let brewInstallCommand = "brew install node"

        /// Pure snapshot used by Doctor / Settings (assembled after probing).
        struct Snapshot: Equatable, Sendable {
            /// Absolute path when a `node` binary was found.
            var binaryPath: String?
            /// Raw `node --version` text (e.g. `v22.14.0`), empty when unknown.
            var versionDisplay: String
            var meetsMinimum: Bool

            var isFound: Bool { binaryPath != nil }

            /// One-line detail for Doctor / Settings banners.
            var detail: String {
                NodeRequirement.detail(
                    found: isFound,
                    versionDisplay: versionDisplay,
                    meetsMinimum: meetsMinimum
                )
            }
        }

        /// Parses `v22.14.0`, `22.14.0`, or leading noise into major/minor/patch.
        static func parseVersion(_ string: String) -> (major: Int, minor: Int, patch: Int)? {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let withoutV = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
                ? String(trimmed.dropFirst())
                : trimmed
            let numeric = withoutV.split(whereSeparator: { !$0.isNumber && $0 != "." }).first.map(String.init) ?? withoutV
            let parts = numeric.split(separator: ".").compactMap { Int($0) }
            guard let major = parts.first else { return nil }
            let minor = parts.count > 1 ? parts[1] : 0
            let patch = parts.count > 2 ? parts[2] : 0
            return (major, minor, patch)
        }

        static func meetsMinimum(major: Int, minor: Int, patch: Int = 0) -> Bool {
            if major > minimumMajor { return true }
            if major < minimumMajor { return false }
            if minor > minimumMinor { return true }
            if minor < minimumMinor { return false }
            return patch >= 0
        }

        static func meetsMinimum(versionString: String) -> Bool {
            guard let parsed = parseVersion(versionString) else { return false }
            return meetsMinimum(major: parsed.major, minor: parsed.minor, patch: parsed.patch)
        }

        static func detail(found: Bool, versionDisplay: String, meetsMinimum: Bool) -> String {
            if !found {
                return "Not found — install Node.js \(minimumMajor).\(minimumMinor)+ (Homebrew: \(brewInstallCommand), or nodejs.org)."
            }
            if versionDisplay.isEmpty {
                return "Found, but version could not be read — need \(minimumMajor).\(minimumMinor)+."
            }
            if meetsMinimum {
                return "\(versionDisplay) (meets \(minimumMajor).\(minimumMinor)+)."
            }
            return "\(versionDisplay) is too old — need Node.js \(minimumMajor).\(minimumMinor)+ (Homebrew: \(brewInstallCommand), or nodejs.org)."
        }

        static func snapshot(binaryPath: String?, versionDisplay: String) -> Snapshot {
            let meets: Bool
            if binaryPath == nil {
                meets = false
            } else if versionDisplay.isEmpty {
                meets = false
            } else {
                meets = meetsMinimum(versionString: versionDisplay)
            }
            return Snapshot(binaryPath: binaryPath, versionDisplay: versionDisplay, meetsMinimum: meets)
        }
    }

    /// Builds the `/models` probe URL from a bridge base URL, preserving the `/v1` suffix.
    static func modelsURL(for baseURL: String) -> URL? {
        ProviderModelFetcher.modelsURL(for: baseURL)
    }

    /// Extracts the TCP port from a base URL like `http://127.0.0.1:18787/v1`.
    static func port(from baseURL: String) -> Int? {
        guard let components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return components.port
    }

    /// True when a base URL points at loopback.
    static func isLoopback(_ baseURL: String) -> Bool {
        let lower = baseURL.lowercased()
        return lower.contains("127.0.0.1") || lower.contains("localhost") || lower.contains("[::1]")
    }

    /// Catalog ids that are Cursor routing aliases, not real selectable models.
    static let excludedCatalogIDs: Set<String> = ["default", "auto", "auto-smart"]

    /// True when a catalog id should not appear in Fetch / Add model pickers.
    static func isExcludedCatalogID(_ modelID: String) -> Bool {
        excludedCatalogIDs.contains(modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Drops routing aliases (`default`, `auto`, `auto-smart`) from a fetched catalog.
    static func filterCatalog(_ models: [FetchedModel]) -> [FetchedModel] {
        models.filter { !isExcludedCatalogID($0.id) }
    }

    /// Parses an OpenAI `/v1/models` payload into selectable model ids (reuses the shared parser).
    static func parseModelIDs(_ data: Data) -> [String] {
        (ProviderModelFetcher.parse(data) ?? [])
            .map(\.id)
            .filter { !isExcludedCatalogID($0) }
    }

    /// Derives a de-duplicated, valid `[model.<id>]` table key for a bridged model id.
    static func importID(for modelID: String) -> String {
        let base = CustomModel.suggestedID(from: modelID)
        guard !base.isEmpty else { return "" }
        return base.hasPrefix("cursor-") ? base : "cursor-\(base)"
    }

    /// Maps the managed endpoint + advertised model id into a ready-to-save `CustomModel`.
    ///
    /// Inference-only: grok keeps its ACP tools; the bridge only serves completions.
    static func makeModel(modelID: String, endpoint: Endpoint = managedEndpoint) -> CustomModel {
        CustomModel(
            id: importID(for: modelID),
            model: modelID,
            baseURL: endpoint.baseURL,
            name: displayName(for: modelID),
            apiKey: "local",
            providerID: ProviderPreset.cursor.provider.id,
            apiBackend: defaultAPIBackend
        )
    }

    /// Display name like Cline’s pattern: `composer-2.5` → `Cursor Composer 2.5`.
    static func displayName(for modelID: String) -> String {
        let slug = modelID.split(separator: "/").last.map(String.init) ?? modelID
        let label = slug
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { part -> String in
                let token = String(part)
                if token.allSatisfy({ $0.isNumber || $0 == "." }) { return token }
                return token.prefix(1).uppercased() + token.dropFirst()
            }
            .joined(separator: " ")
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Cursor" }
        if trimmed.lowercased().hasPrefix("cursor ") { return trimmed }
        return "Cursor \(trimmed)"
    }

    /// Result of probing the managed endpoint.
    struct ProbeResult: Sendable, Equatable {
        var endpoint: Endpoint
        var isOnline: Bool
        var modelIDs: [String]
        var errorDescription: String?
    }

    /// Probes one endpoint's `/v1/models`. Short timeout so an offline bridge fails fast.
    static func probe(_ endpoint: Endpoint, timeout: TimeInterval = 3) async -> ProbeResult {
        guard let url = modelsURL(for: endpoint.baseURL) else {
            return ProbeResult(endpoint: endpoint, isOnline: false, modelIDs: [], errorDescription: "Invalid endpoint URL.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return ProbeResult(endpoint: endpoint, isOnline: false, modelIDs: [],
                                   errorDescription: "HTTP \(http.statusCode)")
            }
            let ids = parseModelIDs(data)
            return ProbeResult(endpoint: endpoint, isOnline: !ids.isEmpty, modelIDs: ids,
                               errorDescription: ids.isEmpty ? "No models returned." : nil)
        } catch {
            return ProbeResult(endpoint: endpoint, isOnline: false, modelIDs: [],
                               errorDescription: error.localizedDescription)
        }
    }

    /// Probes the managed GrokBuild sidecar on port `18787`.
    static func probeManaged(timeout: TimeInterval = 3) async -> ProbeResult {
        await probe(managedEndpoint, timeout: timeout)
    }
}
