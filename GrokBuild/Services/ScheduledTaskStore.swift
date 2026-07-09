import Foundation

/// A recurring/one-shot task grok has scheduled via its built-in `scheduler_*` tools.
///
/// GrokBuild mirrors these into the app by **observing** ACP `session/update` tool-call activity
/// (grok owns the source of truth). The mirror reflects scheduler activity the app has seen in a
/// live session plus authoritative snapshots from `scheduler_list` — it is not a live query, so
/// tasks created in the grok TUI or other sessions only appear after a refresh.
struct ScheduledTask: Identifiable, Equatable, Codable {
    let id: String
    var prompt: String
    var intervalHuman: String
    var nextFireAt: Date?
    var recurring: Bool
}

/// Detects and parses grok `scheduler_*` tool activity from ACP `session/update` payloads.
///
/// Pure and side-effect-free so it can be unit-tested without a live grok process. grok's wire
/// casing has varied across versions, so every lookup tolerates camelCase / lowercase / snake_case.
enum SchedulerToolParsing {
    /// Returns the scheduler tool (or result variant) name when `update` is scheduler-related.
    static func schedulerName(inUpdate update: [String: Any]) -> String? {
        if let meta = update["_meta"] as? [String: Any],
           let tool = meta["x.ai/tool"] as? [String: Any],
           let name = tool["name"] as? String, name.hasPrefix("scheduler_") {
            return name
        }
        if let out = rawOutput(inUpdate: update),
           let type = out["type"] as? String, type.lowercased().hasPrefix("scheduler") {
            return type
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

    /// Parses one task entry from a `scheduler_list` result.
    static func task(from dict: [String: Any]) -> ScheduledTask? {
        guard let id = dict["id"] as? String else { return nil }
        let prompt = dict["prompt"] as? String ?? ""
        let interval = firstString(dict, "intervalHuman", "intervalhuman", "interval_human", "humanSchedule", "humanschedule", "interval") ?? ""
        let recurring = dict["recurring"] as? Bool ?? false
        let next = firstString(dict, "nextFireAt", "nextfireat", "next_fire_at").flatMap(parseDate)
        return ScheduledTask(id: id, prompt: prompt, intervalHuman: interval, nextFireAt: next, recurring: recurring)
    }

    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt
    }()

    static func parseDate(_ value: String) -> Date? {
        if let date = isoFormatterFractional.date(from: value) { return date }
        return isoFormatter.date(from: value)
    }

    private static func firstString(_ dict: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }
}

/// Accumulates observed grok scheduler activity into a task list.
///
/// Feed it each scheduler-related `session/update` payload via ``apply(update:)``. It correlates the
/// initiating `tool_call` (which carries `rawInput` such as interval/prompt) with the completing
/// `tool_call_update` (which carries `rawOutput` such as the assigned id), so a freshly created task
/// appears with its prompt even before the next `scheduler_list` refresh.
struct ScheduledTaskTracker {
    private(set) var tasks: [ScheduledTask] = []
    /// `rawInput` captured at `tool_call`, keyed by toolCallId, merged in at completion.
    private var pendingInputs: [String: [String: Any]] = [:]

    mutating func apply(update: [String: Any]) {
        let callId = SchedulerToolParsing.toolCallId(inUpdate: update)
        if let callId, let input = SchedulerToolParsing.rawInput(inUpdate: update), !input.isEmpty {
            pendingInputs[callId] = input
        }

        // Only completed updates carry a rawOutput; that is where the authoritative data lives.
        guard let out = SchedulerToolParsing.rawOutput(inUpdate: update),
              let type = out["type"] as? String else { return }

        let input = callId.flatMap { pendingInputs[$0] } ?? [:]
        // grok emits CamelCase variants (`SchedulerList`) on rawOutput.type; normalize.
        switch type.lowercased() {
        case "schedulerlist", "scheduler_list":
            if let list = out["tasks"] as? [[String: Any]] {
                tasks = list.compactMap(SchedulerToolParsing.task(from:))
            }
        case "schedulercreate", "scheduler_create":
            if let id = out["id"] as? String {
                let interval = (out["humanSchedule"] as? String)
                    ?? (out["humanschedule"] as? String)
                    ?? (out["human_schedule"] as? String)
                    ?? (input["interval"] as? String)
                    ?? ""
                let prompt = input["prompt"] as? String ?? ""
                let recurring = (out["recurring"] as? Bool) ?? (input["recurring"] as? Bool) ?? false
                upsert(ScheduledTask(id: id, prompt: prompt, intervalHuman: interval, nextFireAt: nil, recurring: recurring))
            }
        case "schedulerdelete", "scheduler_delete":
            let id = (out["id"] as? String)
                ?? (input["id"] as? String)
                ?? (input["task_id"] as? String)
            if let id { tasks.removeAll { $0.id == id } }
        default:
            break
        }

        if let callId { pendingInputs[callId] = nil }
    }

    private mutating func upsert(_ task: ScheduledTask) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else {
            tasks.append(task)
            return
        }
        var merged = task
        if merged.prompt.isEmpty { merged.prompt = tasks[idx].prompt }
        if merged.intervalHuman.isEmpty { merged.intervalHuman = tasks[idx].intervalHuman }
        tasks[idx] = merged
    }
}
