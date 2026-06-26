import Foundation

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
    /// Optional link to a saved `Provider`. GrokBuild-only; the endpoint/credential are still
    /// written into this model's own `[model.<id>]` table so the Grok CLI can read them.
    var providerID: String?

    init(
        id: String,
        model: String,
        baseURL: String,
        name: String = "",
        apiKey: String = "",
        providerID: String? = nil
    ) {
        self.id = id
        self.model = model
        self.baseURL = baseURL
        self.name = name
        self.apiKey = apiKey
        self.providerID = providerID
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

/// Built-in provider presets for popular OpenAI-compatible endpoints.
enum ProviderPreset: String, CaseIterable, Identifiable {
    case openai
    case zai
    case minimax
    case kimi
    case qwen
    case xiaomiMiMo
    case deepseek
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "ChatGPT (OpenAI)"
        case .zai: return "Z.ai (GLM)"
        case .minimax: return "MiniMax"
        case .kimi: return "Kimi (Moonshot)"
        case .qwen: return "Qwen (DashScope)"
        case .xiaomiMiMo: return "Xiaomi MiMo"
        case .deepseek: return "DeepSeek"
        case .ollama: return "Ollama (local)"
        }
    }

    var provider: Provider {
        switch self {
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
        }
    }
}

/// A single entry returned by a provider's `/v1/models` listing.
struct FetchedModel: Identifiable, Hashable, Sendable {
    var id: String
    var ownedBy: String?
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
}

/// Persists user-defined `Provider`s in `UserDefaults` (config.toml has no provider concept).
enum ProviderStore {
    private static let key = "grokbuild.customModelProviders"

    static func load() -> [Provider] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let providers = try? JSONDecoder().decode([Provider].self, from: data) else {
            return []
        }
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
                apiKey: fields["api_key"] ?? ""
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
