import Foundation

/// A background activity mirrored from grok ACP tool calls (scheduled tasks, background shells, monitors, subagents).
struct BackgroundActivity: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case scheduled
        case backgroundCommand
        case monitor
        case subagent
    }

    let id: String
    let kind: Kind
    var title: String
    var detail: String
    var status: String
    /// Populated for `.scheduled` kinds.
    var scheduledTask: ScheduledTask?

    init(
        id: String,
        kind: Kind,
        title: String,
        detail: String = "",
        status: String = "",
        scheduledTask: ScheduledTask? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.status = status
        self.scheduledTask = scheduledTask
    }
}

/// Detects background-task-related tool activity from ACP `session/update` payloads.
enum BackgroundToolParsing {
    static let backgroundToolNames: Set<String> = [
        "run_terminal_command",
        "monitor",
        "kill_command_or_subagent",
        "get_command_or_subagent_output",
        "spawn_subagent",
        "spawn-subagent",
    ]

    static func backgroundToolName(inUpdate update: [String: Any]) -> String? {
        if let meta = update["_meta"] as? [String: Any],
           let tool = meta["x.ai/tool"] as? [String: Any],
           let name = tool["name"] as? String {
            let normalized = name.lowercased().replacingOccurrences(of: "-", with: "_")
            if backgroundToolNames.contains(normalized) || normalized.hasPrefix("spawn_subagent") {
                return normalized
            }
            if normalized.hasPrefix("scheduler_") {
                return normalized
            }
        }
        if let out = rawOutput(inUpdate: update),
           let type = out["type"] as? String {
            let normalized = type.lowercased().replacingOccurrences(of: "-", with: "_")
            if normalized.hasPrefix("scheduler") { return normalized }
        }
        return nil
    }

    static func toolCallId(inUpdate update: [String: Any]) -> String? {
        update["toolCallId"] as? String ?? update["tool_call_id"] as? String
    }

    static func rawInput(inUpdate update: [String: Any]) -> [String: Any]? {
        update["rawInput"] as? [String: Any]
            ?? update["raw_input"] as? [String: Any]
            ?? update["rawinput"] as? [String: Any]
    }

    static func rawOutput(inUpdate update: [String: Any]) -> [String: Any]? {
        update["rawOutput"] as? [String: Any]
            ?? update["raw_output"] as? [String: Any]
            ?? update["rawoutput"] as? [String: Any]
    }

    static func isBackgroundTerminalCommand(_ input: [String: Any]) -> Bool {
        if let background = input["background"] as? Bool { return background }
        if let background = input["is_background"] as? Bool { return background }
        if let background = input["run_in_background"] as? Bool { return background }
        return false
    }

    static func activityKind(for toolName: String, input: [String: Any]) -> BackgroundActivity.Kind? {
        let name = toolName.lowercased().replacingOccurrences(of: "-", with: "_")
        if name.hasPrefix("scheduler") { return .scheduled }
        if name == "run_terminal_command" {
            return isBackgroundTerminalCommand(input) ? .backgroundCommand : nil
        }
        if name == "monitor" { return .monitor }
        if name.contains("subagent") { return .subagent }
        return nil
    }

    static func title(for kind: BackgroundActivity.Kind, input: [String: Any], output: [String: Any]?) -> String {
        switch kind {
        case .scheduled:
            return input["prompt"] as? String ?? output?["id"] as? String ?? "Scheduled task"
        case .backgroundCommand:
            return input["command"] as? String ?? input["cmd"] as? String ?? "Background command"
        case .monitor:
            return input["name"] as? String ?? input["target"] as? String ?? "Monitor"
        case .subagent:
            return input["name"] as? String
                ?? input["role"] as? String
                ?? input["prompt"] as? String
                ?? "Subagent"
        }
    }
}

/// Accumulates observed background activity from ACP tool updates.
struct BackgroundTaskTracker {
    private(set) var activities: [BackgroundActivity] = []
    private var scheduledTracker = ScheduledTaskTracker()
    private var pendingInputs: [String: [String: Any]] = [:]

    mutating func apply(update: [String: Any]) {
        scheduledTracker.apply(update: update)

        guard let toolName = BackgroundToolParsing.backgroundToolName(inUpdate: update) else { return }
        let callId = BackgroundToolParsing.toolCallId(inUpdate: update)
        if let callId, let input = BackgroundToolParsing.rawInput(inUpdate: update), !input.isEmpty {
            pendingInputs[callId] = input
        }

        let input = callId.flatMap { pendingInputs[$0] } ?? BackgroundToolParsing.rawInput(inUpdate: update) ?? [:]
        let output = BackgroundToolParsing.rawOutput(inUpdate: update)

        if toolName.hasPrefix("scheduler") {
            syncScheduledActivities()
            if let callId { pendingInputs[callId] = nil }
            return
        }

        guard let kind = BackgroundToolParsing.activityKind(for: toolName, input: input) else {
            if let callId { pendingInputs[callId] = nil }
            return
        }

        let id = output?["id"] as? String
            ?? output?["command_id"] as? String
            ?? output?["subagent_id"] as? String
            ?? callId
            ?? UUID().uuidString
        let title = BackgroundToolParsing.title(for: kind, input: input, output: output)
        let status = output?["status"] as? String ?? (output == nil ? "running" : "done")
        let detail = output?["output"] as? String ?? input["description"] as? String ?? ""

        upsert(BackgroundActivity(
            id: id,
            kind: kind,
            title: title,
            detail: detail,
            status: status
        ))

        if let callId { pendingInputs[callId] = nil }
    }

    mutating func reset() {
        activities = []
        scheduledTracker = ScheduledTaskTracker()
        pendingInputs = [:]
    }

    private mutating func syncScheduledActivities() {
        let scheduledIDs = Set(scheduledTracker.tasks.map(\.id))
        activities.removeAll { $0.kind == .scheduled && !scheduledIDs.contains($0.id) }
        for task in scheduledTracker.tasks {
            let title = task.prompt.isEmpty ? task.intervalHuman : task.prompt
            upsert(BackgroundActivity(
                id: task.id,
                kind: .scheduled,
                title: title,
                detail: task.intervalHuman,
                status: task.recurring ? "recurring" : "once",
                scheduledTask: task
            ))
        }
    }

    private mutating func upsert(_ activity: BackgroundActivity) {
        if let idx = activities.firstIndex(where: { $0.id == activity.id }) {
            var merged = activity
            if merged.title.isEmpty { merged.title = activities[idx].title }
            if merged.detail.isEmpty { merged.detail = activities[idx].detail }
            activities[idx] = merged
        } else {
            activities.append(activity)
        }
    }
}
