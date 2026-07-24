import Foundation

/// Reads and writes `[workflows] enabled` in `~/.grok/config.toml`.
enum WorkflowsConfigStore {
    static var configURL: URL {
        CustomModelStore.configURL
    }

    static func isEnabled(contents: String? = nil) -> Bool {
        let text: String
        if let contents {
            text = contents
        } else if let loaded = try? String(contentsOf: configURL, encoding: .utf8) {
            text = loaded
        } else {
            return true
        }
        return parseEnabled(from: text) ?? true
    }

    static func loadEnabled() -> Bool {
        isEnabled()
    }

    static func setEnabled(_ enabled: Bool) throws {
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let updated = rewrite(existing, enabled: enabled)
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try updated.write(to: configURL, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: .workflowsConfigChanged, object: nil)
    }

    static func rewrite(_ contents: String, enabled: Bool) -> String {
        var output: [String] = []
        var inWorkflowsSection = false
        var foundEnabled = false
        var hasWorkflowsSection = false

        for rawLine in contents.components(separatedBy: .newlines) {
            let trimmed = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if inWorkflowsSection, !foundEnabled {
                    output.append("enabled = \(enabled)")
                }
                let header = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                inWorkflowsSection = header == "workflows"
                if inWorkflowsSection { hasWorkflowsSection = true }
                foundEnabled = false
                output.append(rawLine)
                continue
            }

            if inWorkflowsSection {
                let key = trimmed.split(separator: "=", maxSplits: 1).first?
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                if key == "enabled" {
                    output.append("enabled = \(enabled)")
                    foundEnabled = true
                    continue
                }
            }

            output.append(rawLine)
        }

        if inWorkflowsSection, !foundEnabled {
            output.append("enabled = \(enabled)")
        }

        while let last = output.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            output.removeLast()
        }

        var result = output.joined(separator: "\n")
        if !hasWorkflowsSection {
            if !result.isEmpty { result += "\n" }
            result += "\n[workflows]\nenabled = \(enabled)\n"
        } else if !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }

    private static func parseEnabled(from contents: String) -> Bool? {
        var inWorkflowsSection = false
        for rawLine in contents.components(separatedBy: .newlines) {
            let trimmed = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let header = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                inWorkflowsSection = header == "workflows"
                continue
            }
            guard inWorkflowsSection else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "enabled" else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
            switch value {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }

    private static func stripComment(_ line: String) -> String {
        var quote: Character?
        var escaped = false
        var result = ""
        for char in line {
            if let q = quote {
                if q == "\"" {
                    if escaped { escaped = false }
                    else if char == "\\" { escaped = true }
                    else if char == "\"" { quote = nil }
                } else if char == q {
                    quote = nil
                }
                result.append(char)
                continue
            }
            if char == "#" { break }
            if char == "\"" || char == "'" { quote = char }
            result.append(char)
        }
        return result
    }
}
