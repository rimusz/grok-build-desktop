import Foundation

/// The HTTP wire format grok uses to talk to a custom model's backend.
///
/// Maps to the `api_backend` key in a `[model.<id>]` table. Most OpenAI-compatible endpoints
/// (including the Cursor localhost bridges) use `chat_completions`; the OpenAI Responses API and
/// Anthropic Messages API are the other shapes grok understands. Kept as a small enum so the
/// Models UI can offer a picker and the TOML round-trip stays lossless.
enum ModelAPIBackend: String, CaseIterable, Identifiable, Sendable {
    case chatCompletions = "chat_completions"
    case responses = "responses"
    case messages = "messages"

    var id: String { rawValue }

    /// The default backend when a `[model.<id>]` table omits `api_backend`.
    static let `default`: ModelAPIBackend = .chatCompletions

    var displayName: String {
        switch self {
        case .chatCompletions: return "OpenAI Chat Completions"
        case .responses: return "OpenAI Responses"
        case .messages: return "Anthropic Messages"
        }
    }

    /// Parses a TOML value into a backend, defaulting when absent or unrecognized.
    static func parse(_ value: String?) -> ModelAPIBackend {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return .default }
        return ModelAPIBackend(rawValue: raw) ?? .default
    }
}

/// A user-defined OpenAI-compatible model entry for `~/.grok/config.toml`.
///
/// Maps to a `[model.<id>]` table, e.g.
/// ```toml
/// [model.zai-glm]
/// model = "glm-5.2"
/// base_url = "https://api.z.ai/api/coding/paas/v4"
/// name = "Z.ai GLM-5.2"
/// api_key = "sk-..."
/// ```
///
/// Grok resolves credentials per model in this priority order:
/// `api_key` > active session token > `XAI_API_KEY`.
struct CustomModel: Identifiable, Hashable, Sendable {
    /// The TOML table key (`[model.<id>]`). Used with `/model <id>` and `grok -m <id>`.
    var id: String
    /// The provider model name (e.g. `glm-5.2`, `minimax-m2.5`).
    var model: String
    /// OpenAI-compatible base URL.
    var baseURL: String
    /// Human-friendly display name. Optional.
    var name: String
    /// API key stored inline in config.toml. Empty for local/open servers.
    var apiKey: String
    /// Optional context-window size GrokBuild uses when the CLI does not advertise one.
    var contextTokens: Int?
    /// Whether GrokBuild should expose the reasoning-effort control for this model.
    /// Opt-out: defaults to `true` (both for new models and for existing config.toml
    /// entries missing the `grokbuild_supports_reasoning_effort` key) so the control keeps
    /// showing unless the user explicitly disables it.
    var supportsReasoningEffort: Bool
    /// Whether the provider model can accept image inputs.
    var supportsVision: Bool
    /// Whether GrokBuild should expect/display model thinking blocks for this model.
    var supportsThinkingDisplay: Bool
    /// Optional link to a saved `Provider`. GrokBuild-only; the endpoint/credential are still
    /// written into this model's own `[model.<id>]` table so the Grok CLI can read them.
    var providerID: String?
    /// The HTTP wire format grok uses for this model (`api_backend` in config.toml).
    var apiBackend: ModelAPIBackend
    /// Optional environment-variable name holding the API key (`env_key` in config.toml). Lets a
    /// user keep the secret out of the file (BYOK) while grok resolves it at launch.
    var envKey: String

    init(
        id: String,
        model: String,
        baseURL: String,
        name: String = "",
        apiKey: String = "",
        contextTokens: Int? = nil,
        supportsReasoningEffort: Bool = true,
        supportsVision: Bool = false,
        supportsThinkingDisplay: Bool = false,
        providerID: String? = nil,
        apiBackend: ModelAPIBackend = .default,
        envKey: String = ""
    ) {
        self.id = id
        self.model = model
        self.baseURL = baseURL
        self.name = name
        self.apiKey = apiKey
        self.contextTokens = contextTokens
        self.supportsReasoningEffort = supportsReasoningEffort
        self.supportsVision = supportsVision
        self.supportsThinkingDisplay = supportsThinkingDisplay
        self.providerID = providerID
        self.apiBackend = apiBackend
        self.envKey = envKey
    }

    /// `true` when this looks like a local/self-hosted endpoint that needs no API key.
    var isLocalEndpoint: Bool {
        let lower = baseURL.lowercased()
        return lower.contains("localhost")
            || lower.contains("127.0.0.1")
            || lower.contains("0.0.0.0")
            || lower.contains("host.docker.internal")
    }

    /// `true` when an inline API key is stored in config.toml.
    var hasInlineKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// A short, redacted preview of the inline key for display (e.g. `sk-1…ab9f`).
    var maskedKeyPreview: String {
        Self.mask(apiKey)
    }

    /// Redacts a secret, keeping a few leading/trailing characters for recognizability.
    static func mask(_ secret: String) -> String {
        let trimmed = secret.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= 8 { return String(repeating: "•", count: trimmed.count) }
        let prefix = trimmed.prefix(4)
        let suffix = trimmed.suffix(4)
        return "\(prefix)…\(suffix)"
    }

