import Foundation

struct SlashCommand: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let description: String
    let inputHint: String?
    let isSkill: Bool

    init(name: String, description: String = "", inputHint: String? = nil, isSkill: Bool = false) {
        self.name = name
        self.description = description
        self.inputHint = inputHint
        self.isSkill = isSkill
    }

    static func parse(from dict: [String: Any]) -> SlashCommand? {
        guard let name = dict["name"] as? String else { return nil }
        let description = dict["description"] as? String ?? ""
        let hint = (dict["input"] as? [String: Any])?["hint"] as? String
        let path = (dict["_meta"] as? [String: Any])?["path"] as? String ?? ""
        let isSkill = path.hasSuffix("SKILL.md") || path.contains("/skills/")
        return SlashCommand(name: name, description: description, inputHint: hint, isSkill: isSkill)
    }
}

enum SlashMenuEntry: Identifiable, Hashable {
    case command(SlashCommand)
    case showMoreSkills(count: Int)
    case showMoreCommands(count: Int)

    var id: String {
        switch self {
        case .command(let command): return "cmd:\(command.id)"
        case .showMoreSkills: return "more:skills"
        case .showMoreCommands: return "more:commands"
        }
    }
}

enum SlashAutocompleteGroups {
    static let previewLimit = 3
    private static let skillPriority = ["code-review", "review", "check-work"]

    static func split(_ commands: [SlashCommand]) -> (skills: [SlashCommand], commands: [SlashCommand]) {
        var skills: [SlashCommand] = []
        var cmds: [SlashCommand] = []
        for command in commands {
            if command.isSkill {
                skills.append(command)
            } else {
                cmds.append(command)
            }
        }
        return (sortSkills(skills), cmds)
    }

    private static func sortSkills(_ skills: [SlashCommand]) -> [SlashCommand] {
        skills.sorted { lhs, rhs in
            let left = skillPriority.firstIndex(of: lhs.name) ?? Int.max
            let right = skillPriority.firstIndex(of: rhs.name) ?? Int.max
            if left != right { return left < right }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func visible(_ items: [SlashCommand], expanded: Bool, filtering: Bool = false) -> (visible: [SlashCommand], hiddenCount: Int) {
        guard !expanded, !filtering, items.count > previewLimit else {
            return (items, 0)
        }
        return (Array(items.prefix(previewLimit)), items.count - previewLimit)
    }

    static func navigableEntries(
        skills: [SlashCommand],
        commands: [SlashCommand],
        skillsExpanded: Bool,
        commandsExpanded: Bool,
        filtering: Bool = false
    ) -> [SlashMenuEntry] {
        var entries: [SlashMenuEntry] = []
        let skillSlice = visible(skills, expanded: skillsExpanded, filtering: filtering)
        entries += skillSlice.visible.map { .command($0) }
        if skillSlice.hiddenCount > 0 {
            entries.append(.showMoreSkills(count: skillSlice.hiddenCount))
        }

        let commandSlice = visible(commands, expanded: commandsExpanded, filtering: filtering)
        entries += commandSlice.visible.map { .command($0) }
        if commandSlice.hiddenCount > 0 {
            entries.append(.showMoreCommands(count: commandSlice.hiddenCount))
        }
        return entries
    }
}

struct FileAttachment: Identifiable, Hashable, Sendable {
    let id: UUID
    let path: String
    let relativePath: String
    var isHidden: Bool

    init(path: String, workspaceRoot: URL?, isHidden: Bool = false) {
        self.id = UUID()
        self.path = path
        self.isHidden = isHidden
        if let root = workspaceRoot {
            let rootPath = root.standardizedFileURL.path
            if path.hasPrefix(rootPath + "/") {
                relativePath = String(path.dropFirst(rootPath.count + 1))
            } else {
                relativePath = URL(fileURLWithPath: path).lastPathComponent
            }
        } else {
            relativePath = URL(fileURLWithPath: path).lastPathComponent
        }
    }

}

enum AttachmentPromptBuilder {
    /// Build attachment text for the user prompt. Uses plain paths — not `@` references,
    /// which tell grok to read the whole file (bad for large text and binaries).
    static func build(from attachments: [FileAttachment]) -> String? {
        let paths = attachments.filter { !$0.isHidden }.map(\.relativePath)
        guard !paths.isEmpty else { return nil }

        if paths.count == 1 {
            return "Attached file: \(paths[0])"
        }
        return "Attached files:\n" + paths.map { "- \($0)" }.joined(separator: "\n")
    }
}

struct ExitPlanRequest: Identifiable, Hashable, @unchecked Sendable {
    let id: AnyHashable
    let sessionId: String
    var planText: String
    var isResolved: Bool
    var verdict: PlanVerdict?

    enum PlanVerdict: String, Sendable {
        case approved, rejected, abandoned
    }
}

struct QuestionOption: Identifiable, Hashable, Sendable {
    let label: String
    let description: String?

    var id: String { label }
}

struct QuestionItem: Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let options: [QuestionOption]
    let multiSelect: Bool

    static func parse(from dict: [String: Any]) -> QuestionItem? {
        let text = (dict["question"] as? String) ?? (dict["prompt"] as? String) ?? ""
        guard !text.isEmpty else { return nil }
        let options = (dict["options"] as? [[String: Any]] ?? []).compactMap { opt -> QuestionOption? in
            guard let label = opt["label"] as? String else { return nil }
            return QuestionOption(label: label, description: opt["description"] as? String)
        }
        return QuestionItem(
            id: text,
            text: text,
            options: options,
            multiSelect: dict["multiSelect"] as? Bool ?? false
        )
    }
}

struct QuestionRequest: Identifiable, Hashable, @unchecked Sendable {
    let id: AnyHashable
    let sessionId: String
    let questions: [QuestionItem]
    var isResolved: Bool
    var answerSummary: String?

