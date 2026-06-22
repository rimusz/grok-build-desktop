import Foundation

struct GitBranchInfo: Identifiable, Hashable, Sendable {
    let name: String
    let isCurrent: Bool

    var id: String { name }
}

struct GitWorktreeInfo: Identifiable, Hashable, Sendable {
    let path: URL
    let branch: String?
    let isDetached: Bool

    var id: String { path.path }

    var branchLabel: String {
        if let branch { return branch }
        return isDetached ? "detached" : "unknown"
    }
}

enum GitService {
    enum GitError: LocalizedError {
        case notARepository
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .notARepository: return "This folder is not a git repository."
            case .commandFailed(let message): return message
            }
        }
    }

    @discardableResult
    static func run(_ args: [String], in directory: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = directory

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { process in
                let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: out)
                } else {
                    continuation.resume(throwing: GitError.commandFailed(err.isEmpty ? out : err))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func isRepository(_ directory: URL) -> Bool {
        gitDirectory(for: directory) != nil
    }

    static func currentBranch(in directory: URL) -> String? {
        guard let gitDir = gitDirectory(for: directory) else { return nil }
        let headURL = gitDir.appendingPathComponent("HEAD")
        guard let head = try? String(contentsOf: headURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !head.isEmpty else {
            return nil
        }
        if head.hasPrefix("ref: ") {
            return URL(fileURLWithPath: String(head.dropFirst(5))).lastPathComponent
        }
        return String(head.prefix(7))
    }

    static func listLocalBranches(in directory: URL) async throws -> [GitBranchInfo] {
        guard isRepository(directory) else { throw GitError.notARepository }
        let output = try await run(
            ["for-each-ref", "--sort=-committerdate", "refs/heads/", "--format=%(refname:short)\t%(HEAD)"],
            in: directory
        )
        return output
            .components(separatedBy: .newlines)
            .compactMap { line -> GitBranchInfo? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let parts = trimmed.split(separator: "\t", omittingEmptySubsequences: false)
                guard let name = parts.first.map(String.init), !name.isEmpty else { return nil }
                let marker = parts.count > 1 ? String(parts[1]) : ""
                return GitBranchInfo(name: name, isCurrent: marker == "*")
            }
    }

    static func listWorktrees(in directory: URL) async throws -> [GitWorktreeInfo] {
        guard isRepository(directory) else { throw GitError.notARepository }
        let output = try await run(["worktree", "list", "--porcelain"], in: directory)
        var worktrees: [GitWorktreeInfo] = []
        var path: URL?
        var branch: String?
        var detached = false

        func flush() {
            guard let path else { return }
            worktrees.append(GitWorktreeInfo(path: path, branch: branch, isDetached: detached))
        }

        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("worktree ") {
                flush()
                path = URL(fileURLWithPath: String(line.dropFirst("worktree ".count)))
                branch = nil
                detached = false
            } else if line.hasPrefix("branch ") {
                branch = String(line.dropFirst("branch ".count))
                    .replacingOccurrences(of: "refs/heads/", with: "")
            } else if line == "detached" {
                detached = true
            } else if line.isEmpty {
                flush()
                path = nil
                branch = nil
                detached = false
            }
        }
        flush()
        return worktrees
    }

    static func gitDirectory(for projectURL: URL) -> URL? {
        let dotGit = projectURL.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else {
            return nil
        }

        if isDirectory.boolValue {
            return dotGit
        }

        guard let content = try? String(contentsOf: dotGit, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              content.hasPrefix("gitdir:") else {
            return nil
        }

        let rawPath = content.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath)
        }
        return projectURL.appendingPathComponent(rawPath).standardizedFileURL
    }
}