    /// Derives a valid `[model.<id>]` table key from a provider model name.
    /// Characters outside letters, numbers, dots, dashes, and underscores become dashes.
    static func suggestedID(from modelName: String) -> String {
        let trimmed = modelName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        var result = ""
        var lastWasSeparator = false
        for char in trimmed {
            if char.isLetter || char.isNumber || char == "." || char == "_" || char == "-" {
                result.append(char)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                result.append("-")
                lastWasSeparator = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-.")).lowercased()
    }

    /// A validation error message, or nil when the entry is well-formed.
    var validationError: String? {
        let trimmedID = id.trimmingCharacters(in: .whitespaces)
        if trimmedID.isEmpty { return "Model id is required." }
        if trimmedID.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) == nil {
            return "Model id may only contain letters, numbers, dots, dashes, and underscores."
        }
        if model.trimmingCharacters(in: .whitespaces).isEmpty { return "Model name is required." }
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespaces)
        if trimmedURL.isEmpty { return "Base URL is required." }
        if !(trimmedURL.hasPrefix("http://") || trimmedURL.hasPrefix("https://")) {
            return "Base URL must start with http:// or https://."
        }
        if let contextTokens, contextTokens <= 0 {
            return "Context window must be greater than zero."
        }
        return nil
    }

    /// Returns a copy with endpoint/credentials filled in from a linked provider.
    ///
    /// A provider acts as the source of truth for the shared `base_url`. For the credential,
    /// the provider only overrides the model when it actually carries an inline `api_key`;
    /// otherwise the model keeps its own. This prevents a provider with no key from wiping a
    /// key already stored on the model.
    func resolved(using providers: [Provider]) -> CustomModel {
        guard let providerID,
              let provider = providers.first(where: { $0.id == providerID }) else {
            return self
        }
        var copy = self
        copy.baseURL = provider.baseURL
        if !provider.apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            copy.apiKey = provider.apiKey
        }
        return copy
    }
}

/// A reusable OpenAI-compatible provider: a base URL plus a shared credential.
///
/// Providers are a GrokBuild-side convenience so several models can share one endpoint and
/// API key (e.g. `glm-5.2` and `glm-4.7` both via Z.ai). They are persisted in `UserDefaults`,
/// not in config.toml — when a model is saved, the resolved endpoint/credential are copied into
/// that model's own `[model.<id>]` table.
struct Provider: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var baseURL: String
    var apiKey: String
    /// A suggested default model id for this provider (used when adding a model from the provider).
    var suggestedModel: String

    init(id: String, name: String, baseURL: String, apiKey: String = "", suggestedModel: String = "") {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.suggestedModel = suggestedModel
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, baseURL, apiKey, suggestedModel
    }

    var isLocalEndpoint: Bool {
        let lower = baseURL.lowercased()
        return lower.contains("localhost")
            || lower.contains("127.0.0.1")
            || lower.contains("0.0.0.0")
            || lower.contains("host.docker.internal")
    }

    var hasInlineKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    var maskedKeyPreview: String { CustomModel.mask(apiKey) }

    var validationError: String? {
        if id.trimmingCharacters(in: .whitespaces).isEmpty { return "Provider id is required." }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Provider name is required." }
        let url = baseURL.trimmingCharacters(in: .whitespaces)
        if url.isEmpty { return "Base URL is required." }
        if !(url.hasPrefix("http://") || url.hasPrefix("https://")) {
            return "Base URL must start with http:// or https://."
        }
        return nil
    }
}

/// Fill-in examples for **Settings → Models → Create custom provider…** (not built-in presets).
enum CustomProviderExample {
    /// NVIDIA DGX Spark serving DeepSeek over Tailscale. Hostname is machine-specific, so this
    /// is an editor example rather than a `ProviderPreset`. Spark (and similar LAN servers) ignore
    /// the dummy key; Fetch still requires one because `http://spark:…` is not treated as local.
    static let sparkDeepSeek = Provider(
        id: "spark-deepseek",
        name: "Spark DeepSeek",
        baseURL: "http://spark:8001/v1",
        apiKey: "not-needed",
        suggestedModel: "deepseek-v4-flash"
    )

    static let dummyKeyHelp =
        "Use a dummy key. Fetch models skips the key only for loopback URLs (localhost, 127.0.0.1, 0.0.0.0, host.docker.internal). LAN or Tailscale hosts like http://spark:… need a dummy key so Fetch is enabled. Spark ignores it."

    static let sparkExampleSummary =
        "Example — local NVIDIA DGX Spark (one model at a time). DeepSeek on :8001:"
}

/// Built-in provider presets for popular OpenAI-compatible endpoints.
enum ProviderPreset: String, CaseIterable, Identifiable {
    /// GrokBuild-managed Cursor OpenAI sidecar (local Node/`@cursor/sdk` on port 18787).
    case cursor
    case openai
    case zai
    case minimax
    case kimi
    case qwen
    case xiaomiMiMo
    case deepseek
    case ollama
    case clinePass

    var id: String { rawValue }

    /// Finds the built-in preset whose provider id matches an installed provider.
    static func matching(provider: Provider) -> ProviderPreset? {
        allCases.first { $0.provider.id == provider.id }
    }

    var displayName: String {
        switch self {
        case .cursor: return "Cursor"
        case .openai: return "ChatGPT (OpenAI)"
        case .zai: return "Z.ai (GLM)"
        case .minimax: return "MiniMax"
        case .kimi: return "Kimi (Moonshot)"
        case .qwen: return "Qwen (DashScope)"
        case .xiaomiMiMo: return "Xiaomi MiMo"
        case .deepseek: return "DeepSeek"
        case .ollama: return "Ollama (local)"
        case .clinePass: return "Cline Pass"
        }
    }

