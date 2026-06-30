import XCTest
@testable import GrokBuild

final class CustomModelTests: XCTestCase {
    func testParseReadsModelTablesAndDefault() {
        let toml = """
        [cli]
        installer = "internal"

        [model.zai-glm]
        model = "glm-5.2"
        base_url = "https://api.z.ai/api/coding/paas/v4"
        name = "Z.ai GLM-5.2"
        api_key = "sk-secret-value"

        [model.local-glm]
        model = "glm-4.6"
        base_url = "http://localhost:8000/v1"
        name = "Local GLM-4.6"

        [models]
        default = "zai-glm"
        """

        let snapshot = CustomModelStore.parse(toml)
        XCTAssertEqual(snapshot.defaultModelID, "zai-glm")
        XCTAssertEqual(snapshot.models.count, 2)

        let zai = snapshot.models.first { $0.id == "zai-glm" }
        XCTAssertEqual(zai?.model, "glm-5.2")
        XCTAssertEqual(zai?.baseURL, "https://api.z.ai/api/coding/paas/v4")
        XCTAssertEqual(zai?.name, "Z.ai GLM-5.2")
        XCTAssertEqual(zai?.apiKey, "sk-secret-value")
        XCTAssertTrue(zai?.hasInlineKey ?? false)

        let local = snapshot.models.first { $0.id == "local-glm" }
        XCTAssertEqual(local?.apiKey, "")
        XCTAssertTrue(local?.isLocalEndpoint ?? false)
    }

    func testApiKeyRoundTripsThroughRewrite() {
        let model = CustomModel(
            id: "zai-glm",
            model: "glm-5.2",
            baseURL: "https://api.z.ai/api/coding/paas/v4",
            name: "Z.ai GLM-5.2",
            apiKey: "sk-abc123"
        )
        let rewritten = CustomModelStore.rewrite("", models: [model], defaultModelID: nil)
        XCTAssertTrue(rewritten.contains("api_key = \"sk-abc123\""))

        let reparsed = CustomModelStore.parse(rewritten)
        XCTAssertEqual(reparsed.models.first?.apiKey, "sk-abc123")
    }

