import ApplicationServices
import Foundation

struct MCPTool {
    let name: String
    let description: String
    let inputSchema: [String: Any]

    var json: [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": inputSchema
        ]
    }
}

enum HelperError: LocalizedError {
    case invalidArguments(String)
    case policyDenied(String)
    case commandFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message): return message
        case .policyDenied(let message): return message
        case .commandFailed(let message): return message
        case .timeout: return "agent-desktop command timed out."
        }
    }
}

let agentDesktop = ProcessInfo.processInfo.environment["AGENT_DESKTOP_PATH"] ?? "agent-desktop"
let sessionName = ProcessInfo.processInfo.environment["GROKBUILD_COMPUTER_USE_SESSION"] ?? "grokbuild"
let permissionPolicy = ProcessInfo.processInfo.environment["GROKBUILD_COMPUTER_USE_POLICY"] ?? "ask"
let commandTimeout = TimeInterval(Int(ProcessInfo.processInfo.environment["GROKBUILD_COMPUTER_USE_TIMEOUT"] ?? "60") ?? 60)
let includeScreenshots = ProcessInfo.processInfo.environment["GROKBUILD_COMPUTER_USE_SCREENSHOTS"] == "true"

let tools: [MCPTool] = [
    MCPTool(
        name: "computer_snapshot",
        description: "Return an accessibility-tree snapshot with deterministic refs for desktop UI automation.",
        inputSchema: objectSchema(
            properties: [
                "app": stringSchema("Application name, for example Safari or Finder."),
                "window_id": stringSchema("Optional window id to snapshot."),
                "root": stringSchema("Optional ref to drill into, for example @e3."),
                "snapshot": stringSchema("Optional snapshot id to resolve root refs against."),
                "surface": stringSchema("Surface type: window, focused, menu, menubar, sheet, popover, or alert."),
                "interactive_only": boolSchema("Only include interactive elements."),
                "compact": boolSchema("Omit empty structural nodes."),
                "skeleton": boolSchema("Return a shallow skeleton for dense apps."),
                "include_bounds": boolSchema("Include element bounds."),
                "max_depth": intSchema("Maximum accessibility tree depth.")
            ]
        )
    ),
    MCPTool(
        name: "computer_screenshot",
        description: "Capture a desktop screenshot through agent-desktop. Requires screenshots enabled in GrokBuild settings.",
        inputSchema: objectSchema(
            properties: [
                "app": stringSchema("Optional application name."),
                "window_id": stringSchema("Optional window id."),
                "save_path": stringSchema("Optional file path where agent-desktop should save the image.")
            ]
        )
    ),
    MCPTool(
        name: "computer_click",
        description: "Click an accessibility ref from a recent computer_snapshot.",
        inputSchema: objectSchema(
            properties: [
                "ref": stringSchema("Element ref, for example @e3."),
                "snapshot": stringSchema("Optional snapshot id.")
            ],
            required: ["ref"]
        )
    ),
    MCPTool(
        name: "computer_type",
        description: "Type text into an accessibility ref from a recent computer_snapshot.",
        inputSchema: objectSchema(
            properties: [
                "ref": stringSchema("Element ref, for example @e5."),
                "text": stringSchema("Text to type."),
                "snapshot": stringSchema("Optional snapshot id.")
            ],
            required: ["ref", "text"]
        )
    ),
    MCPTool(
        name: "computer_press",
        description: "Press a keyboard key or shortcut, for example cmd+s, escape, or return.",
        inputSchema: objectSchema(
            properties: [
                "combo": stringSchema("Key or shortcut to press.")
            ],
            required: ["combo"]
        )
    ),
    MCPTool(
        name: "computer_get",
        description: "Read a property from an accessibility ref.",
        inputSchema: objectSchema(
            properties: [
                "ref": stringSchema("Element ref, for example @e3."),
                "property": stringSchema("Property to read, for example value."),
                "snapshot": stringSchema("Optional snapshot id.")
            ],
            required: ["ref", "property"]
        )
    ),
    MCPTool(
        name: "computer_wait",
        description: "Wait for time, element actionability, text, window, menu, or notification state.",
        inputSchema: objectSchema(
            properties: [
                "milliseconds": intSchema("Plain wait duration in milliseconds."),
                "element": stringSchema("Optional element ref to wait on."),
                "predicate": stringSchema("Optional predicate such as actionable or value."),
                "value": stringSchema("Optional expected predicate value."),
                "timeout": intSchema("Timeout in milliseconds."),
                "text": stringSchema("Optional text to wait for."),
                "app": stringSchema("Optional app name."),
                "window": stringSchema("Optional window title."),
                "menu": boolSchema("Wait for an open menu.")
            ]
        )
    ),
    MCPTool(
        name: "computer_list_apps",
        description: "List running GUI applications.",
        inputSchema: objectSchema()
    ),
    MCPTool(
        name: "computer_list_windows",
        description: "List visible windows, optionally for a specific app.",
        inputSchema: objectSchema(
            properties: [
                "app": stringSchema("Optional application name.")
            ]
        )
    ),
    MCPTool(
        name: "computer_permissions",
        description: "Report macOS permissions required by agent-desktop.",
        inputSchema: objectSchema()
    )
]

