import Foundation

/// Repairs empty or **truncated** GrokBuild tabs from grok CLI `chat_history.jsonl`.
enum SessionTranscriptRecovery {
    /// Minimum shared prefix/suffix used to splice a truncated bubble onto grok's last assistant.
    static let minimumAssistantOverlap = 24

    /// Returns imported or tail-extended messages when recovery ran; `nil` when not needed.
    static func recoverIfNeeded(
        sessionID: UUID,
        grokSessionID: String?,
        workspacePath: URL,
        currentMessages: [Message]
    ) -> [Message]? {
        guard let imported = importMessages(
            grokSessionID: grokSessionID,
            workspacePath: workspacePath
        ) else { return nil }

        guard let merged = mergeLongerTranscript(current: currentMessages, imported: imported) else {
            return nil
        }

        SessionMessageStore.save(merged, for: sessionID)
        return merged
    }

    static func importMessages(grokSessionID: String?, workspacePath: URL) -> [Message]? {
        guard let grokSessionID,
              let historyURL = GrokSessionTranscriptImporter.chatHistoryURL(
                  workspacePath: workspacePath,
                  grokSessionID: grokSessionID
              ),
              GrokSessionTranscriptImporter.hasRecoverableTranscript(at: historyURL) else {
            return nil
        }
        let imported = GrokSessionTranscriptImporter.importMessages(from: historyURL)
        return imported.isEmpty ? nil : imported
    }

    /// Empty tabs take the jsonl transcript. A user prompt with no assistant appends
    /// imported assistants (crash / early persist). Otherwise only extend the last
    /// assistant when grok's last assistant is a longer continuation — do not replace
    /// a complete bubble just because jsonl also has bootstrap `user_info` rows.
    static func mergeLongerTranscript(current: [Message], imported: [Message]) -> [Message]? {
        guard let importedLast = imported.last(where: {
            $0.role == .assistant && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { return nil }

        if SessionMessageStore.needsTranscriptRecovery(current) {
            return imported
        }

        guard let currentIdx = current.lastIndex(where: { $0.role == .assistant }) else {
            let importedAssistants = imported.filter {
                $0.role == .assistant && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard !importedAssistants.isEmpty else { return nil }
            return current + importedAssistants
        }
        guard let extended = extendedAssistantContent(
            current: current[currentIdx].content,
            imported: importedLast.content
        ) else { return nil }

        var updated = current
        updated[currentIdx].replaceContent(extended)
        return updated
    }

    /// Weave CLI working lines from `updates.jsonl` onto assistant messages that lack them.
    static func attachActivityIfNeeded(
        messages: [Message],
        grokSessionID: String?,
        workspacePath: URL
    ) -> [Message] {
        let messages = AssistantTranscriptSanitizer.cleanedTranscript(messages)
        guard let grokSessionID,
              let updatesURL = GrokActivityLog.updatesURL(
                  workspacePath: workspacePath,
                  grokSessionID: grokSessionID
              ),
              FileManager.default.fileExists(atPath: updatesURL.path) else {
            return messages
        }
        let turns = GrokActivityLog.turns(from: updatesURL)
        return attachActivity(messages: messages, turns: turns)
    }

    /// Pair each assistant bubble with the same-index `updates.jsonl` turn.
    /// Do not compact away turns that have no tools — that slides a later
    /// activity line onto an earlier text-only answer.
    static func attachActivity(messages: [Message], turns: [GrokActivityLog.Turn]) -> [Message] {
        guard !turns.isEmpty else { return messages }
        var updated = messages
        let assistantIndexes = updated.indices.filter { updated[$0].role == .assistant }
        guard !assistantIndexes.isEmpty else { return messages }

        let activityTurns = turns.filter { $0.parts.contains(where: \.isActivity) }
        guard !activityTurns.isEmpty else { return messages }

        if assistantIndexes.count == 1, let idx = assistantIndexes.first, activityTurns.count == 1 {
            updated[idx].parts = GrokActivityLog.align(activityTurns[0].parts, toContent: updated[idx].content)
            return AssistantTranscriptSanitizer.cleanedTranscript(updated)
        }

        for (assistantIdx, turn) in zip(assistantIndexes, turns) {
            guard turn.parts.contains(where: \.isActivity) else { continue }
            updated[assistantIdx].parts = GrokActivityLog.align(
                turn.parts,
                toContent: updated[assistantIdx].content
            )
        }
        return AssistantTranscriptSanitizer.cleanedTranscript(updated)
    }

    /// Prefer grok's jsonl when it has more user/assistant text than the local tab.
    /// Used for empty-tab decisions; live tails use `extendedAssistantContent`.
    static func shouldReplace(current: [Message], with imported: [Message]) -> Bool {
        let importedChars = imported.conversationCharacterCount
        guard importedChars > 0 else { return false }
        return importedChars > current.conversationCharacterCount
    }

    /// Extends a streamed assistant bubble from grok's last jsonl assistant.
    ///
    /// Handles a straight prefix (ACP stopped early) and the common case where two
    /// jsonl assistant rows were concatenated into one bubble (`preamble + truncated`).
    static func extendedAssistantContent(current: String, imported: String) -> String? {
        if imported == current { return nil }
        if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        if imported.hasPrefix(current), imported.count > current.count {
            return imported
        }
        guard let overlap = longestImportedPrefixAsSuffix(of: current, imported: imported),
              imported.count > overlap else {
            return nil
        }
        return String(current.dropLast(overlap)) + imported
    }

    static func longestImportedPrefixAsSuffix(of current: String, imported: String) -> Int? {
        let maxLen = min(current.count, imported.count)
        let minLen = min(minimumAssistantOverlap, maxLen)
        guard minLen > 0 else { return nil }
        for len in stride(from: maxLen, through: minLen, by: -1) {
            if current.hasSuffix(imported.prefix(len)) {
                return len
            }
        }
        return nil
    }
}

/// Where a trailing `agent_message_chunk` should land after `session/prompt` returns.
enum LateAssistantChunkRouting {
    enum Destination: Equatable {
        case streaming(UUID)
        case late(UUID)
    }

    /// Keep leftover chunks on the completed assistant until the next
    /// `session/prompt` send begins. A longer jsonl reconcile must not close
    /// that window — ACP may still flush more text than disk has written.
    static func destination(
        streamingID: UUID?,
        currentPromptSendBegun: Bool,
        lateUntil: Date?,
        previousAssistantID: UUID?,
        now: Date = Date()
    ) -> Destination? {
        let lateOpen = lateUntil.map { now < $0 } ?? false
        if let streamingID {
            if !currentPromptSendBegun,
               lateOpen,
               let previousAssistantID,
               previousAssistantID != streamingID {
                return .late(previousAssistantID)
            }
            return .streaming(streamingID)
        }
        if lateOpen, let previousAssistantID {
            return .late(previousAssistantID)
        }
        return nil
    }
}

enum FailedPromptCleanup {
    /// Keep a failed turn that recorded CLI working lines even when no
    /// assistant text streamed.
    static func shouldDiscardEmptyAssistant(content: String, hasActivityParts: Bool) -> Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasActivityParts
    }
}
