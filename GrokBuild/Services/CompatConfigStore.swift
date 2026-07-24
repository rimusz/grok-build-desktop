import Foundation

enum CompatFlavor: String, CaseIterable, Sendable {
    case cursor
    case claude
    case codex

    var tomlKey: String { rawValue }
}

/// Reads and writes `[compat.cursor|claude|codex] enabled` in `~/.grok/config.toml`.
enum CompatConfigStore {
    static var configURL: URL {
        CustomModelStore.configURL
    }

    static func loadEnabled(_ flavor: CompatFlavor) -> Bool {
        isEnabled(flavor)
    }

    static func isEnabled(_ flavor: CompatFlavor, contents: String? = nil) -> Bool {
        let text: String
        if let contents {
            text = contents
        } else if let loaded = try? String(contentsOf: configURL, encoding: .utf8) {
            text = loaded
        } else {
            return false
        }
        return parseEnabled(flavor: flavor, from: text) ?? false
    }

    static func setEnabled(_ flavor: CompatFlavor, _ enabled: Bool) throws {
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let updated = rewrite(existing, flavor: flavor, enabled: enabled)
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try updated.write(to: configURL, atomically: true, encoding: .utf8)
    }

    static func rewrite(_ contents: String, flavor: CompatFlavor, enabled: Bool) -> String {
        let sectionName = "compat.\(flavor.tomlKey)"
        var output: [String] = []
        var inSection = false
        var foundEnabled = false
        var hasSection = false

        for rawLine in contents.components(separatedBy: .newlines) {
            let trimmed = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if inSection, !foundEnabled {
                    output.append("enabled = \(enabled)")
                }
                let header = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                inSection = header == sectionName
                if inSection { hasSection = true }
                foundEnabled = false
                output.append(rawLine)
                continue
            }

            if inSection {
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

        if inSection, !foundEnabled {
            output.append("enabled = \(enabled)")
        }

        while let last = output.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            output.removeLast()
        }

        var result = output.joined(separator: "\n")
        if !hasSection {
            if !result.isEmpty { result += "\n" }
            result += "\n[\(sectionName)]\nenabled = \(enabled)\n"
        } else if !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }

    private static func parseEnabled(flavor: CompatFlavor, from contents: String) -> Bool? {
        let sectionName = "compat.\(flavor.tomlKey)"
        var inSection = false
        for rawLine in contents.components(separatedBy: .newlines) {
            let trimmed = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let header = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                inSection = header == sectionName
                continue
            }
            guard inSection else { continue }
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

struct GrokExternalCompatInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isEnabled: Bool

    init(dictionary: [String: Any]) {
        name = dictionary["name"] as? String ?? dictionary["id"] as? String ?? "Unknown"
        id = name
        isEnabled = dictionary["enabled"] as? Bool
            ?? (dictionary["is_enabled"] as? Bool)
            ?? false
    }
}
