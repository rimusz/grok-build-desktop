import Foundation

/// Repairs empty or **truncated** GrokBuild tabs from grok CLI `chat_history.jsonl`.
enum SessionTranscriptRecovery {
    /// Returns imported messages when recovery ran; `nil` when not needed or not possible.
    static func recoverIfNeeded(
        sessionID: UUID,
        grokSessionID: String?,
        workspacePath: URL,
        currentMessages: [Message]
    ) -> [Message]? {
        guard let grokSessionID,
              let historyURL = GrokSessionTranscriptImporter.chatHistoryURL(
                  workspacePath: workspacePath,
                  grokSessionID: grokSessionID
              ),
              GrokSessionTranscriptImporter.hasRecoverableTranscript(at: historyURL) else {
            return nil
        }

        let imported = GrokSessionTranscriptImporter.importMessages(from: historyURL)
        guard shouldReplace(current: currentMessages, with: imported) else { return nil }

        SessionMessageStore.save(imported, for: sessionID)
        return imported
    }

    /// Prefer grok's jsonl when it has more user/assistant text than the local tab
    /// (empty tabs, or a turn that was persisted before the last chunks arrived).
    static func shouldReplace(current: [Message], with imported: [Message]) -> Bool {
        let importedChars = imported.conversationCharacterCount
        guard importedChars > 0 else { return false }
        return importedChars > current.conversationCharacterCount
    }
}
