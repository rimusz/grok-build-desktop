import Foundation

enum MessageRole: String, Codable, Sendable {
    case user, assistant, system
}

struct Message: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date

    var hasDiff: Bool {
        guard role == .assistant else { return false }
        return content.contains("diff --git") ||
               content.contains("```diff") ||
               content.contains("```patch")
    }

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
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