    /// True when this preset is the GrokBuild-managed Cursor sidecar (local secret + process lifecycle).
    var isManagedCursorBridge: Bool { self == .cursor }

    /// Whether GrokBuild can discover models via `GET {base_url}/models`.
    var supportsModelListingFetch: Bool {
        switch self {
        case .clinePass: return false
        default: return true
        }
    }

    /// Whether GrokBuild fetches this provider's models from Cline's public recommended-models
    /// feed (no API key required) instead of `{base_url}/models`.
    var supportsLiveCatalogRefresh: Bool {
        switch self {
        case .clinePass: return true
        default: return false
        }
    }

    var catalogDocumentationURL: URL? {
        switch self {
        case .cursor:
            // No Settings deep-link — key is pasted in the Cursor provider editor.
            return nil
        case .clinePass:
            return ClinePassCatalog.documentationURL
        default:
            return nil
        }
    }

    var provider: Provider {
        switch self {
        case .cursor:
            // Placeholder key for grok config.toml; the real Cursor API key is stored under
            // Application Support and injected only into the local sidecar process.
            return Provider(
                id: "cursor",
                name: "Cursor",
                baseURL: CursorBridge.managedEndpoint.baseURL,
                apiKey: "local",
                suggestedModel: "composer-2.5"
            )
        case .openai:
            return Provider(
                id: "openai",
                name: "ChatGPT (OpenAI)",
                baseURL: "https://api.openai.com/v1",
                suggestedModel: "gpt-4o"
            )
        case .zai:
            return Provider(
                id: "zai",
                name: "Z.ai (GLM)",
                baseURL: "https://api.z.ai/api/coding/paas/v4",
                suggestedModel: "glm-5.2"
            )
        case .minimax:
            return Provider(
                id: "minimax",
                name: "MiniMax",
                baseURL: "https://api.minimax.io/v1",
                suggestedModel: "minimax-m2.5"
            )
        case .kimi:
            return Provider(
                id: "kimi",
                name: "Kimi (Moonshot)",
                baseURL: "https://api.moonshot.ai/v1",
                suggestedModel: "kimi-k2.6"
            )
        case .qwen:
            return Provider(
                id: "qwen",
                name: "Qwen (DashScope)",
                baseURL: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
                suggestedModel: "qwen3.7-plus"
            )
        case .xiaomiMiMo:
            return Provider(
                id: "xiaomi-mimo",
                name: "Xiaomi MiMo",
                baseURL: "https://api.xiaomimimo.com/v1",
                suggestedModel: "mimo-v2.5-pro"
            )
        case .deepseek:
            return Provider(
                id: "deepseek",
                name: "DeepSeek",
                baseURL: "https://api.deepseek.com",
                suggestedModel: "deepseek-v4-pro"
            )
        case .ollama:
            // Ollama ignores the key, but its OpenAI-compatible endpoint expects a
            // non-empty value; "ollama" is the conventional placeholder.
            return Provider(
                id: "ollama",
                name: "Ollama (local)",
                baseURL: "http://localhost:11434/v1",
                apiKey: "ollama",
                suggestedModel: "llama3.2"
            )
        case .clinePass:
            return Provider(
                id: "clinepass",
                name: "Cline Pass",
                baseURL: "https://api.cline.bot/api/v1",
                suggestedModel: "cline-pass/glm-5.2"
            )
        }
    }
}

/// Helpers for Cline Pass model listing (live feed + display labels).
///
/// Docs: [ClinePass — Models](https://docs.cline.bot/getting-started/clinepass#models).
enum ClinePassCatalog {
    static let documentationURL = URL(string: "https://docs.cline.bot/getting-started/clinepass#models")!

    /// Public Cline recommended-models feed (includes a `clinePass` array; no API key required).
    static let recommendedModelsURL = URL(
        string: "https://api.cline.bot/api/v1/ai/cline/recommended-models"
    )!

    /// Human-readable label derived from a Cline Pass model id slug.
    static func displayLabel(for modelID: String) -> String {
        let slug = modelID.split(separator: "/").last.map(String.init) ?? modelID
        let acronyms: Set<String> = ["glm", "gpt"]
        return slug
            .split(separator: "-")
            .map { part -> String in
                let token = String(part)
                if token.allSatisfy({ $0.isNumber || $0 == "." }) { return token }
                let lower = token.lowercased()
                if acronyms.contains(lower) { return lower.uppercased() }
                return token.prefix(1).uppercased() + token.dropFirst()
            }
            .joined(separator: " ")
    }

    /// Display name written to config.toml `name` (e.g. "Cline Kimi K2.7 Code").
    static func displayName(for catalogName: String) -> String {
        let trimmed = catalogName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.lowercased().hasPrefix("cline ") { return trimmed }
        return "Cline \(trimmed)"
    }

    /// Sorts models A–Z by display label (falls back to id), so related names stay adjacent.
    static func sortedAlphabetically(_ models: [FetchedModel]) -> [FetchedModel] {
        models.sorted { lhs, rhs in
            let left = (lhs.ownedBy?.isEmpty == false ? lhs.ownedBy! : lhs.id)
            let right = (rhs.ownedBy?.isEmpty == false ? rhs.ownedBy! : rhs.id)
            let labelOrder = left.localizedCaseInsensitiveCompare(right)
            if labelOrder != .orderedSame { return labelOrder == .orderedAscending }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }
}

extension Provider {
    var matchingPreset: ProviderPreset? { ProviderPreset.matching(provider: self) }

