import Foundation

/// Per-turn token metering from grok ACP (`session/prompt` result `_meta`, or the same
/// camelCase keys on `session/update`). Distinct from the context-window gauge
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

/// Parses grok's ACP usage dialect and the draft ACP `usage` object.
///
/// Precedence matches other grok ACP clients: top-level `usage` when it has
/// breakdown keys, then `_meta.usage`, then flat `_meta` camelCase counters.
enum TurnTokenUsageParser {
    static func parse(from json: [String: Any]) -> TurnTokenUsage? {
        if let usage = json["usage"] as? [String: Any],
           let parsed = fromTokenBag(usage), parsed.hasBreakdown {
            return parsed
        }
        if let meta = json["_meta"] as? [String: Any] {
            if let nested = meta["usage"] as? [String: Any],
               let parsed = fromTokenBag(nested), parsed.hasBreakdown {
                return parsed
            }
            if let parsed = fromTokenBag(meta), parsed.hasBreakdown {
                return parsed
            }
        }
        if let parsed = fromTokenBag(json), parsed.hasBreakdown {
            return parsed
        }
        return nil
    }

    /// `session/update` params: `_meta` on the params or on `update`.
    static func parse(fromSessionUpdate params: [String: Any]) -> TurnTokenUsage? {
        if let parsed = parse(from: params) { return parsed }
        if let update = params["update"] as? [String: Any] {
            return parse(from: update)
        }
        return nil
    }

    private static func fromTokenBag(_ bag: [String: Any]) -> TurnTokenUsage? {
        TurnTokenUsage(
            inputTokens: int(bag, keys: ["inputTokens", "input_tokens"]),
            outputTokens: int(bag, keys: ["outputTokens", "output_tokens"]),
            cachedReadTokens: int(bag, keys: [
                "cachedReadTokens",
                "cached_read_tokens",
                "cacheReadTokens",
                "cache_read_input_tokens",
                "cached_tokens"
            ]),
            reasoningTokens: int(bag, keys: [
                "reasoningTokens",
                "reasoning_tokens",
                "thoughtTokens",
                "thought_tokens"
            ]),
            totalTokens: int(bag, keys: ["totalTokens", "total_tokens"])
        )
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
