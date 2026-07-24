import AppKit
import Foundation

enum SavedWorkflowScope: Equatable {
    case project
    case user
}

struct SavedWorkflow: Identifiable, Equatable {
    var id: String { "\(scopeLabel)-\(name)-\(url.path)" }
    let name: String
    let description: String
    let scope: SavedWorkflowScope
    let url: URL

    private var scopeLabel: String {
        switch scope {
        case .project: return "project"
        case .user: return "user"
        }
    }
}

enum SavedWorkflowStore {
    static func load(projectRoot: URL?, fileManager: FileManager = .default) -> [SavedWorkflow] {
        var workflows: [SavedWorkflow] = []
        if let projectRoot {
            let projectDir = projectRoot
                .appendingPathComponent(".grok/workflows", isDirectory: true)
            workflows += loadRhaiFiles(in: projectDir, scope: .project, fileManager: fileManager)
        }
        let userDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".grok/workflows", isDirectory: true)
        workflows += loadRhaiFiles(in: userDir, scope: .user, fileManager: fileManager)
        return workflows.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func parseMeta(from contents: String) -> (name: String?, description: String?) {
        let scan = contents.components(separatedBy: .newlines).prefix(40).joined(separator: "\n")
        let name = firstMatch(
            in: scan,
            patterns: [
                #"name\s*[:=]\s*"([^"]+)""#,
                #"name\s*[:=]\s*'([^']+)'"#,
            ]
        )
        let description = firstMatch(
            in: scan,
            patterns: [
                #"description\s*[:=]\s*"([^"]+)""#,
                #"description\s*[:=]\s*'([^']+)'"#,
            ]
        )
        return (name, description)
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func loadRhaiFiles(
        in directory: URL,
        scope: SavedWorkflowScope,
        fileManager: FileManager
    ) -> [SavedWorkflow] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "rhai" }
            .compactMap { url in
                let fallbackName = url.deletingPathExtension().lastPathComponent
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                    return SavedWorkflow(
                        name: fallbackName,
                        description: "",
                        scope: scope,
                        url: url
                    )
                }
                let meta = parseMeta(from: contents)
                return SavedWorkflow(
                    name: meta.name ?? fallbackName,
                    description: meta.description ?? "",
                    scope: scope,
                    url: url
                )
            }
    }

    private static func firstMatch(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let value = String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }
}
