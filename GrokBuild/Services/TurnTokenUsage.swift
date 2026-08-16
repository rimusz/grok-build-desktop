import Foundation

/// Per-turn token metering from grok ACP (`session/prompt` result `_meta`,
/// `_x.ai/session_notification` `turn_completed` / `response_completed`, or the
/// same keys on `session/update`). Distinct from the context-window gauge
/// (`_meta.totalTokens` on updates → `AcpEvent.contextUsage`).
struct TurnTokenUsage: Sendable, Equatable {
    var inputTokens: Int?
    var outputTokens: Int?
    var cachedReadTokens: Int?
    var reasoningTokens: Int?
    var totalTokens: Int?

    /// True when grok reported at least one per-turn bucket (not just a context total).
    var hasBreakdown: Bool {
        inputTokens != nil
            || outputTokens != nil
            || cachedReadTokens != nil
            || reasoningTokens != nil
    }
}

/// Parses grok's ACP usage dialect, xAI session notifications, and OpenAI-style bags.
///
/// Precedence: top-level `usage` when it has breakdown keys, then `_meta.usage`,
/// then flat `_meta` / object camelCase counters. `JSONSerialization` nested
/// `NSDictionary` values are accepted (Swift `as? [String: Any]` often fails there).
///
/// `inputTokens` (PromptUsage) and OpenAI `prompt_tokens` are the full prompt
/// including cache. grok snake-case `input_tokens` is uncached-only and is added
/// to cache hits so the popover percent is `cached / full input`.
enum TurnTokenUsageParser {
    static func parse(from json: [String: Any]) -> TurnTokenUsage? {
        parse(fromAny: json)
    }

    static func parse(fromAny value: Any?) -> TurnTokenUsage? {
        guard let json = dictionary(value) else { return nil }
        if let parsed = fromTokenBag(dictionary(json["usage"]) ?? [:]), parsed.hasBreakdown {
            return parsed
        }
        if let meta = dictionary(json["_meta"]) {
            if let parsed = fromTokenBag(dictionary(meta["usage"]) ?? [:]), parsed.hasBreakdown {
                return parsed
            }
            if let parsed = fromTokenBag(meta), parsed.hasBreakdown {
                return parsed
            }
        }
        if let parsed = fromTokenBag(json), parsed.hasBreakdown {
            return parsed
        }
        if let result = json["result"] {
            return parse(fromAny: result)
        }
        return nil
    }

    /// `session/update` or `_x.ai/session_notification` params: `_meta` on the
    /// params or on `update`.
    static func parse(fromSessionUpdate params: [String: Any]) -> TurnTokenUsage? {
        parse(fromAny: params)
            ?? parse(fromAny: params["update"])
    }

    static func parse(fromSessionUpdateAny value: Any?) -> TurnTokenUsage? {
        guard let params = dictionary(value) else { return nil }
        return parse(fromSessionUpdate: params)
    }

    private static func fromTokenBag(_ bag: [String: Any]) -> TurnTokenUsage? {
        let cached = int(bag, keys: [
            "cachedReadTokens",
            "cached_read_tokens",
            "cacheReadTokens",
            "cacheReadInputTokens",
            "cache_read_input_tokens",
            "cached_tokens"
        ]) ?? cachedFromPromptDetails(bag)

        let fullInput = int(bag, keys: ["inputTokens", "prompt_tokens"])
        let uncachedInput = int(bag, keys: ["input_tokens"])
        let input: Int?
        if let fullInput {
            input = fullInput
        } else if let uncachedInput {
            input = cached.map { uncachedInput + $0 } ?? uncachedInput
        } else {
            input = nil
        }

        return TurnTokenUsage(
            inputTokens: input,
            outputTokens: int(bag, keys: ["outputTokens", "output_tokens", "completion_tokens"]),
            cachedReadTokens: cached,
            reasoningTokens: int(bag, keys: [
                "reasoningTokens",
                "reasoning_tokens",
                "thoughtTokens",
                "thought_tokens"
            ]),
            totalTokens: int(bag, keys: ["totalTokens", "total_tokens"])
        )
    }

    private static func cachedFromPromptDetails(_ bag: [String: Any]) -> Int? {
        let details = dictionary(bag["prompt_tokens_details"])
            ?? dictionary(bag["promptTokensDetails"])
        return int(details ?? [:], keys: ["cached_tokens", "cachedTokens"])
    }

    static func dictionary(_ value: Any?) -> [String: Any]? {
        if let typed = value as? [String: Any] { return typed }
        guard let ns = value as? NSDictionary else { return nil }
        var out: [String: Any] = [:]
        out.reserveCapacity(ns.count)
        for (key, val) in ns {
            guard let stringKey = key as? String else { continue }
            out[stringKey] = val
        }
        return out
    }

    private static func int(_ bag: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = bag[key], let parsed = intValue(value) {
                return parsed
            }
        }
        return nil
    }

    private static func intValue(_ value: Any) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String { return Int(s) }
        return nil
    }
}