    func testApiKeyWithSpecialCharactersIsEscaped() {
        let model = CustomModel(
            id: "weird",
            model: "m",
            baseURL: "https://x/v1",
            apiKey: #"sk-with"quote\and-backslash"#
        )
        let rewritten = CustomModelStore.rewrite("", models: [model], defaultModelID: nil)
        let reparsed = CustomModelStore.parse(rewritten)
        XCTAssertEqual(reparsed.models.first?.apiKey, #"sk-with"quote\and-backslash"#)
    }

    func testDottedModelIDIsQuotedInTableHeader() {
        // A dot in the id must be quoted, else TOML nests it: `[model.minimax-m2.5]` would be
        // read by the Grok CLI as model id `minimax-m2`. Header must be `[model."minimax-m2.5"]`.
        let model = CustomModel(
            id: "minimax-m2.5",
            model: "MiniMax-M2.5",
            baseURL: "https://api.minimax.io/v1",
            apiKey: "sk-1"
        )
        let rewritten = CustomModelStore.rewrite("", models: [model], defaultModelID: "minimax-m2.5")
        XCTAssertTrue(
            rewritten.contains(#"[model."minimax-m2.5"]"#),
            "dotted id must be quoted in the table header:\n\(rewritten)"
        )
        XCTAssertFalse(rewritten.contains("[model.minimax-m2.5]"), "must not write an unquoted dotted header")

        // And it must round-trip back to the exact same id.
        let reparsed = CustomModelStore.parse(rewritten)
        XCTAssertEqual(reparsed.models.map { $0.id }, ["minimax-m2.5"])
        XCTAssertEqual(reparsed.models.first?.model, "MiniMax-M2.5")
        XCTAssertEqual(reparsed.defaultModelID, "minimax-m2.5")
    }

    func testBareModelIDStaysUnquoted() {
        let model = CustomModel(id: "grok-build", model: "grok-build", baseURL: "https://x/v1")
        let rewritten = CustomModelStore.rewrite("", models: [model], defaultModelID: nil)
        XCTAssertTrue(rewritten.contains("[model.grok-build]"))
    }

    func testMaskRedactsSecret() {
        XCTAssertEqual(CustomModel.mask(""), "")
        XCTAssertEqual(CustomModel.mask("short"), "•••••")
        XCTAssertEqual(CustomModel.mask("sk-1234567890ab"), "sk-1…90ab")
    }

    func testSuggestedIDSanitizesProviderModelNames() {
        XCTAssertEqual(CustomModel.suggestedID(from: "MiniMax-M2.7"), "minimax-m2.7")
        XCTAssertEqual(CustomModel.suggestedID(from: "MiniMax-M3"), "minimax-m3")
        XCTAssertEqual(CustomModel.suggestedID(from: "gemma4:12b-mlx"), "gemma4-12b-mlx")
        XCTAssertEqual(CustomModel.suggestedID(from: "  "), "")
    }

    func testRewriteSupportsMultipleModelsFromSameProvider() {
        let providerURL = "https://api.minimax.io/v1"
        let modelA = CustomModel(id: "minimax-m2.5", model: "MiniMax-M2.5", baseURL: providerURL, apiKey: "sk-1")
        let modelB = CustomModel(id: "minimax-m2.7", model: "MiniMax-M2.7", baseURL: providerURL, apiKey: "sk-1")
        let rewritten = CustomModelStore.rewrite("", models: [modelA, modelB], defaultModelID: nil)
        let reparsed = CustomModelStore.parse(rewritten)
        XCTAssertEqual(reparsed.models.count, 2)
        XCTAssertEqual(Set(reparsed.models.map(\.id)), ["minimax-m2.5", "minimax-m2.7"])
    }

    func testRewriteSupportsMultipleClinePassModels() {
        let providerURL = "https://api.cline.bot/api/v1"
        let modelA = CustomModel(
            id: "cline-pass-glm-5.2",
            model: "cline-pass/glm-5.2",
            baseURL: providerURL,
            apiKey: "sk-1"
        )
        let modelB = CustomModel(
            id: "cline-pass-kimi-k2.6",
            model: "cline-pass/kimi-k2.6",
            baseURL: providerURL,
            apiKey: "sk-1"
        )
        let rewritten = CustomModelStore.rewrite("", models: [modelA, modelB], defaultModelID: nil)
        let reparsed = CustomModelStore.parse(rewritten)
        XCTAssertEqual(reparsed.models.count, 2)
        XCTAssertEqual(Set(reparsed.models.map(\.id)), ["cline-pass-glm-5.2", "cline-pass-kimi-k2.6"])
        XCTAssertEqual(reparsed.models.first?.model, "cline-pass/glm-5.2")
    }

    func testMaxModelsLimitIsTwentyEight() {
        XCTAssertEqual(CustomModelStore.maxModels, 28)
    }

    func testRewritePreservesUnrelatedSectionsAndUpdatesModels() {
        let original = """
        [cli]
        installer = "internal"

        [marketplace]
        official_marketplace_auto_installed = true

        [models]
        default = "grok-composer-2.5-fast"

        [ui]
        yolo = false
        """

        let model = CustomModel(
            id: "minimax",
            model: "minimax-m2.5",
            baseURL: "https://api.minimax.io/v1",
            name: "MiniMax M2.5",
            apiKey: "sk-minimax"
        )

        let rewritten = CustomModelStore.rewrite(original, models: [model], defaultModelID: "minimax")
        let reparsed = CustomModelStore.parse(rewritten)

        // Unrelated sections survive.
        XCTAssertTrue(rewritten.contains("[cli]"))
        XCTAssertTrue(rewritten.contains("installer = \"internal\""))
        XCTAssertTrue(rewritten.contains("[marketplace]"))
        XCTAssertTrue(rewritten.contains("[ui]"))
        XCTAssertTrue(rewritten.contains("yolo = false"))

        // Model table and default are updated.
        XCTAssertEqual(reparsed.models.count, 1)
        XCTAssertEqual(reparsed.models.first?.id, "minimax")
        XCTAssertEqual(reparsed.models.first?.baseURL, "https://api.minimax.io/v1")
        XCTAssertEqual(reparsed.defaultModelID, "minimax")

        // The old default value must not linger.
        XCTAssertFalse(rewritten.contains("grok-composer-2.5-fast"))
    }

    func testRewriteRemovesStaleModelTables() {
        let original = """
        [model.old-one]
        model = "old"
        base_url = "https://example.com/v1"

        [models]
        default = "old-one"
        """

        let rewritten = CustomModelStore.rewrite(original, models: [], defaultModelID: nil)
        let reparsed = CustomModelStore.parse(rewritten)

        XCTAssertTrue(reparsed.models.isEmpty)
        XCTAssertFalse(rewritten.contains("[model.old-one]"))
    }

    func testRewriteRoundTripIsStable() {
        let model = CustomModel(
            id: "zai-glm",
            model: "glm-5.2",
            baseURL: "https://api.z.ai/api/coding/paas/v4",
            name: "Z.ai GLM-5.2",
            apiKey: "sk-zai"
        )

        let first = CustomModelStore.rewrite("", models: [model], defaultModelID: "zai-glm")
        let parsedOnce = CustomModelStore.parse(first)
        let second = CustomModelStore.rewrite(first, models: parsedOnce.models, defaultModelID: parsedOnce.defaultModelID)
        let parsedTwice = CustomModelStore.parse(second)

        XCTAssertEqual(parsedOnce.models, parsedTwice.models)
        XCTAssertEqual(parsedOnce.defaultModelID, parsedTwice.defaultModelID)
        XCTAssertEqual(parsedTwice.models.first, model)
    }

    func testValidationCatchesBadInput() {
        XCTAssertNotNil(CustomModel(id: "", model: "m", baseURL: "https://x/v1").validationError)
        XCTAssertNotNil(CustomModel(id: "has space", model: "m", baseURL: "https://x/v1").validationError)
        XCTAssertNotNil(CustomModel(id: "ok", model: "", baseURL: "https://x/v1").validationError)
        XCTAssertNotNil(CustomModel(id: "ok", model: "m", baseURL: "ftp://x").validationError)
        XCTAssertNil(CustomModel(id: "zai-glm", model: "glm-5.2", baseURL: "https://api.z.ai/v1").validationError)
    }

    func testProviderPresetsAreValid() {
        for preset in ProviderPreset.allCases {
            XCTAssertNil(preset.provider.validationError, "Preset \(preset) should be valid")
            XCTAssertFalse(preset.provider.baseURL.isEmpty)
        }
    }

    func testProviderPresetsCoverRequestedProviders() {
        let names = Set(ProviderPreset.allCases.map { $0.displayName })
        XCTAssertTrue(names.contains("ChatGPT (OpenAI)"))
        XCTAssertTrue(names.contains("Kimi (Moonshot)"))
        XCTAssertTrue(names.contains("Qwen (DashScope)"))
        XCTAssertTrue(names.contains("Xiaomi MiMo"))
        XCTAssertTrue(names.contains("DeepSeek"))
        XCTAssertTrue(names.contains("Cline Pass"))
        XCTAssertTrue(names.contains("Ollama (local)"))
        // Ollama is local and defaults its inline key to the conventional "ollama"
        // placeholder its OpenAI endpoint expects.
        XCTAssertTrue(ProviderPreset.ollama.provider.isLocalEndpoint)
        XCTAssertEqual(ProviderPreset.ollama.provider.apiKey, "ollama")
    }

    func testEachProviderPresetHasAStartingModel() {
        for preset in ProviderPreset.allCases {
            XCTAssertFalse(
                preset.provider.suggestedModel.isEmpty,
                "Preset \(preset) should suggest a starting model"
            )
        }
    }

    func testDeepSeekPresetEndpoint() {
        let provider = ProviderPreset.deepseek.provider
        XCTAssertEqual(provider.baseURL, "https://api.deepseek.com")
        XCTAssertEqual(provider.suggestedModel, "deepseek-v4-pro")
    }

    func testClinePassPresetUsesCatalogNotFetch() {
        let preset = ProviderPreset.clinePass
        XCTAssertFalse(preset.supportsModelListingFetch)
        XCTAssertTrue(preset.usesCatalogModels)
        XCTAssertEqual(preset.provider.id, "clinepass")
        XCTAssertEqual(preset.provider.baseURL, "https://api.cline.bot/api/v1")
        XCTAssertEqual(preset.provider.suggestedModel, "cline-pass/glm-5.2")
        XCTAssertEqual(
            preset.catalogDocumentationURL?.absoluteString,
            ClinePassCatalog.documentationURL.absoluteString
        )
        XCTAssertEqual(preset.catalogModelIDs, ClinePassCatalog.modelIDs)
        XCTAssertEqual(preset.catalogModels.count, ClinePassCatalog.models.count)
    }

    func testClinePassCatalogMatchesDocumentationModelsTable() {
        let expected: [(String, String)] = [
            ("GLM-5.2", "cline-pass/glm-5.2"),
            ("Kimi K2.7 Code", "cline-pass/kimi-k2.7-code"),
            ("Kimi K2.6", "cline-pass/kimi-k2.6"),
            ("DeepSeek V4 Pro", "cline-pass/deepseek-v4-pro"),
            ("DeepSeek V4 Flash", "cline-pass/deepseek-v4-flash"),
            ("MiMo-V2.5", "cline-pass/mimo-v2.5"),
            ("MiMo-V2.5-Pro", "cline-pass/mimo-v2.5-pro"),
            ("MiniMax M3", "cline-pass/minimax-m3"),
            ("Qwen3.7 Max", "cline-pass/qwen3.7-max"),
            ("Qwen3.7 Plus", "cline-pass/qwen3.7-plus"),
        ]
        XCTAssertEqual(ClinePassCatalog.models.count, expected.count)
        for (index, pair) in expected.enumerated() {
            XCTAssertEqual(ClinePassCatalog.models[index].name, pair.0, "row \(index + 1) name")
            XCTAssertEqual(ClinePassCatalog.models[index].modelID, pair.1, "row \(index + 1) id")
        }
        XCTAssertEqual(
            ClinePassCatalog.fetchedModels.first?.ownedBy,
            "GLM-5.2"
        )
    }

    func testSuggestedIDForClinePassModel() {
        XCTAssertEqual(CustomModel.suggestedID(from: "cline-pass/glm-5.2"), "cline-pass-glm-5.2")
    }

    func testClinePassDisplayNamePrefixesCline() {
        XCTAssertEqual(ClinePassCatalog.displayName(for: "Kimi K2.7 Code"), "Cline Kimi K2.7 Code")
        XCTAssertEqual(ClinePassCatalog.displayName(for: "GLM-5.2"), "Cline GLM-5.2")
        XCTAssertEqual(ClinePassCatalog.displayName(for: "Cline GLM-5.2"), "Cline GLM-5.2")
    }

    func testProviderCatalogFlagsFromMatchingPreset() {
        let cline = ProviderPreset.clinePass.provider
        XCTAssertTrue(cline.usesCatalogModels)
        XCTAssertFalse(cline.supportsModelListingFetch)
        XCTAssertEqual(cline.catalogModelIDs.count, 10)

        let zai = ProviderPreset.zai.provider
        XCTAssertFalse(zai.usesCatalogModels)
        XCTAssertTrue(zai.supportsModelListingFetch)
    }

    func testOpenAIPresetEndpoint() {
        let provider = ProviderPreset.openai.provider
        XCTAssertEqual(provider.id, "openai")
        XCTAssertEqual(provider.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(provider.suggestedModel, "gpt-4o")
    }

    func testModelResolvesEndpointAndKeyFromProvider() {
        let provider = Provider(
            id: "zai",
            name: "Z.ai",
            baseURL: "https://api.z.ai/api/coding/paas/v4",
            apiKey: "sk-shared",
            suggestedModel: "glm-5.2"
        )
        // Two models share one provider — multiple models, same provider.
        let modelA = CustomModel(id: "glm-5", model: "glm-5.2", baseURL: "", providerID: "zai")
        let modelB = CustomModel(id: "glm-4", model: "glm-4.7", baseURL: "", providerID: "zai")

        let resolvedA = modelA.resolved(using: [provider])
        let resolvedB = modelB.resolved(using: [provider])

        XCTAssertEqual(resolvedA.baseURL, "https://api.z.ai/api/coding/paas/v4")
        XCTAssertEqual(resolvedA.apiKey, "sk-shared")
        XCTAssertEqual(resolvedB.baseURL, "https://api.z.ai/api/coding/paas/v4")
        XCTAssertEqual(resolvedB.apiKey, "sk-shared")

        // Both serialize to distinct [model.*] tables sharing the same base_url.
        let toml = CustomModelStore.rewrite("", models: [resolvedA, resolvedB], defaultModelID: nil)
        let reparsed = CustomModelStore.parse(toml)
        XCTAssertEqual(reparsed.models.count, 2)
        XCTAssertEqual(Set(reparsed.models.map { $0.baseURL }), ["https://api.z.ai/api/coding/paas/v4"])
    }

    func testModelWithoutProviderIsUnchangedByResolution() {
        let model = CustomModel(id: "m", model: "x", baseURL: "https://x/v1", apiKey: "sk-1")
        XCTAssertEqual(model.resolved(using: []), model)
    }

    func testKeylessProviderDoesNotWipeModelKey() {
        // A provider with no credential must not clobber a key already on the model.
        let provider = Provider(id: "minimax", name: "MiniMax", baseURL: "https://api.minimax.io/v1")
        let model = CustomModel(
            id: "minimax-m2.5",
            model: "MiniMax-M2.5",
            baseURL: "https://api.minimax.io/v1",
            apiKey: "sk-real-key",
            providerID: "minimax"
        )
        let resolved = model.resolved(using: [provider])
        XCTAssertEqual(resolved.apiKey, "sk-real-key", "model's own key must survive")
        XCTAssertTrue(resolved.hasInlineKey)
        // Base URL still comes from the provider.
        XCTAssertEqual(resolved.baseURL, "https://api.minimax.io/v1")
    }

    func testProviderWithKeyOverridesModel() {
        let provider = Provider(
            id: "minimax",
            name: "MiniMax",
            baseURL: "https://api.minimax.io/v1",
            apiKey: "sk-provider"
        )
        let model = CustomModel(id: "m", model: "x", baseURL: "", apiKey: "", providerID: "minimax")
        let resolved = model.resolved(using: [provider])
        XCTAssertEqual(resolved.apiKey, "sk-provider")
    }

    func testProviderStoreRoundTrips() {
        let key = "grokbuild.customModelProviders"
        let saved = UserDefaults.standard.data(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        let providers = [
            ProviderPreset.kimi.provider,
            Provider(id: "custom", name: "Custom", baseURL: "https://x/v1", apiKey: "sk-z")
        ]
        ProviderStore.save(providers)
        XCTAssertEqual(ProviderStore.load(), providers)
    }

    // MARK: - ProviderModelFetcher

    func testModelsURLAppendsModelsPreservingVersionSuffix() {
        XCTAssertEqual(
            ProviderModelFetcher.modelsURL(for: "https://api.moonshot.ai/v1")?.absoluteString,
            "https://api.moonshot.ai/v1/models"
        )
        // DeepSeek's base has no /v1 — must not be invented.
        XCTAssertEqual(
            ProviderModelFetcher.modelsURL(for: "https://api.deepseek.com")?.absoluteString,
            "https://api.deepseek.com/models"
        )
        // Qwen's compatible-mode path is preserved.
        XCTAssertEqual(
            ProviderModelFetcher.modelsURL(for: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1")?.absoluteString,
            "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/models"
        )
    }

    func testModelsURLTrimsTrailingSlashAndWhitespace() {
        XCTAssertEqual(
            ProviderModelFetcher.modelsURL(for: "  https://api.z.ai/api/coding/paas/v4/  ")?.absoluteString,
            "https://api.z.ai/api/coding/paas/v4/models"
        )
    }

    func testModelsURLRejectsEmpty() {
        XCTAssertNil(ProviderModelFetcher.modelsURL(for: "   "))
    }

    func testResolveKeyReturnsInlineOrNil() {
        XCTAssertEqual(ProviderModelFetcher.resolveKey(apiKey: "sk-inline"), "sk-inline")
        XCTAssertEqual(ProviderModelFetcher.resolveKey(apiKey: "  sk-trim  "), "sk-trim")
        XCTAssertNil(ProviderModelFetcher.resolveKey(apiKey: "   "))
        XCTAssertNil(ProviderModelFetcher.resolveKey(apiKey: ""))
    }

    func testParseModelsOpenAIShape() {
        let json = """
        {
          "object": "list",
          "data": [
            { "id": "kimi-k2.6", "object": "model", "owned_by": "moonshot" },
            { "id": "kimi-k2.5", "object": "model", "owned_by": "moonshot" },
            { "id": "kimi-k2.6", "object": "model" }
          ]
        }
        """.data(using: .utf8)!

        let models = ProviderModelFetcher.parse(json)
        XCTAssertNotNil(models)
        // De-duplicated and sorted case-insensitively.
        XCTAssertEqual(models?.map { $0.id }, ["kimi-k2.5", "kimi-k2.6"])
        XCTAssertEqual(models?.first(where: { $0.id == "kimi-k2.5" })?.ownedBy, "moonshot")
    }

    func testParseModelsAcceptsBareArrayAndModelKey() {
        let json = """
        [ { "model": "local-llama" }, { "id": "" }, { "foo": "bar" } ]
        """.data(using: .utf8)!
        let models = ProviderModelFetcher.parse(json)
        XCTAssertEqual(models?.map { $0.id }, ["local-llama"])
    }

    func testParseModelsRejectsGarbage() {
        XCTAssertNil(ProviderModelFetcher.parse(Data("not json".utf8)))
    }
}