    static func isQuestionTool(_ toolCall: ToolCall) -> Bool {
        if questionsFromToolCall(toolCall) != nil { return true }
        let normalized = toolCall.title
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        return normalized == "askuserquestion" || normalized == "askquestion"
    }

    static func questionsFromToolCall(_ toolCall: ToolCall) -> [QuestionItem]? {
        if let raw = toolCall.rawInput?["questions"] as? [[String: Any]] {
            let parsed = raw.compactMap { QuestionItem.parse(from: $0) }
            if !parsed.isEmpty { return parsed }
        }
        let title = toolCall.title
        if title.range(of: #"^ask[:\s]"#, options: [.regularExpression, .caseInsensitive]) != nil {
            let text = title.replacingOccurrences(
                of: #"^ask[:\s]+"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return [QuestionItem(id: text, text: text, options: [], multiSelect: false)]
            }
        }
        return nil
    }
}

enum SessionNameStore {
    private static let key = "grokbuild.sessionNames.v1"

    static func name(for sessionId: String) -> String? {
        guard let map = UserDefaults.standard.dictionary(forKey: key) as? [String: String] else { return nil }
        return map[sessionId]
    }

    static func setName(_ name: String, for sessionId: String) {
        var map = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            map.removeValue(forKey: sessionId)
        } else {
            map[sessionId] = trimmed
        }
        UserDefaults.standard.set(map, forKey: key)
    }

    static func removeName(for sessionId: String) {
        setName("", for: sessionId)
    }
}

enum SessionTitle {
    static let defaultTitle = "New chat"
    static let maxWords = 8

    static func auto(from messages: [Message]) -> String? {
        guard let raw = messages.first(where: { $0.role == .user })?.content else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let collapsed = trimmed
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let parts = collapsed.split(separator: " ")
        guard !parts.isEmpty else { return nil }

        let preview = parts.prefix(maxWords).joined(separator: " ")
        return parts.count > maxWords ? preview + "…" : preview
    }
}