    var supportsModelListingFetch: Bool {
        matchingPreset?.supportsModelListingFetch ?? true
    }

    var catalogDocumentationURL: URL? {
        matchingPreset?.catalogDocumentationURL
    }

    var supportsLiveCatalogRefresh: Bool {
        matchingPreset?.supportsLiveCatalogRefresh ?? false
    }

    /// True when this installed provider is the GrokBuild-managed Cursor sidecar.
    var isManagedCursorBridge: Bool {
        matchingPreset?.isManagedCursorBridge == true || id == ProviderPreset.cursor.provider.id
    }
}

/// Shared “Provider + model” display names for fetched OpenAI-compatible catalogs
/// (e.g. MiniMax + `minimax-m2.5` → `MiniMax M2.5`), matching Cline/Cursor style.
enum ProviderModelNaming {
    /// Parenthetical suffixes in provider titles are dropped (`ChatGPT (OpenAI)` → `ChatGPT`).
    static func providerLabel(from providerName: String) -> String {
        let trimmed = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let idx = trimmed.firstIndex(of: "(") {
            return trimmed[..<idx].trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    /// `providerName` + humanized model id, without double-prefixing.
    static func displayName(providerName: String, modelID: String) -> String {
        let provider = providerLabel(from: providerName)
        let label = humanizeModelID(modelID, strippingProviderSlug: CustomModel.suggestedID(from: provider))
        guard !provider.isEmpty else { return label }
        guard !label.isEmpty else { return provider }
        if label.lowercased().hasPrefix(provider.lowercased() + " ") { return label }
        if label.caseInsensitiveCompare(provider) == .orderedSame { return provider }
        return "\(provider) \(label)"
    }

    /// Title-cases a model slug, optionally stripping a leading provider token (`minimax-m2.5` → `M2.5`).
    static func humanizeModelID(_ modelID: String, strippingProviderSlug: String = "") -> String {
        var slug = modelID.split(separator: "/").last.map(String.init) ?? modelID
        slug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerSlug = strippingProviderSlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !providerSlug.isEmpty {
            let lower = slug.lowercased()
            if lower.hasPrefix(providerSlug + "-") {
                slug = String(slug.dropFirst(providerSlug.count + 1))
            } else if lower.hasPrefix(providerSlug + "_") {
                slug = String(slug.dropFirst(providerSlug.count + 1))
            }
        }
        return titleCaseSlug(slug)
    }

    static func titleCaseSlug(_ slug: String) -> String {
        let acronyms: Set<String> = ["glm", "gpt", "llm", "moe"]
        return slug
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { part -> String in
                let token = String(part)
                if token.allSatisfy({ $0.isNumber || $0 == "." }) { return token }
                let lower = token.lowercased()
                if acronyms.contains(lower) { return lower.uppercased() }
                return token.prefix(1).uppercased() + token.dropFirst()
            }
            .joined(separator: " ")
    }
}

/// A single entry returned by a provider's `/v1/models` listing.
struct FetchedModel: Identifiable, Hashable, Sendable {
    var id: String
    var ownedBy: String?
}

/// Settings list order: A–Z by “Provider + model” (then id), matching the labels shown in the UI.
enum CustomModelListOrdering {
    /// Sort key is always Provider + model (not the raw config.toml `name`, which may be a slug).
    static func sortLabel(for model: CustomModel, providers: [Provider]) -> String {
        let modelID = model.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackID = modelID.isEmpty ? model.id : modelID
        if let providerID = model.providerID,
           let provider = providers.first(where: { $0.id == providerID }) {
            return fetchedSortLabel(for: FetchedModel(id: fallbackID), provider: provider)
        }
        let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? fallbackID : name
    }

    static func sortedAlphabetically(_ models: [CustomModel], providers: [Provider]) -> [CustomModel] {
        models.sorted { lhs, rhs in
            let left = sortLabel(for: lhs, providers: providers)
            let right = sortLabel(for: rhs, providers: providers)
            let order = left.localizedCaseInsensitiveCompare(right)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }

    /// Same “Provider + model” label the Add-model picker shows (without the trailing id).
    static func fetchedSortLabel(for model: FetchedModel, provider: Provider) -> String {
        if provider.isManagedCursorBridge {
            return CursorBridge.displayName(for: model.id)
        }
        if provider.matchingPreset == .clinePass {
            let catalog = model.ownedBy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let base = catalog.isEmpty ? ClinePassCatalog.displayLabel(for: model.id) : catalog
            return ClinePassCatalog.displayName(for: base)
        }
        return ProviderModelNaming.displayName(providerName: provider.name, modelID: model.id)
    }

    static func sortedAlphabetically(_ models: [FetchedModel], provider: Provider) -> [FetchedModel] {
        models.sorted { lhs, rhs in
            let left = fetchedSortLabel(for: lhs, provider: provider)
            let right = fetchedSortLabel(for: rhs, provider: provider)
            let order = left.localizedCaseInsensitiveCompare(right)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }
}

/// Fetches the list of available models from an OpenAI-compatible provider.
///
/// Calls `GET {base_url}/models` with `Authorization: Bearer <key>` and decodes the
/// standard OpenAI response shape `{ "object": "list", "data": [{ "id": ... }] }`.
/// The base URL already carries any version suffix (e.g. `/v1`,
/// `/compatible-mode/v1`, or none for DeepSeek), so we only trim a trailing slash
/// before appending `/models`.
enum ProviderModelFetcher {
    enum FetchError: LocalizedError {
        case invalidURL
        case unauthorized
        case http(Int)
        case empty
        case transport(String)
        case decode

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "The base URL is not a valid endpoint."
            case .unauthorized: return "Unauthorized — check the API key for this provider."
            case .http(let code): return "The provider returned HTTP \(code)."
            case .empty: return "The provider returned no models."
            case .transport(let message): return message
            case .decode: return "Could not read the model list from the provider."
            }
        }
    }

    /// Builds the `/models` URL from a base URL, preserving any existing version path.
    static func modelsURL(for baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return URL(string: normalized + "/models")
    }

    /// Resolves the effective inline API key for a fetch, or nil when none is set.
    static func resolveKey(apiKey: String) -> String? {
        let inline = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return inline.isEmpty ? nil : inline
    }

    /// Parses an OpenAI-style `/models` payload into a sorted, de-duplicated list.
    static func parse(_ data: Data) -> [FetchedModel]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        // Accept either { "data": [...] } or a bare top-level array.
        let rawList: [Any]
        if let dict = object as? [String: Any], let list = dict["data"] as? [Any] {
            rawList = list
        } else if let list = object as? [Any] {
            rawList = list
        } else {
            return nil
        }

        var seen = Set<String>()
        var models: [FetchedModel] = []
        for item in rawList {
            guard let entry = item as? [String: Any] else { continue }
            // Most providers use "id"; a few echo "model".
            let identifier = (entry["id"] as? String) ?? (entry["model"] as? String)
            guard let id = identifier?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { continue }
            guard seen.insert(id).inserted else { continue }
            models.append(FetchedModel(id: id, ownedBy: entry["owned_by"] as? String))
        }
        return models.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    /// Fetches and parses the model list for a provider.
    static func fetch(
        baseURL: String,
        apiKey: String
    ) async throws -> [FetchedModel] {
        guard let url = modelsURL(for: baseURL) else { throw FetchError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = resolveKey(apiKey: apiKey) {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            // Xiaomi MiMo also accepts an `api-key` header; set both for broad compatibility.
            request.setValue(key, forHTTPHeaderField: "api-key")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FetchError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 { throw FetchError.unauthorized }
            guard (200..<300).contains(http.statusCode) else { throw FetchError.http(http.statusCode) }
        }

        guard let models = parse(data) else { throw FetchError.decode }
        guard !models.isEmpty else { throw FetchError.empty }
        return models
    }

    /// Fetches Cline Pass models from the public recommended-models feed (no API key).
    static func fetchClinePassRecommended(
        url: URL = ClinePassCatalog.recommendedModelsURL
    ) async throws -> [FetchedModel] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FetchError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else { throw FetchError.http(http.statusCode) }
        }

        guard let models = parseClinePassRecommended(data) else { throw FetchError.decode }
        guard !models.isEmpty else { throw FetchError.empty }
        return models
    }

    /// Parses `{ "clinePass": [{ "id": "cline-pass/…", "name": "…" }] }` from Cline's feed.
    static func parseClinePassRecommended(_ data: Data) -> [FetchedModel]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["clinePass"] as? [Any] else {
            return nil
        }

        var seen = Set<String>()
        var models: [FetchedModel] = []
        for item in list {
            guard let entry = item as? [String: Any] else { continue }
            let identifier = (entry["id"] as? String) ?? (entry["model"] as? String)
            guard let id = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  id.hasPrefix("cline-pass/") else { continue }
            guard seen.insert(id).inserted else { continue }
            models.append(FetchedModel(id: id, ownedBy: ClinePassCatalog.displayLabel(for: id)))
        }
        // Alphabetical by display label (related names stay adjacent).
        return ClinePassCatalog.sortedAlphabetically(models)
    }

