import Foundation

/// Persists chat transcript per live session tab (keyed by `LiveSession.id`).
/// Grok keeps conversation state server-side; this restores what the UI showed last time.
enum SessionMessageStore {
    private static let key = "GrokBuild.sessionMessages.v1"

    static func messages(for sessionID: UUID) -> [Message] {
        guard let data = blob(for: sessionID) else { return [] }
        return (try? JSONDecoder().decode([Message].self, from: data)) ?? []
    }

    static func save(_ messages: [Message], for sessionID: UUID) {
        var map = loadMap()
        let existing = Self.messages(for: sessionID)
        let persistable = messages.filter { shouldPersist($0) }
        let merged = mergeTranscripts(existing: existing, incoming: persistable)
        if merged.isEmpty {
            map.removeValue(forKey: sessionID.uuidString)
        } else if let data = try? JSONEncoder().encode(merged) {
            map[sessionID.uuidString] = data
        }
        UserDefaults.standard.set(map, forKey: key)
    }

    /// Never drop a longer on-disk transcript when memory is temporarily empty or partial.
    private static func mergeTranscripts(existing: [Message], incoming: [Message]) -> [Message] {
        guard !existing.isEmpty else { return incoming }
        guard !incoming.isEmpty else { return existing }
        if incoming.count >= existing.count { return incoming }

        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for message in incoming {
            byID[message.id] = message
        }
        var merged: [Message] = []
        var seen: Set<UUID> = []
        for message in existing {
            merged.append(byID[message.id] ?? message)
            seen.insert(message.id)
        }
        for message in incoming where !seen.contains(message.id) {
            merged.append(message)
        }
        return merged
    }

    static func messageCount(for sessionID: UUID) -> Int {
        messages(for: sessionID).filter { $0.role == .user || $0.role == .assistant }.count
    }

    static func remove(for sessionID: UUID) {
        var map = loadMap()
        map.removeValue(forKey: sessionID.uuidString)
        UserDefaults.standard.set(map, forKey: key)
    }

    /// Legacy resume notes added before message persistence — drop on load.
    static func isLegacyResumeNote(_ message: Message) -> Bool {
        guard message.role == .system else { return false }
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("Resumed session ") && text.hasSuffix(".")
    }

    /// System note shown when grok `session/load` fell back to `session/new`.
    static func isStaleSessionFallbackNote(_ message: Message) -> Bool {
        guard message.role == .system else { return false }
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("Previous grok session expired")
    }

    static func hasRestorableTranscript(for sessionID: UUID) -> Bool {
        messages(for: sessionID).contains { message in
            guard message.role == .user || message.role == .assistant else { return false }
            if message.role == .assistant,
               message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            return true
        }
    }

    /// True when local storage has no user/assistant transcript to show.
    static func needsTranscriptRecovery(_ messages: [Message]) -> Bool {
        !messages.contains { message in
            guard message.role == .user || message.role == .assistant else { return false }
            if message.role == .assistant,
               message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            return true
        }
    }

    private static func shouldPersist(_ message: Message) -> Bool {
        if isLegacyResumeNote(message) { return false }
        if isStaleSessionFallbackNote(message) { return false }
        if message.role == .assistant,
           message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    private static func blob(for sessionID: UUID) -> Data? {
        loadMap()[sessionID.uuidString]
    }

    private static func loadMap() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
    }
}
