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