    /// Fetches models for an installed/draft provider, routing Cline Pass to its live catalog.
    static func fetch(for provider: Provider) async throws -> [FetchedModel] {
        if provider.supportsLiveCatalogRefresh {
            return try await fetchClinePassRecommended()
        }
        return try await fetch(baseURL: provider.baseURL, apiKey: provider.apiKey)
    }
}

/// Persists user-defined `Provider`s in `UserDefaults` (config.toml has no provider concept).
enum ProviderStore {
    private static let key = "grokbuild.customModelProviders"

    static func load() -> [Provider] {
        guard let data = UserDefaults.standard.data(forKey: key),
              var providers = try? JSONDecoder().decode([Provider].self, from: data) else {
            return []
        }
        // Rename legacy "Cursor (local bridge)" label to plain "Cursor".
        let cursorID = ProviderPreset.cursor.provider.id
        let cursorName = ProviderPreset.cursor.provider.name
        var changed = false
        for index in providers.indices where providers[index].id == cursorID && providers[index].name != cursorName {
            providers[index].name = cursorName
            changed = true
        }
        if changed { save(providers) }
        return providers
    }

    static func save(_ providers: [Provider]) {
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Reads and writes custom model entries in `~/.grok/config.toml`.
///
/// The store performs minimal, targeted edits: it manages `[model.<id>]` tables and the
/// `default` key inside `[models]`, while preserving any other content in the file.
enum CustomModelStore {
    /// Maximum number of custom models GrokBuild will manage in `~/.grok/config.toml`.
    static let maxModels = 28

    static var configURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".grok/config.toml")
    }

    // MARK: - Loading

