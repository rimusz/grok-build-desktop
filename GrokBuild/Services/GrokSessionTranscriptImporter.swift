import Foundation

/// Imports user/assistant text from grok CLI on-disk `chat_history.jsonl` files.
enum GrokSessionTranscriptImporter {
    static var grokHomeDirectory = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".grok", isDirectory: true)

    static func chatHistoryURL(workspacePath: URL, grokSessionID: String) -> URL? {
        let trimmedID = grokSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return nil }
        let encoded = encodeWorkspacePath(workspacePath)
        return grokHomeDirectory
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(encoded, isDirectory: true)
            .appendingPathComponent(trimmedID, isDirectory: true)
            .appendingPathComponent("chat_history.jsonl")
    }

    static func hasRecoverableTranscript(at url: URL) -> Bool {
        guard let messages = try? loadMessages(from: url) else { return false }
        return conversationMessageCount(messages) > 0
    }

    static func importMessages(from url: URL) -> [Message] {
        (try? loadMessages(from: url)) ?? []
    }

    static func conversationMessageCount(_ messages: [Message]) -> Int {
        messages.filter { $0.role == .user || $0.role == .assistant }.count
    }

    // MARK: - Path encoding

    /// grok stores sessions under `~/.grok/sessions/%2FUsers%2F…%2Fproject` (no trailing `%2F`).
    static func encodeWorkspacePath(_ workspacePath: URL) -> String {
        var path = workspacePath.standardizedFileURL.path
        while path.hasSuffix("/"), path.count > 1 {
            path.removeLast()
        }
        let body = String(path.dropFirst()).replacingOccurrences(of: "/", with: "%2F")
        return "%2F" + body
    }

    // MARK: - JSONL parsing

    private static func loadMessages(from url: URL) throws -> [Message] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var messages: [Message] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = row["type"] as? String else { continue }

            switch type {
            case "user":
                guard let content = extractUserText(from: row["content"]),
                      !content.isEmpty,
                      !isSyntheticSystemReminderOnly(content) else { continue }
                messages.append(Message(role: .user, content: content))
            case "assistant":
                guard let content = extractAssistantText(from: row["content"]) else { continue }
                let cleaned = AssistantTranscriptSanitizer.strip(stripThinkingTags(from: content))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { continue }
                messages.append(Message(role: .assistant, content: cleaned))
            default:
                continue
            }
        }
        return messages
    }

    private static func extractUserText(from value: Any?) -> String? {
        if let text = value as? String {
            return normalizeUserText(text)
        }
        guard let parts = value as? [[String: Any]] else { return nil }
        let joined = parts.compactMap { part -> String? in
            guard (part["type"] as? String) == "text" else { return nil }
            return part["text"] as? String
        }.joined(separator: "\n")
        let normalized = normalizeUserText(joined)
        return normalized.isEmpty ? nil : normalized
    }

    private static func extractAssistantText(from value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        if let parts = value as? [[String: Any]] {
            let joined = parts.compactMap { part -> String? in
                guard (part["type"] as? String) == "text" else { return nil }
                return part["text"] as? String
            }.joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private static func normalizeUserText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let query = extractTaggedContent(trimmed, tag: "user_query") {
            return query.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private static func extractTaggedContent(_ text: String, tag: String) -> String? {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard let start = text.range(of: open),
              let end = text.range(of: close, range: start.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[start.upperBound..<end.lowerBound])
    }

    private static func isSyntheticSystemReminderOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<system-reminder>")
            && trimmed.hasSuffix("</system-reminder>")
    }

    private static func stripThinkingTags(from text: String) -> String {
        let openTag = "<" + "redacted_thinking" + ">"
        let closeTag = "</" + "redacted_thinking" + ">"
        var result = text
        while let start = result.range(of: openTag),
              let end = result.range(of: closeTag, range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