func objectSchema(properties: [String: Any] = [:], required: [String] = []) -> [String: Any] {
    var schema: [String: Any] = [
        "type": "object",
        "properties": properties
    ]
    if !required.isEmpty {
        schema["required"] = required
    }
    return schema
}

func stringSchema(_ description: String) -> [String: Any] {
    ["type": "string", "description": description]
}

func boolSchema(_ description: String) -> [String: Any] {
    ["type": "boolean", "description": description]
}

func intSchema(_ description: String) -> [String: Any] {
    ["type": "integer", "description": description]
}

func respond(id: Any?, result: Any? = nil, error: Error? = nil) {
    var message: [String: Any] = [
        "jsonrpc": "2.0",
        "id": id ?? NSNull()
    ]
    if let error {
        message["error"] = [
            "code": -32000,
            "message": error.localizedDescription
        ]
    } else {
        message["result"] = result ?? [:]
    }
    writeJSON(message)
}

func textResult(_ text: String) -> [String: Any] {
    ["content": [["type": "text", "text": text.isEmpty ? "(no output)" : text]]]
}

func writeJSON(_ value: Any) {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value),
          let line = String(data: data, encoding: .utf8) else {
        return
    }
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

func handle(_ request: [String: Any]) {
    let id = request["id"]
    let method = request["method"] as? String
    let params = request["params"] as? [String: Any] ?? [:]

    do {
        switch method {
        case "initialize":
            respond(id: id, result: [
                "protocolVersion": params["protocolVersion"] as? String ?? "2024-11-05",
                "serverInfo": ["name": "grokbuild-computer-use", "version": "0.1.0"],
                "capabilities": ["tools": [:]]
            ])
        case "notifications/initialized":
            return
        case "ping":
            respond(id: id, result: [:])
        case "tools/list":
            respond(id: id, result: ["tools": tools.map(\.json)])
        case "tools/call":
            let name = params["name"] as? String
            let args = params["arguments"] as? [String: Any] ?? [:]
            respond(id: id, result: try callTool(name: name, args: args))
        default:
            throw HelperError.invalidArguments("Unsupported MCP method: \(method ?? "(nil)")")
        }
    } catch {
        respond(id: id, error: error)
    }
}

