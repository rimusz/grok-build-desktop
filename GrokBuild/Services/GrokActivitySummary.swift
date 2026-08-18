import Foundation

/// One CLI-style working line: `Read 1 skill, Read 2 files, Listed 1 dir  [hooks: 5]`.
struct GrokActivityLine: Codable, Hashable, Sendable {
    var summary: String
    var hookCount: Int
    var isLead: Bool

    var displayText: String {
        if hookCount > 0 {
            return "\(summary)  [hooks: \(hookCount)]"
        }
        return summary
    }
}

enum TranscriptPart: Codable, Hashable, Sendable {
    case text(String)
    case activity(GrokActivityLine)

    var isActivity: Bool {
        if case .activity = self { return true }
        return false
    }

    var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, summary, hookCount, isLead
    }

    private enum Kind: String, Codable {
        case text, activity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .activity:
            self = .activity(
                GrokActivityLine(
                    summary: try container.decode(String.self, forKey: .summary),
                    hookCount: try container.decodeIfPresent(Int.self, forKey: .hookCount) ?? 0,
                    isLead: try container.decodeIfPresent(Bool.self, forKey: .isLead) ?? false
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(value, forKey: .text)
        case .activity(let line):
            try container.encode(Kind.activity, forKey: .type)
            try container.encode(line.summary, forKey: .summary)
            try container.encode(line.hookCount, forKey: .hookCount)
            try container.encode(line.isLead, forKey: .isLead)
        }
    }
}

enum GrokActivityKind: Hashable {
    case readSkill
    case readFile
    case listed
    case edited
    case searched
    case fetched
    case ran
    case computerUse
    case subagent
    case other(String)
}

/// Formats grok tool titles + hook counts the way the CLI pager does.
enum GrokActivitySummary {
    static func classify(title: String) -> GrokActivityKind? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if isPlaceholder(trimmed) { return nil }

        if lower.hasPrefix("read ") || lower.hasPrefix("reading ") {
            if looksLikeSkill(trimmed) { return .readSkill }
            return .readFile
        }
        if lower.hasPrefix("list ") || lower.hasPrefix("listed ") || lower.hasPrefix("listing ") {
            return .listed
        }
        if lower.hasPrefix("edit ") || lower.hasPrefix("edited ") || lower.hasPrefix("editing ")
            || lower.hasPrefix("write ") || lower.hasPrefix("wrote ") {
            return .edited
        }
        if lower.hasPrefix("search ") || lower.hasPrefix("searched ") || lower.hasPrefix("searching ")
            || lower.hasPrefix("grep ") || lower.hasPrefix("rg ") {
            return .searched
        }
        if lower.hasPrefix("fetch ") || lower.hasPrefix("fetched ") || lower.hasPrefix("fetching ")
            || lower.hasPrefix("fetch") {
            return .fetched
        }
        if lower.hasPrefix("ran ") || lower.hasPrefix("running ") || lower.hasPrefix("execute ")
            || lower.hasPrefix("exec ") {
            return .ran
        }

        // Grep/regex/JSON query strings must never become the visible label.
        if looksLikeSearchPattern(trimmed) { return .searched }

        if lower.hasPrefix("[subagent") || lower.hasPrefix("subagent:")
            || lower.hasPrefix("subagent ") || lower.hasPrefix("spawn_subagent") {
            return .subagent
        }
        if lower.hasPrefix("computer_") || lower.hasPrefix("computer ") || lower == "computer" {
            return .computerUse
        }

