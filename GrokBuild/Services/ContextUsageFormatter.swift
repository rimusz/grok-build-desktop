import Foundation

/// Formats context-window usage and last-turn token buckets for the composer's
/// context popover. Billed USD is not exposed over ACP, so this reports tokens only.
enum ContextUsageFormatter {
    /// e.g. "12,000 / 200,000 tokens", or "— / 200,000 tokens" when usage is unknown.
    static func summary(used: Int?, limit: Int?) -> String {
        let usedText = used.map(decimal) ?? "—"
        let limitText = limit.map(decimal) ?? "—"
        return "\(usedText) / \(limitText) tokens"
    }

    /// Whole-percent usage (0…100), or nil when it can't be computed.
    static func percent(used: Int?, limit: Int?) -> Int? {
        guard let limit, limit > 0, let used else { return nil }
        return min(100, max(0, Int((Double(used) / Double(limit) * 100).rounded())))
    }

    /// Cache-hit share of the last-turn prompt (`cached / input`), or nil when unknown.
    static func cachePercent(cached: Int?, input: Int?) -> Int? {
        guard let cached, let input, input > 0 else { return nil }
        return min(100, max(0, Int((Double(cached) / Double(input) * 100).rounded())))
    }

    /// Formatted count, or "—" when missing.
    static func tokenCount(_ value: Int?) -> String {
        value.map(decimal) ?? "—"
    }

    /// e.g. "7,639 cached (64%)", or "0 cached" on a miss. Nil when grok omitted the field.
    static func cachedLine(cached: Int?, input: Int?) -> String? {
        guard let cached else { return nil }
        if let percent = cachePercent(cached: cached, input: input) {
            return "\(decimal(cached)) cached (\(percent)%)"
        }
        return "\(decimal(cached)) cached"
    }

    static func decimal(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
