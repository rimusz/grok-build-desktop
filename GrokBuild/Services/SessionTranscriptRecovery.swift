import Foundation

/// Repairs empty or stale-fallback GrokBuild tabs from grok CLI `chat_history.jsonl`.
enum SessionTranscriptRecovery {
    /// Returns imported messages when recovery ran; `nil` when not needed or not possible.
    static func recoverIfNeeded(
        sessionID: UUID,
        grokSessionID: String?,
        workspacePath: URL,
        currentMessages: [Message]
    ) -> [Message]? {
        guard let grokSessionID,
              SessionMessageStore.needsTranscriptRecovery(currentMessages),
              let historyURL = GrokSessionTranscriptImporter.chatHistoryURL(
                  workspacePath: workspacePath,
                  grokSessionID: grokSessionID
              ),
              GrokSessionTranscriptImporter.hasRecoverableTranscript(at: historyURL) else {
            return nil
        }

        let imported = GrokSessionTranscriptImporter.importMessages(from: historyURL)
        let importedCount = GrokSessionTranscriptImporter.conversationMessageCount(imported)
        let localCount = GrokSessionTranscriptImporter.conversationMessageCount(currentMessages)
        guard importedCount > localCount else { return nil }

        SessionMessageStore.save(imported, for: sessionID)
        return imported
    }
}