        let first = trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? trimmed
        let slug = first.lowercased()
        if slug == "read_file" || slug == "read" {
            return looksLikeSkill(trimmed) ? .readSkill : .readFile
        }
        if slug == "list_dir" || slug == "list" { return .listed }
        if slug == "write_file" || slug == "write" || slug == "edit" { return .edited }
        if slug == "grep" || slug == "rg" || slug == "glob" || slug == "web_search"
            || slug == "websearch" || slug == "search" || slug == "searched" {
            return .searched
        }
        if slug == "get" || slug == "web_fetch" || slug == "webfetch" { return .fetched }
        if slug == "bash" || slug == "shell" || slug == "sh" || slug == "zsh"
            || slug == "spawn" || slug == "run" {
            return .ran
        }
        if slug.hasPrefix("computer") { return .computerUse }
        if slug.hasPrefix("subagent") || slug.hasPrefix("[subagent") { return .subagent }

        let label = first
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`[]{}"))
            .replacingOccurrences(of: "_", with: " ")
        if label.isEmpty || looksLikeSearchPattern(label) || label.count > 32 {
            return .searched
        }
        return .other(label)
    }

    static func summarize(titles: [String]) -> String {
        var verbOrder: [String] = []
        var skills = 0
        var files = 0
        var listed = 0
        var edited = 0
        var searched = 0
        var fetched = 0
        var ran = 0
        var computerUse = 0
        var subagents = 0
        var others: [(label: String, count: Int)] = []

        func noteVerb(_ verb: String) {
            if !verbOrder.contains(verb) { verbOrder.append(verb) }
        }

        for title in titles {
            guard let kind = classify(title: title) else { continue }
            switch kind {
            case .readSkill:
                noteVerb("read")
                skills += 1
            case .readFile:
                noteVerb("read")
                files += 1
            case .listed:
                noteVerb("listed")
                listed += 1
            case .edited:
                noteVerb("edited")
                edited += 1
            case .searched:
                noteVerb("searched")
                searched += 1
            case .fetched:
                noteVerb("fetched")
                fetched += 1
            case .ran:
                noteVerb("ran")
                ran += 1
            case .computerUse:
                noteVerb("computer")
                computerUse += 1
            case .subagent:
                noteVerb("subagent")
                subagents += 1
            case .other(let label):
                noteVerb("other:\(label)")
                if let idx = others.firstIndex(where: { $0.label == label }) {
                    others[idx].count += 1
                } else {
                    others.append((label, 1))
                }
            }
        }

        var clauses: [String] = []
        for verb in verbOrder {
            switch verb {
            case "read":
                if skills > 0 { clauses.append("Read \(skills) \(skills == 1 ? "skill" : "skills")") }
                if files > 0 { clauses.append("Read \(files) \(files == 1 ? "file" : "files")") }
            case "listed":
                clauses.append("Listed \(listed) \(listed == 1 ? "dir" : "dirs")")
            case "edited":
                clauses.append("Edited \(edited) \(edited == 1 ? "file" : "files")")
            case "searched":
                clauses.append("Searched \(searched)")
            case "fetched":
                clauses.append("Fetched \(fetched)")
            case "ran":
                clauses.append("Ran \(ran) \(ran == 1 ? "command" : "commands")")
            case "computer":
                clauses.append(computerUse == 1 ? "Computer Use" : "Computer Use ×\(computerUse)")
            case "subagent":
                clauses.append(subagents == 1 ? "subagent" : "subagent ×\(subagents)")
            default:
                if verb.hasPrefix("other:"),
                   let item = others.first(where: { "other:\($0.label)" == verb }) {
                    clauses.append(item.count == 1 ? item.label : "\(item.label) ×\(item.count)")
                }
            }
        }
        return clauses.joined(separator: ", ")
    }

    static func line(titles: [String], hookCount: Int, eventName: String? = nil) -> String {
        let summary: String = {
            let fromTools = summarize(titles: titles)
            if !fromTools.isEmpty { return fromTools }
            if let eventName, !eventName.isEmpty { return eventName }
            return "Working"
        }()
        if hookCount > 0 {
            return "\(summary)  [hooks: \(hookCount)]"
        }
        return summary
    }

    static func isPlaceholder(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "unknown" || normalized == "tool call"
    }

    private static func looksLikeSkill(_ title: String) -> Bool {
        title.lowercased().contains("skill.md")
    }

    /// Re-fold a persisted working line so old raw titles pick up current classify rules.
    static func refreshSummary(_ summary: String) -> String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.lowercased() == "stop" || trimmed.lowercased().hasPrefix("stop ") {
            return trimmed
        }
        var titles: [String] = []
        for clause in trimmed.components(separatedBy: ", ") {
            let piece = clause.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { continue }
            titles.append(contentsOf: titlesForPersistedClause(piece))
        }
        let refreshed = summarize(titles: titles)
        return refreshed.isEmpty ? trimmed : refreshed
    }

    /// Grep patterns, quoted JSON keys, and regexes are searches — not tool names.
    private static func looksLikeSearchPattern(_ title: String) -> Bool {
        if title.contains(".*") { return true }
        if title.contains("\\") { return true }
        if title.contains("|") { return true }
        if title.contains("\"name\":") || title.contains("\":\"") { return true }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\"") { return true }
        if trimmed.contains("*") && trimmed.contains(".") { return true }
        return false
    }

    private static func titlesForPersistedClause(_ clause: String) -> [String] {
        let (base, suffixCount) = splitCountSuffix(clause)
        let cleaned = base.trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
            .trimmingCharacters(in: .whitespaces)
        if let (seed, n) = canonicalTitle(for: cleaned) {
            return Array(repeating: seed, count: max(1, n) * suffixCount)
        }
        return Array(repeating: cleaned, count: suffixCount)
    }

    private static func splitCountSuffix(_ clause: String) -> (String, Int) {
        let trimmed = clause.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.range(of: #"\s*[×x](\d+)\s*$"#, options: .regularExpression) else {
            return (trimmed, 1)
        }
        let digits = trimmed[match].filter(\.isNumber)
        let count = max(1, Int(digits) ?? 1)
        let base = String(trimmed[..<match.lowerBound]).trimmingCharacters(in: .whitespaces)
        return (base, count)
    }

    private static func canonicalTitle(for clause: String) -> (String, Int)? {
        let lower = clause.lowercased()
        if let count = trailingCount(lower, prefix: "read ", suffixCandidates: ["skill", "skills"]) {
            return ("Read SKILL.md", count)
        }
        if let count = trailingCount(lower, prefix: "read ", suffixCandidates: ["file", "files"]) {
            return ("Read file", count)
        }
        if let count = trailingCount(lower, prefix: "listed ", suffixCandidates: ["dir", "dirs"]) {
            return ("List dir", count)
        }
        if let count = trailingCount(lower, prefix: "edited ", suffixCandidates: ["file", "files"]) {
            return ("Edit file", count)
        }
        if let count = trailingCount(lower, prefix: "searched ", suffixCandidates: [""]) {
            return ("Search files", count)
        }
        if let count = trailingCount(lower, prefix: "fetched ", suffixCandidates: [""]) {
            return ("Get", count)
        }
        if let count = trailingCount(lower, prefix: "ran ", suffixCandidates: ["command", "commands"]) {
            return ("bash", count)
        }
        if lower == "computer use" { return ("computer", 1) }
        if lower == "subagent" { return ("subagent", 1) }
        return nil
    }

    private static func trailingCount(
        _ lower: String,
        prefix: String,
        suffixCandidates: [String]
    ) -> Int? {
        guard lower.hasPrefix(prefix) else { return nil }
        let rest = String(lower.dropFirst(prefix.count))
        let tokens = rest.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = tokens.first, let count = Int(first) else { return nil }
        if suffixCandidates == [""] {
            return tokens.count == 1 ? count : nil
        }
        guard tokens.count == 2, suffixCandidates.contains(tokens[1]) else { return nil }
        return count
    }
}

/// Incremental fold of ACP message / tool / hook events into transcript parts.
struct GrokActivityBuilder {
    private(set) var parts: [TranscriptPart] = []
    private var openIDs: [String] = []
    private var openTitles: [String: String] = [:]
    private var openHookRuns = 0
    private var pendingHookRuns = 0
    private var activityCount = 0

    var textContent: String {
        parts.compactMap(\.text).joined()
    }

    var hasActivity: Bool {
        parts.contains(where: \.isActivity) || !openTitles.isEmpty
    }

    mutating func addMessage(_ text: String) {
        guard let usable = AssistantTranscriptSanitizer.usableChunk(text),
              !usable.isEmpty else { return }
        flushOpenActivity()
        appendText(usable)
        sanitizeLastTextPart()
    }

    mutating func addTool(id: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !GrokActivitySummary.isPlaceholder(trimmed) else { return }
        if openTitles[id] == nil {
            openIDs.append(id)
        }
        openTitles[id] = trimmed
        if pendingHookRuns > 0 {
            openHookRuns += pendingHookRuns
            pendingHookRuns = 0
        }
        publishOpenActivity()
    }

    mutating func addHook(eventName: String, runCount: Int) {
        let count = max(0, runCount)
        switch eventName {
        case "stop":
            flushOpenActivity()
            appendActivity(summary: "stop", hookCount: count)
        case "session_start", "session_end":
            break
        case "post_tool_use":
            break
        case "user_prompt_submit":
            pendingHookRuns += count
        default:
            if !openTitles.isEmpty {
                openHookRuns += count
                publishOpenActivity()
            } else {
                pendingHookRuns += count
            }
        }
    }

    mutating func finish() {
        flushOpenActivity()
    }

    private mutating func appendText(_ text: String) {
        if case .text(let existing) = parts.last {
            parts[parts.count - 1] = .text(existing + text)
        } else {
            parts.append(.text(text))
        }
    }

    private mutating func sanitizeLastTextPart() {
        guard case .text(let existing) = parts.last else { return }
        let stripped = AssistantTranscriptSanitizer.strip(existing)
        if stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.removeLast()
        } else if stripped != existing {
            parts[parts.count - 1] = .text(stripped)
        }
    }

    private mutating func publishOpenActivity() {
        let titles = openIDs.compactMap { openTitles[$0] }
        guard !titles.isEmpty else { return }
        let summary = GrokActivitySummary.summarize(titles: titles)
        guard !summary.isEmpty else { return }
        upsertActivity(summary: summary, hookCount: openHookRuns)
    }

    private mutating func flushOpenActivity() {
        if !openTitles.isEmpty {
            publishOpenActivity()
        }
        openIDs = []
        openTitles = [:]
        openHookRuns = 0
    }

    private mutating func upsertActivity(summary: String, hookCount: Int) {
        if case .activity(let existing) = parts.last {
            parts[parts.count - 1] = .activity(
                GrokActivityLine(summary: summary, hookCount: hookCount, isLead: existing.isLead)
            )
            return
        }
        let line = GrokActivityLine(summary: summary, hookCount: hookCount, isLead: activityCount == 0)
        parts.append(.activity(line))
        activityCount += 1
    }

    private mutating func appendActivity(summary: String, hookCount: Int) {
        let isLead = activityCount == 0
        parts.append(.activity(GrokActivityLine(summary: summary, hookCount: hookCount, isLead: isLead)))
        activityCount += 1
    }
}

/// Rebuilds CLI activity parts from grok `updates.jsonl`.
enum GrokActivityLog {
    static func updatesURL(workspacePath: URL, grokSessionID: String) -> URL? {
        GrokSessionTranscriptImporter.chatHistoryURL(
            workspacePath: workspacePath,
            grokSessionID: grokSessionID
        )?.deletingLastPathComponent().appendingPathComponent("updates.jsonl")
    }

    /// One user turn's interleaved text + activity.
    struct Turn: Equatable {
        var userText: String
        var parts: [TranscriptPart]
    }

    static func turns(from url: URL) -> [Turn] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return turns(fromJSONL: text)
    }

    static func turns(fromJSONL text: String) -> [Turn] {
        var turns: [Turn] = []
        var currentUser = ""
        var builder = GrokActivityBuilder()
        var inAssistantTurn = false

        func flushTurn() {
            builder.finish()
            guard builder.hasActivity || !builder.textContent.isEmpty else {
                builder = GrokActivityBuilder()
                return
            }
            turns.append(Turn(userText: currentUser, parts: builder.parts))
            builder = GrokActivityBuilder()
            inAssistantTurn = false
        }

        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let update = unwrapUpdate(row) else { continue }

            let kind = update["sessionUpdate"] as? String ?? ""
            switch kind {
            case "user_message_chunk":
                if inAssistantTurn { flushTurn() }
                if let chunk = textContent(in: update) {
                    currentUser += chunk
                }
            case "agent_message_chunk":
                inAssistantTurn = true
                if let chunk = textContent(in: update) {
                    builder.addMessage(chunk)
                }
            case "tool_call", "tool_call_update":
                inAssistantTurn = true
                let id = (update["toolCallId"] as? String)
                    ?? (update["tool_call_id"] as? String)
                    ?? UUID().uuidString
                if let title = update["title"] as? String {
                    builder.addTool(id: id, title: title)
                }
            case "hook_execution":
                let event = (update["event_name"] as? String) ?? (update["eventName"] as? String) ?? ""
                let runs = (update["runs"] as? [[String: Any]])?.count ?? 0
                if event == "user_prompt_submit" {
                    if inAssistantTurn { flushTurn() }
                    currentUser = ""
                }
                builder.addHook(eventName: event, runCount: runs)
            case "turn_completed":
                flushTurn()
                currentUser = ""
            default:
                break
            }
        }
        if inAssistantTurn || builder.hasActivity {
            flushTurn()
        }
        return turns
    }

    /// Overlay activity parts onto an assistant message when it has none yet.
    static func align(_ parts: [TranscriptPart], toContent content: String) -> [TranscriptPart] {
        let content = AssistantTranscriptSanitizer.strip(content)
        let parts = parts.compactMap { part -> TranscriptPart? in
            switch part {
            case .text(let value):
                let cleaned = AssistantTranscriptSanitizer.strip(value)
                return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .text(cleaned)
            case .activity:
                return part
            }
        }
        let joined = parts.compactMap(\.text).joined()
        if joined == content { return parts }
        if content.hasPrefix(joined), let last = parts.lastIndex(where: { $0.text != nil }) {
            var updated = parts
            let extra = AssistantTranscriptSanitizer.strip(String(content.dropFirst(joined.count)))
            if !extra.isEmpty, case .text(let existing) = updated[last] {
                updated[last] = .text(existing + extra)
            }
            return updated
        }
        if joined.hasPrefix(content) { return parts }
        if let overlap = SessionTranscriptRecovery.longestImportedPrefixAsSuffix(of: content, imported: joined),
           overlap >= SessionTranscriptRecovery.minimumAssistantOverlap {
            let head = AssistantTranscriptSanitizer.strip(String(content.dropLast(overlap)))
            var updated = parts
            if head.isEmpty { return updated }
            if case .text(let first) = updated.first {
                updated[0] = .text(head + first)
            } else {
                updated.insert(.text(head), at: 0)
            }
            return updated
        }
        return parts
    }

    private static func unwrapUpdate(_ row: [String: Any]) -> [String: Any]? {
        if let update = row["sessionUpdate"] as? String, !update.isEmpty {
            return row
        }
        if let params = row["params"] as? [String: Any],
           let update = params["update"] as? [String: Any] {
            return update
        }
        if let update = row["update"] as? [String: Any] {
            return update
        }
        return nil
    }

    private static func textContent(in update: [String: Any]) -> String? {
        if let content = update["content"] as? [String: Any],
           let text = content["text"] as? String,
           !text.isEmpty {
            return text
        }
        if let text = update["text"] as? String, !text.isEmpty {
            return text
        }
        return nil
    }
}
