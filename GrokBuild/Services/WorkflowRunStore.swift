import Foundation

/// A grok workflow run mirrored from observed `workflow` tool activity in a live session.
struct WorkflowRun: Identifiable, Equatable, Codable {
    let id: String
    var name: String
    var phase: String
    var status: String
    var progress: String
    var agentBudgetSpent: Int?
    var agentBudgetTotal: Int?
}

/// Detects and parses grok `workflow` tool activity from ACP `session/update` payloads.
enum WorkflowToolParsing {
    static func workflowName(inUpdate update: [String: Any]) -> String? {
        if let meta = update["_meta"] as? [String: Any],
           let tool = meta["x.ai/tool"] as? [String: Any],
           let name = tool["name"] as? String {
            if name == "workflow" || name.hasPrefix("workflow") {
                return name
            }
        }
        if let out = rawOutput(inUpdate: update),
           let type = out["type"] as? String,
           type.lowercased().hasPrefix("workflow") {
            return type
        }
        return nil
    }

    static func isWorkflowSessionUpdate(_ sessionUpdateKey: String) -> Bool {
        let normalized = sessionUpdateKey
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
        switch normalized {
        case "workflowupdated", "goalupdated":
            return true
        default:
            return false
        }
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

    static func run(from dict: [String: Any]) -> WorkflowRun? {
        guard let id = firstString(dict, "displayName", "display_name", "handle", "name", "id") else {
            return nil
        }
        let name = firstString(
            dict,
            "workflowName", "workflow_name", "metaName", "meta_name", "title"
        ) ?? id
        let phase = firstString(dict, "phase", "currentPhase", "current_phase") ?? ""
        let status = firstString(dict, "status", "state") ?? "running"
        let progress = firstString(dict, "progress", "summary", "message") ?? ""
        let spent = firstInt(dict, "agentBudgetSpent", "agent_budget_spent", "budgetSpent", "budget_spent")
        let total = firstInt(dict, "agentBudgetTotal", "agent_budget_total", "budgetTotal", "budget_total")
        return WorkflowRun(
            id: id,
            name: name,
            phase: phase,
            status: status,
            progress: progress,
            agentBudgetSpent: spent,
            agentBudgetTotal: total
        )
    }

    private static func firstString(_ dict: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private static func firstInt(_ dict: [String: Any], _ keys: String...) -> Int? {
        for key in keys {
            if let value = dict[key] as? Int { return value }
            if let value = dict[key] as? Double { return Int(value) }
            if let value = dict[key] as? String, let parsed = Int(value) { return parsed }
        }
        return nil
    }
}

/// Accumulates observed grok workflow activity into a run list.
struct WorkflowRunTracker {
    private(set) var runs: [WorkflowRun] = []
    private var pendingInputs: [String: [String: Any]] = [:]

    mutating func apply(update: [String: Any]) {
        if let key = update["sessionUpdate"] as? String,
           WorkflowToolParsing.isWorkflowSessionUpdate(key) {
            if let run = sessionRun(from: update) {
                upsert(run)
            }
            return
        }

        let callId = WorkflowToolParsing.toolCallId(inUpdate: update)
        if let callId, let input = WorkflowToolParsing.rawInput(inUpdate: update), !input.isEmpty {
            pendingInputs[callId] = input
        }

        guard let out = WorkflowToolParsing.rawOutput(inUpdate: update),
              let type = out["type"] as? String else { return }

        let input = callId.flatMap { pendingInputs[$0] } ?? [:]
        switch type.lowercased().replacingOccurrences(of: "_", with: "") {
        case "workflowlist":
            replaceRuns(from: out)
        case "workflow", "workflowcreate", "workflowlaunch", "workflowstart":
            if let run = mergedRun(output: out, input: input) {
                upsert(run)
            }
        case "workflowpause":
            updateStatus(handleFrom: out, input: input, status: "paused")
        case "workflowresume":
            updateStatus(handleFrom: out, input: input, status: "running")
        case "workflowstop", "workflowcancel":
            updateStatus(handleFrom: out, input: input, status: "stopped")
        case "workflowcomplete", "workflowfinished":
            updateStatus(handleFrom: out, input: input, status: "completed")
        default:
            if type.lowercased().hasPrefix("workflow"),
               let run = mergedRun(output: out, input: input) {
                upsert(run)
            }
        }

        if let callId { pendingInputs[callId] = nil }
    }

    mutating func reset() {
        runs = []
        pendingInputs = [:]
    }

    private mutating func replaceRuns(from out: [String: Any]) {
        let list = (out["runs"] as? [[String: Any]])
            ?? (out["workflows"] as? [[String: Any]])
            ?? (out["items"] as? [[String: Any]])
            ?? []
        runs = list.compactMap(WorkflowToolParsing.run(from:))
    }

    private func sessionRun(from update: [String: Any]) -> WorkflowRun? {
        if let run = WorkflowToolParsing.run(from: update) { return run }
        if let nested = update["workflow"] as? [String: Any],
           let run = WorkflowToolParsing.run(from: nested) {
            return run
        }
        if let nested = update["run"] as? [String: Any],
           let run = WorkflowToolParsing.run(from: nested) {
            return run
        }
        return nil
    }

    private func mergedRun(output: [String: Any], input: [String: Any]) -> WorkflowRun? {
        guard var run = WorkflowToolParsing.run(from: output)
            ?? WorkflowToolParsing.run(from: input) else {
            return nil
        }
        if let fromInput = WorkflowToolParsing.run(from: input) {
            if run.name == run.id, fromInput.name != fromInput.id { run.name = fromInput.name }
            if run.phase.isEmpty { run.phase = fromInput.phase }
            if run.progress.isEmpty { run.progress = fromInput.progress }
            if run.agentBudgetSpent == nil { run.agentBudgetSpent = fromInput.agentBudgetSpent }
            if run.agentBudgetTotal == nil { run.agentBudgetTotal = fromInput.agentBudgetTotal }
        }
        return run
    }

    private mutating func updateStatus(handleFrom output: [String: Any], input: [String: Any], status: String) {
        guard let id = runHandle(from: output, input: input) else { return }
        guard let idx = runs.firstIndex(where: { $0.id == id }) else {
            if let run = mergedRun(output: output, input: input) {
                var created = run
                created.status = status
                upsert(created)
            }
            return
        }
        runs[idx].status = status
        if let run = WorkflowToolParsing.run(from: output) {
            if !run.phase.isEmpty { runs[idx].phase = run.phase }
            if !run.progress.isEmpty { runs[idx].progress = run.progress }
            if let spent = run.agentBudgetSpent { runs[idx].agentBudgetSpent = spent }
            if let total = run.agentBudgetTotal { runs[idx].agentBudgetTotal = total }
        }
    }

    private func runHandle(from output: [String: Any], input: [String: Any]) -> String? {
        WorkflowToolParsing.run(from: output)?.id
            ?? WorkflowToolParsing.run(from: input)?.id
            ?? (output["handle"] as? String)
            ?? (output["id"] as? String)
            ?? (input["handle"] as? String)
            ?? (input["id"] as? String)
            ?? (input["name"] as? String)
    }

    private mutating func upsert(_ run: WorkflowRun) {
        guard let idx = runs.firstIndex(where: { $0.id == run.id }) else {
            runs.append(run)
            return
        }
        var merged = run
        if merged.name.isEmpty || merged.name == merged.id { merged.name = runs[idx].name }
        if merged.phase.isEmpty { merged.phase = runs[idx].phase }
        if merged.progress.isEmpty { merged.progress = runs[idx].progress }
        if merged.agentBudgetSpent == nil { merged.agentBudgetSpent = runs[idx].agentBudgetSpent }
        if merged.agentBudgetTotal == nil { merged.agentBudgetTotal = runs[idx].agentBudgetTotal }
        runs[idx] = merged
    }
}