func callTool(name: String?, args: [String: Any]) throws -> [String: Any] {
    switch name {
    case "computer_snapshot":
        return textResult(try runAgentDesktop(buildSnapshotArgs(args)))
    case "computer_screenshot":
        guard includeScreenshots else {
            throw HelperError.policyDenied("Screenshots are disabled in GrokBuild Computer Use settings.")
        }
        return textResult(try runAgentDesktop(buildScreenshotArgs(args)))
    case "computer_click":
        try enforceActionPolicy("click")
        return textResult(try runAgentDesktop(buildRefCommand("click", args: args)))
    case "computer_type":
        try enforceActionPolicy("type")
        let ref = try requiredString(args, "ref")
        let text = try requiredString(args, "text")
        var command = baseArgs() + ["type", ref, text]
        appendString(args, "snapshot", flag: "--snapshot", to: &command)
        return textResult(try runAgentDesktop(command))
    case "computer_press":
        try enforceActionPolicy("press")
        return textResult(try runAgentDesktop(baseArgs() + ["press", try requiredString(args, "combo")]))
    case "computer_get":
        let ref = try requiredString(args, "ref")
        let property = try requiredString(args, "property")
        var command = baseArgs() + ["get", ref, "--property", property]
        appendString(args, "snapshot", flag: "--snapshot", to: &command)
        return textResult(try runAgentDesktop(command))
    case "computer_wait":
        return textResult(try runAgentDesktop(buildWaitArgs(args)))
    case "computer_list_apps":
        return textResult(try runAgentDesktop(baseArgs() + ["list-apps"]))
    case "computer_list_windows":
        var command = baseArgs() + ["list-windows"]
        appendString(args, "app", flag: "--app", to: &command)
        return textResult(try runAgentDesktop(command))
    case "computer_permissions":
        return textResult(try runAgentDesktop(["permissions"]))
    default:
        throw HelperError.invalidArguments("Unknown Computer Use tool: \(name ?? "(nil)")")
    }
}

func enforceActionPolicy(_ action: String) throws {
    if permissionPolicy == "deny" {
        throw HelperError.policyDenied("Computer Use action '\(action)' is blocked by GrokBuild's local policy.")
    }
}

func baseArgs() -> [String] {
    // agent-desktop no longer accepts a global --session flag; snapshot ids are passed per command.
    []
}

func buildSnapshotArgs(_ args: [String: Any]) throws -> [String] {
    var command = baseArgs() + ["snapshot"]
    appendString(args, "app", flag: "--app", to: &command)
    appendString(args, "window_id", flag: "--window-id", to: &command)
    appendString(args, "root", flag: "--root", to: &command)
    appendString(args, "snapshot", flag: "--snapshot", to: &command)
    appendString(args, "surface", flag: "--surface", to: &command)
    appendBool(args, "interactive_only", flag: "-i", to: &command)
    appendBool(args, "compact", flag: "--compact", defaultValue: true, to: &command)
    appendBool(args, "skeleton", flag: "--skeleton", to: &command)
    appendBool(args, "include_bounds", flag: "--include-bounds", to: &command)
    appendInt(args, "max_depth", flag: "--max-depth", to: &command)
    return command
}

func buildScreenshotArgs(_ args: [String: Any]) throws -> [String] {
    var command = baseArgs() + ["screenshot"]
    appendString(args, "app", flag: "--app", to: &command)
    appendString(args, "window_id", flag: "--window-id", to: &command)
    if let savePath = args["save_path"] as? String,
       !savePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        command.append(savePath)
    }
    return command
}

func buildRefCommand(_ commandName: String, args: [String: Any]) throws -> [String] {
    var command = baseArgs() + [commandName, try requiredString(args, "ref")]
    appendString(args, "snapshot", flag: "--snapshot", to: &command)
    return command
}

func buildWaitArgs(_ args: [String: Any]) throws -> [String] {
    if let milliseconds = args["milliseconds"] as? Int {
        return baseArgs() + ["wait", String(milliseconds)]
    }
    var command = baseArgs() + ["wait"]
    appendString(args, "element", flag: "--element", to: &command)
    appendString(args, "predicate", flag: "--predicate", to: &command)
    appendString(args, "value", flag: "--value", to: &command)
    appendInt(args, "timeout", flag: "--timeout", to: &command)
    appendString(args, "text", flag: "--text", to: &command)
    appendString(args, "app", flag: "--app", to: &command)
    appendString(args, "window", flag: "--window", to: &command)
    appendBool(args, "menu", flag: "--menu", to: &command)
    return command
}

func requiredString(_ args: [String: Any], _ key: String) throws -> String {
    guard let value = args[key] as? String,
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw HelperError.invalidArguments("Missing required argument: \(key)")
    }
    return value
}

func appendString(_ args: [String: Any], _ key: String, flag: String, to command: inout [String]) {
    guard let value = args[key] as? String,
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    command += [flag, value]
}

func appendInt(_ args: [String: Any], _ key: String, flag: String, to command: inout [String]) {
    guard let value = args[key] as? Int else { return }
    command += [flag, String(value)]
}

