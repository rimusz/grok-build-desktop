import Foundation

/// Drops ACP / telemetry JSON that leaked into assistant prose.
///
/// grok sometimes streams `ToolCallUpdate` objects (or mid-object fragments)
/// as `agent_message_chunk` text or as non-JSON-RPC stdout. Those must not
/// appear in the transcript.
enum AssistantTranscriptSanitizer {
    static func isProtocolNoise(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return containsProtocolMarkers(trimmed)
    }

    /// Incomplete JSON-RPC leftovers on stdout should never become a bubble.
    static func shouldDropRawLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "[process stopped]" { return false }
        if isProtocolNoise(trimmed) { return true }
        if trimmed.hasPrefix("{") { return true }
        if trimmed.hasPrefix("[{") || trimmed.hasPrefix("[\"") { return true }
        return looksLikeJSONFragment(trimmed)
    }

    static func usableChunk(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return text.isEmpty ? nil : text }
        let stripped = strip(text)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : stripped
    }

    static func strip(_ text: String) -> String {
        var remaining = text
        while let range = firstProtocolJSONRange(in: remaining) {
            remaining.removeSubrange(range)
        }
        if let cut = unclosedProtocolJSONStart(in: remaining) {
            remaining = String(remaining[..<cut])
        }
        let kept = remaining
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !isProtocolNoise(trimmed) && !looksLikeJSONFragment(trimmed)
            }
            .joined(separator: "\n")
        let trimmedKept = kept.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKept.isEmpty { return "" }
        if isProtocolNoise(kept) || looksLikeJSONFragment(trimmedKept) {
            return ""
        }
        return collapseBlankLines(kept)
    }

    static func sanitized(_ message: Message) -> Message {
        guard message.role == .assistant else { return message }
        let strippedContent = strip(message.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = message.parts.compactMap { part -> TranscriptPart? in
            switch part {
            case .text(let value):
                let cleaned = strip(value)
                return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .text(cleaned)
            case .activity(let line):
                let refreshed = GrokActivitySummary.refreshSummary(line.summary)
                return .activity(
                    GrokActivityLine(
                        summary: refreshed,
                        hookCount: line.hookCount,
                        isLead: line.isLead
                    )
                )
            }
        }
        let joined = parts.compactMap(\.text).joined()
        return Message(
            id: message.id,
            role: message.role,
            content: joined.isEmpty ? strippedContent : joined,
            timestamp: message.timestamp,
            parts: parts
        )
    }

    /// Sanitize assistant text and drop bubbles that were only protocol noise.
    static func cleanedTranscript(_ messages: [Message]) -> [Message] {
        messages.compactMap { message in
            let cleaned = sanitized(message)
            if cleaned.role == .assistant,
               cleaned.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !cleaned.hasActivityParts {
                return nil
            }
            return cleaned
        }
    }

    // MARK: - Markers

    private static func containsProtocolMarkers(_ text: String) -> Bool {
        if text.contains("ToolCallUpdate") { return true }
        if text.contains("\"updateParams\"") { return true }
        if text.contains("\"agentTimestampMs\"") { return true }
        if text.contains("\"streamStartMs\"") { return true }
        if text.contains("\"turnStartMs\"") { return true }
        if text.contains("\"updateType\"") { return true }
        if text.contains("\"jsonrpc\"")
            && (text.contains("\"method\"") || text.contains("\"result\"")) {
            return true
        }
        if text.contains("\"toolCallId\"") && text.contains("\"status\"") {
            return true
        }
        return false
    }

    private static func looksLikeJSONFragment(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if containsProtocolMarkers(text) { return true }
        if text.contains("\":\"") && text.contains("}")
            && (text.contains("\"status\"") || text.contains("Completed")) {
            return true
        }
        return false
    }

    /// Drop an unclosed `{…` protocol object so preceding prose is kept.
    private static func unclosedProtocolJSONStart(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "{", matchingBrace(from: index, in: text) == nil {
                if containsProtocolMarkers(String(text[index...])) {
                    return index
                }
            }
            text.formIndex(after: &index)
        }
        return nil
    }

    private static func firstProtocolJSONRange(in text: String) -> Range<String.Index>? {
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "{",
               let end = matchingBrace(from: index, in: text) {
                let slice = String(text[index...end])
                if containsProtocolMarkers(slice) {
                    return index..<text.index(after: end)
                }
                index = text.index(after: end)
                continue
            }
            text.formIndex(after: &index)
        }
        return nil
    }

    private static func matchingBrace(from start: String.Index, in text: String) -> String.Index? {
        var depth = 0
        var index = start
        var inString = false
        var escape = false
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escape {
                    escape = false
                } else if character == "\\" {
                    escape = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            text.formIndex(after: &index)
        }
        return nil
    }

    private static func collapseBlankLines(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var pendingBlank = false
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                pendingBlank = !result.isEmpty
                continue
            }
            if pendingBlank {
                result.append("")
                pendingBlank = false
            }
            result.append(line)
        }
        return result.joined(separator: "\n")
    }
}