    /// Loaded custom models plus the configured default model id (which may reference a built-in).
    struct Snapshot: Sendable {
        var models: [CustomModel]
        var defaultModelID: String?
    }

    static func load() -> Snapshot {
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return Snapshot(models: [], defaultModelID: nil)
        }
        return parse(contents)
    }

    static func parse(_ contents: String) -> Snapshot {
        var models: [CustomModel] = []
        var defaultModelID: String?

        var currentTable: String?
        var currentModelID: String?
        var fields: [String: String] = [:]

        func flushModel() {
            guard let id = currentModelID else { return }
            models.append(CustomModel(
                id: id,
                model: fields["model"] ?? "",
                baseURL: fields["base_url"] ?? "",
                name: fields["name"] ?? "",
                apiKey: fields["api_key"] ?? "",
                contextTokens: parseInt(fields["grokbuild_context_tokens"]),
                supportsReasoningEffort: parseBool(fields["grokbuild_supports_reasoning_effort"]) ?? true,
                supportsVision: parseBool(fields["grokbuild_supports_vision"]) ?? false,
                supportsThinkingDisplay: parseBool(fields["grokbuild_supports_thinking"]) ?? false,
                apiBackend: ModelAPIBackend.parse(fields["api_backend"]),
                envKey: fields["env_key"] ?? ""
            ))
            currentModelID = nil
            fields = [:]
        }

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                flushModel()
                let header = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                currentTable = header
                if header.hasPrefix("model.") {
                    currentModelID = unquote(String(header.dropFirst("model.".count)))
                }
                continue
            }

            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = unquote(line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces))

            if currentModelID != nil {
                fields[key] = value
            } else if currentTable == "models", key == "default" {
                defaultModelID = value
            }
        }
        flushModel()

        return Snapshot(models: models, defaultModelID: defaultModelID)
    }

    // MARK: - Saving

    /// Persists `models` and `defaultModelID` into the config file, preserving unrelated content.
    static func save(models: [CustomModel], defaultModelID: String?) throws {
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let updated = rewrite(existing, models: models, defaultModelID: defaultModelID)
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try updated.write(to: configURL, atomically: true, encoding: .utf8)
    }

    /// Produces a new config string: drops all existing `[model.*]` tables and the `[models].default`
    /// key, then appends fresh versions while keeping every other section intact.
    static func rewrite(_ contents: String, models: [CustomModel], defaultModelID: String?) -> String {
        var output: [String] = []
        var skippingModelTable = false
        var inModelsTable = false

        for rawLine in contents.components(separatedBy: .newlines) {
            let trimmed = stripComment(rawLine).trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let header = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                skippingModelTable = header.hasPrefix("model.")
                inModelsTable = (header == "models")
                if skippingModelTable { continue }
                output.append(rawLine)
                continue
            }

            if skippingModelTable { continue }

            // Drop only the managed `default` key inside [models]; keep other [models] keys.
            if inModelsTable {
                if let eq = trimmed.firstIndex(of: "="),
                   trimmed[..<eq].trimmingCharacters(in: .whitespaces) == "default" {
                    continue
                }
            }

            output.append(rawLine)
        }

        // Trim trailing blank lines for a tidy append.
        while let last = output.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            output.removeLast()
        }

        var result = output.joined(separator: "\n")

        // Append model tables.
        for model in models {
            result += "\n\n[model.\(quoteKeyIfNeeded(model.id))]\n"
            result += "model = \(quote(model.model))\n"
            result += "base_url = \(quote(model.baseURL))\n"
            if !model.name.trimmingCharacters(in: .whitespaces).isEmpty {
                result += "name = \(quote(model.name))\n"
            }
            if !model.apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                result += "api_key = \(quote(model.apiKey))\n"
            }
            if !model.envKey.trimmingCharacters(in: .whitespaces).isEmpty {
                result += "env_key = \(quote(model.envKey))\n"
            }
            // Only write api_backend when it deviates from grok's default, to keep files tidy.
            if model.apiBackend != .default {
                result += "api_backend = \(quote(model.apiBackend.rawValue))\n"
            }
            if let contextTokens = model.contextTokens {
                result += "grokbuild_context_tokens = \(contextTokens)\n"
            }
            result += "grokbuild_supports_reasoning_effort = \(model.supportsReasoningEffort)\n"
            result += "grokbuild_supports_vision = \(model.supportsVision)\n"
            result += "grokbuild_supports_thinking = \(model.supportsThinkingDisplay)\n"
        }

        // Re-establish [models].default. Reuse an existing [models] table if present.
        if let defaultModelID, !defaultModelID.trimmingCharacters(in: .whitespaces).isEmpty {
            if result.range(of: #"(?m)^\s*\[models\]\s*$"#, options: .regularExpression) != nil {
                result = result.replacingOccurrences(
                    of: #"(?m)^(\s*\[models\]\s*\n)"#,
                    with: "$1default = \(quote(defaultModelID))\n",
                    options: .regularExpression
                )
            } else {
                result += "\n\n[models]\ndefault = \(quote(defaultModelID))\n"
            }
        }

        if !result.hasSuffix("\n") { result += "\n" }
        return result
    }

    // MARK: - TOML helpers

    private static func stripComment(_ line: String) -> String {
        var quote: Character? = nil
        var escaped = false
        var result = ""

        for char in line {
            if let q = quote {
                if q == "\"" {
                    if escaped {
                        escaped = false
                    } else if char == "\\" {
                        escaped = true
                    } else if char == "\"" {
                        quote = nil
                    }
                } else if char == q {
                    quote = nil
                }
                result.append(char)
                continue
            }

            if char == "\"" || char == "'" {
                quote = char
                result.append(char)
                continue
            }

            if char == "#" { break }
            result.append(char)
        }

        return result
    }

    private static func unquote(_ value: String) -> String {
        var v = value.trimmingCharacters(in: .whitespaces)
        if v.count >= 2, (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        return v
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func parseBool(_ value: String?) -> Bool? {
        guard let value else { return nil }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    private static func parseInt(_ value: String?) -> Int? {
        guard let value else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Returns a TOML table-key segment for `[model.<key>]`.
    ///
    /// A *bare* TOML key may only contain `A-Za-z0-9_-`. A dot is a table-path separator, so an
    /// id like `minimax-m2.5` MUST be quoted (`"minimax-m2.5"`) — otherwise TOML reads it as the
    /// nested table `model.minimax-m2."5"` and the model id becomes `minimax-m2`.
    private static func quoteKeyIfNeeded(_ key: String) -> String {
        if key.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil {
            return key
        }
        return quote(key)
    }
}

/// A user-defined subagent **role** for grok's `[subagents.roles.<name>]` in `~/.grok/config.toml`.
///
/// Maps to a role table plus a prompt file holding the instruction, e.g.
/// ```toml
/// [subagents.roles.researcher]
/// description = "Deep research agent"
/// model = "grok-build"
/// prompt_file = "/Users/me/.grok/prompts/researcher.md"
/// ```
///
/// grok owns how roles are spawned; GrokBuild only edits the definition. An empty `model`
/// means the subagent inherits the parent session's model (grok's default behavior).
struct SubagentRole: Identifiable, Hashable, Sendable {
    /// The role name — the TOML table key `[subagents.roles.<name>]` and how the role is spawned.
    var name: String
    /// The model this role runs on. Empty = inherit the parent session's model.
    var model: String
    /// The role's system instruction, stored in a prompt file and referenced via `prompt_file`.
    var instruction: String
    /// Optional short description shown in `grok inspect` and the editor.
    var description: String
    /// Role keys GrokBuild does not edit directly (for example `default_capability_mode`).
    /// Values are preserved as TOML literals so saving from the UI does not erase valid grok config.
    var extraFields: [String: String]

    var id: String { name }

    init(
        name: String,
        model: String = "",
        instruction: String = "",
        description: String = "",
        extraFields: [String: String] = [:]
    ) {
        self.name = name
        self.model = model
        self.instruction = instruction
        self.description = description
        self.extraFields = extraFields
    }

    /// Derives a valid role name from free text (letters, numbers, dashes, underscores).
    static func suggestedName(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        var result = ""
        var lastWasSeparator = false
        for char in trimmed {
            if char.isLetter || char.isNumber || char == "_" || char == "-" {
                result.append(char)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                result.append("-")
                lastWasSeparator = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-_")).lowercased()
    }

    /// Names reserved by grok's built-in subagents; a custom role may not shadow them.
    static let reservedNames: Set<String> = [
        "general", "general-purpose", "explore", "plan", "vision", "verify", "computer"
    ]

    /// A validation error message, or nil when the entry is well-formed.
    var validationError: String? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { return "Name is required." }
        if trimmedName.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) == nil {
            return "Name may only contain letters, numbers, dashes, and underscores."
        }
        if SubagentRole.reservedNames.contains(trimmedName.lowercased()) {
            return "\"\(trimmedName)\" is reserved by a built-in subagent."
        }
        if instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Instruction is required."
        }
        return nil
    }
}

/// Reads and writes custom subagent roles in `~/.grok/config.toml` (`[subagents.roles.*]`).
///
/// Mirrors `CustomModelStore`: it performs minimal, targeted edits — managing only
/// `[subagents.roles.<name>]` tables while preserving every other section (models, other
/// `[subagents.*]` tables, etc.). Each role's instruction lives in `~/.grok/prompts/<name>.md`
/// and is referenced from the role table via `prompt_file`.
enum SubagentRoleStore {
    /// Maximum number of custom roles GrokBuild will manage.
    static let maxRoles = 24

    static var configURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".grok/config.toml")
    }

    static var promptsDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".grok/prompts")
    }

    static func promptURL(for name: String) -> URL {
        promptsDirectory.appendingPathComponent("\(name).md")
    }

    // MARK: - Loading

    static func load() -> [SubagentRole] {
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else { return [] }
        return parse(contents)
    }

    /// Parses `[subagents.roles.<name>]` tables, reading each instruction from its `prompt_file`.
    static func parse(
        _ contents: String,
        relativePromptBaseURL: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) -> [SubagentRole] {
        var roles: [SubagentRole] = []
        var currentName: String?
        var fields: [String: String] = [:]
        var rawFields: [String: String] = [:]

        func flush() {
            guard let name = currentName else { return }
            let instruction: String
            if let path = fields["prompt_file"], !path.isEmpty,
               let text = try? String(contentsOfFile: resolvePath(path, relativeTo: relativePromptBaseURL), encoding: .utf8) {
                instruction = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                instruction = ""
            }
            roles.append(SubagentRole(
                name: name,
                model: fields["model"] ?? "",
                instruction: instruction,
                description: fields["description"] ?? "",
                extraFields: rawFields.filter { !Self.managedRoleFields.contains($0.key) }
            ))
            currentName = nil
            fields = [:]
            rawFields = [:]
        }

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                flush()
                let header = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if header.hasPrefix("subagents.roles.") {
                    currentName = unquote(String(header.dropFirst("subagents.roles.".count)))
                }
                continue
            }

            guard currentName != nil, let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            let value = unquote(rawValue)
            fields[key] = value
            rawFields[key] = String(rawValue)
        }
        flush()

        return roles
    }

    // MARK: - Saving

    /// Persists `roles` into config.toml (preserving unrelated content) and writes each
    /// instruction to its prompt file. Prompt files for removed roles are deleted only when
    /// the role's `prompt_file` in config.toml pointed to the GrokBuild-managed path.
    static func save(_ roles: [SubagentRole]) throws {
        try save(roles, configURL: configURL, promptsDirectory: promptsDirectory)
    }

    /// Testable save that writes `config.toml` + prompt files at injected paths.
    static func save(
        _ roles: [SubagentRole],
        configURL: URL,
        promptsDirectory: URL,
        relativePromptBaseURL: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) throws {
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        // Capture prompt_file paths before overwriting, so we can check which files are safe to delete.
        let previousPromptFiles = parsePromptFilePaths(existing)
        let updated = rewrite(existing, roles: roles, promptsDirectory: promptsDirectory)

        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: promptsDirectory, withIntermediateDirectories: true)

        for role in roles {
            try role.instruction.write(
                to: promptsDirectory.appendingPathComponent("\(role.name).md"),
                atomically: true,
                encoding: .utf8
            )
        }

        // Remove prompt files only for roles that no longer exist and whose prompt_file
        // resolved to the GrokBuild-managed path (to avoid deleting user-maintained files).
        let keptNames = Set(roles.map(\.name))
        for (name, rawPath) in previousPromptFiles where !keptNames.contains(name) {
            let managedURL = promptsDirectory.appendingPathComponent("\(name).md").standardized
            let resolvedURL = URL(
                fileURLWithPath: resolvePath(rawPath, relativeTo: relativePromptBaseURL)
            ).standardized
            if resolvedURL == managedURL {
                try? FileManager.default.removeItem(at: managedURL)
            }
        }

        try updated.write(to: configURL, atomically: true, encoding: .utf8)
    }

    /// Returns a map of role name → raw `prompt_file` value for every `[subagents.roles.*]` table.
    private static func parsePromptFilePaths(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        var currentName: String?
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let header = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                currentName = header.hasPrefix("subagents.roles.")
                    ? unquote(String(header.dropFirst("subagents.roles.".count)))
                    : nil
                continue
            }
            guard let name = currentName, let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard key == "prompt_file" else { continue }
            let rawValue = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            result[name] = unquote(rawValue)
        }
        return result
    }

    /// Drops all existing `[subagents.roles.*]` tables, then appends fresh ones, keeping every
    /// other section intact.
    static func rewrite(
        _ contents: String,
        roles: [SubagentRole],
        promptsDirectory: URL = promptsDirectory
    ) -> String {
        var output: [String] = []
        var skipping = false

        for rawLine in contents.components(separatedBy: .newlines) {
            let trimmed = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let header = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                skipping = header.hasPrefix("subagents.roles.")
                if skipping { continue }
                output.append(rawLine)
                continue
            }
            if skipping { continue }
            output.append(rawLine)
        }

        while let last = output.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            output.removeLast()
        }

        var result = output.joined(separator: "\n")

        for role in roles {
            result += "\n\n[subagents.roles.\(role.name)]\n"
            if !role.description.trimmingCharacters(in: .whitespaces).isEmpty {
                result += "description = \(quote(role.description))\n"
            }
            if !role.model.trimmingCharacters(in: .whitespaces).isEmpty {
                result += "model = \(quote(role.model))\n"
            }
            for key in role.extraFields.keys.sorted() {
                guard let rawValue = role.extraFields[key],
                      !Self.managedRoleFields.contains(key) else { continue }
                result += "\(key) = \(rawValue)\n"
            }
            result += "prompt_file = \(quote(promptsDirectory.appendingPathComponent("\(role.name).md").path))\n"
        }

        if !result.hasSuffix("\n") { result += "\n" }
        return result
    }

    // MARK: - TOML helpers

    private static let managedRoleFields: Set<String> = ["description", "model", "prompt_file"]

    private static func resolvePath(_ path: String, relativeTo baseURL: URL) -> String {
        if path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        if path.hasPrefix("/") {
            return path
        }
        return baseURL.appendingPathComponent(path).path
    }

    static func resolvedPromptPath(_ path: String) -> String {
        resolvePath(path, relativeTo: URL(fileURLWithPath: NSHomeDirectory()))
    }

    private static func stripComment(_ line: String) -> String {
        var quote: Character?
        var escaped = false
        var result = ""
        for char in line {
            if let q = quote {
                if q == "\"" {
                    if escaped { escaped = false }
                    else if char == "\\" { escaped = true }
                    else if char == "\"" { quote = nil }
                } else if char == q {
                    quote = nil
                }
                result.append(char)
                continue
            }
            if char == "\"" || char == "'" { quote = char; result.append(char); continue }
            if char == "#" { break }
            result.append(char)
        }
        return result
    }

    private static func unquote(_ value: String) -> String {
        var v = value.trimmingCharacters(in: .whitespaces)
        if v.count >= 2, (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        return v
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
