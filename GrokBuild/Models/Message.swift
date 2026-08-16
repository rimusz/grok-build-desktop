import Foundation

enum MessageRole: String, Codable, Sendable {
    case user, assistant, system
}

struct Message: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    /// Interleaved assistant text and CLI-style working lines. Empty on older saves.
    var parts: [TranscriptPart]

    var hasDiff: Bool {
        guard role == .assistant else { return false }
        return content.contains("diff --git") ||
               content.contains("```diff") ||
               content.contains("```patch")
    }

    var hasActivityParts: Bool {
        parts.contains(where: \.isActivity)
    }

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        parts: [TranscriptPart] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.parts = parts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        parts = try container.decodeIfPresent([TranscriptPart].self, forKey: .parts) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        if !parts.isEmpty {
            try container.encode(parts, forKey: .parts)
        }
    }

    /// Keep activity lines when grok jsonl supplies a longer assistant tail.
    mutating func replaceContent(_ extended: String) {
        if parts.isEmpty {
            content = extended
            return
        }
        parts = GrokActivityLog.align(parts, toContent: extended)
        content = extended
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, parts
    }
}

extension Array where Element == Message {
    /// Combined length of user + assistant text. Used to prefer a longer grok
    /// jsonl transcript over a locally persisted copy that missed the last chunks.
    var conversationCharacterCount: Int {
        reduce(0) { partial, message in
            guard message.role == .user || message.role == .assistant else { return partial }
            return partial + message.content.count
        }
    }
}