func appendBool(_ args: [String: Any], _ key: String, flag: String, defaultValue: Bool = false, to command: inout [String]) {
    let value = args[key] as? Bool ?? defaultValue
    if value {
        command.append(flag)
    }
}

func runAgentDesktop(_ args: [String]) throws -> String {
    let process = Process()
    if agentDesktop.contains("/") {
        process.executableURL = URL(fileURLWithPath: agentDesktop)
        process.arguments = args
    } else {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [agentDesktop] + args
    }

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        throw HelperError.commandFailed("Failed to launch agent-desktop: \(error.localizedDescription)")
    }

    let deadline = Date().addingTimeInterval(commandTimeout)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning {
        process.terminate()
        throw HelperError.timeout
    }

    let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let error = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let text = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? error : output

    if process.terminationStatus != 0 {
        throw HelperError.commandFailed(mappedError(from: text, fallback: process.terminationStatus))
    }
    if let mapped = mappedStructuredFailure(from: text) {
        throw HelperError.commandFailed(mapped)
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func mappedStructuredFailure(from text: String) -> String? {
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let ok = json["ok"] as? Bool,
          ok == false else {
        return nil
    }
    return mappedError(from: text, fallback: 1)
}

func mappedError(from text: String, fallback: Int32) -> String {
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let error = json["error"] as? [String: Any] else {
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "agent-desktop exited with \(fallback)"
            : text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let code = error["code"] as? String ?? "AGENT_DESKTOP_ERROR"
    let message = error["message"] as? String ?? "agent-desktop command failed."
    let suggestion = error["suggestion"] as? String
    return [code, message, suggestion].compactMap { $0 }.joined(separator: ": ")
}

func printPermissionsProbe() {
    var agentDesktopOutput = ""
    var agentDesktopGranted = false
    do {
        agentDesktopOutput = try runAgentDesktop(["permissions"])
        if let data = agentDesktopOutput.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let payload = (json["data"] as? [String: Any]) ?? json
            if let granted = payload["granted"] as? Bool {
                agentDesktopGranted = granted
            } else if let accessibility = payload["accessibility"] as? [String: Any],
                      let state = accessibility["state"] as? String {
                agentDesktopGranted = state.lowercased() == "granted"
            }
        }
    } catch {
        agentDesktopOutput = error.localizedDescription
    }

    let payload: [String: Any] = [
        "ok": true,
        "helper_accessibility_granted": AXIsProcessTrusted(),
        "helper_executable": ProcessInfo.processInfo.arguments[0],
        "agent_desktop_granted": agentDesktopGranted,
        "agent_desktop_output": agentDesktopOutput
    ]

    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
          let text = String(data: data, encoding: .utf8) else {
        fputs("{\"ok\":false,\"error\":\"Failed to encode permissions probe.\"}\n", stderr)
        exit(1)
    }
    print(text)
}

func requestPermissionsProbe() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [key: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)

    var agentDesktopOutput = ""
    do {
        agentDesktopOutput = try runAgentDesktop(["permissions", "--request"])
    } catch {
        agentDesktopOutput = error.localizedDescription
    }

    let payload: [String: Any] = [
        "ok": true,
        "helper_accessibility_granted": AXIsProcessTrusted(),
        "helper_executable": ProcessInfo.processInfo.arguments[0],
        "agent_desktop_output": agentDesktopOutput
    ]

    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
          let text = String(data: data, encoding: .utf8) else {
        fputs("{\"ok\":false,\"error\":\"Failed to encode permissions request.\"}\n", stderr)
        exit(1)
    }
    print(text)
}

func main() {
    if CommandLine.arguments.contains("--check-permissions") {
        printPermissionsProbe()
        return
    }
    if CommandLine.arguments.contains("--request-permissions") {
        requestPermissionsProbe()
        return
    }

    while let line = readLine() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        do {
            guard let data = trimmed.data(using: .utf8),
                  let request = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HelperError.invalidArguments("Invalid JSON-RPC request.")
            }
            handle(request)
        } catch {
            respond(id: nil, error: error)
        }
    }
}

main()
