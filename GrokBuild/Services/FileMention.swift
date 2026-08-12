import Foundation

/// Detects and applies `@` file mentions in the composer input, mirroring `SlashAutocomplete`.
///
/// A mention is triggered by an `@` at the start of the input or after whitespace, followed by
/// an optional (possibly partial) path query with no whitespace. Selecting a match inserts
/// `@<path> ` so grok reads the referenced file.
enum FileMentionMatch {
    /// Returns the current query and the range of the `@…` token at the end of `text`, if any.
    static func match(in text: String) -> (query: String, range: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:^|\s)@([^\s@]*)$"#) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let result = regex.firstMatch(in: text, range: range),
              result.numberOfRanges > 1,
              let fullRange = Range(result.range, in: text),
              let queryRange = Range(result.range(at: 1), in: text) else { return nil }
        return (String(text[queryRange]), fullRange)
    }

    /// Replaces the matched `@…` token with `@<path> `, preserving any leading whitespace.
    static func apply(path: String, to text: String, matchRange: Range<String.Index>) -> String {
        let leading = text[matchRange.lowerBound]
        let prefix = leading.isWhitespace ? String(leading) : ""
        return text.replacingCharacters(in: matchRange, with: "\(prefix)@\(path) ")
    }
}

/// Fuzzy-filters workspace-relative paths for the `@` mention popover.
enum FileMentionFilter {
    /// Ranks `files` against `query`. An empty query returns the head of the list. Matches are
    /// ordered: filename prefix, filename substring, path substring, then subsequence; ties break
    /// on shorter paths then lexicographically.
    static func filter(_ files: [String], query: String, limit: Int = 8) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return Array(files.prefix(limit)) }

        var scored: [(path: String, score: Int)] = []
        for path in files {
            if let score = rank(path: path, query: trimmed) {
                scored.append((path, score))
            }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            if lhs.path.count != rhs.path.count { return lhs.path.count < rhs.path.count }
            return lhs.path < rhs.path
        }
        return scored.prefix(limit).map(\.path)
    }

    private static func rank(path: String, query: String) -> Int? {
        let lowerPath = path.lowercased()
        let fileName = (lowerPath as NSString).lastPathComponent
        if fileName.hasPrefix(query) { return 0 }
        if fileName.contains(query) { return 1 }
        if lowerPath.contains(query) { return 2 }
        if isSubsequence(query, of: lowerPath) { return 3 }
        return nil
    }

    /// True when every character of `needle` appears in `haystack` in order.
    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var it = haystack.makeIterator()
        for ch in needle {
            var matched = false
            while let next = it.next() {
                if next == ch { matched = true; break }
            }
            if !matched { return false }
        }
        return true
    }
}

/// Enumerates workspace files (relative paths) for `@` mentions, skipping heavyweight and
/// generated directories and capping the count for responsiveness.
enum FileMentionIndex {
    static let skippedDirectories: Set<String> = [
        ".git", "node_modules", ".build", ".swiftpm", "dist", "build",
        ".next", "DerivedData", "Pods", ".venv", "venv", "__pycache__",
        ".idea", ".gradle", "target", "vendor", ".terraform"
    ]

    /// Returns workspace-relative file paths under `root`, skipping ignored directories and
    /// stopping at `cap` entries.
    static func enumerate(root: URL, cap: Int = 2000) -> [String] {
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        guard let enumerator = fm.enumerator(
            at: root.standardizedFileURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [String] = []
        for case let url as URL in enumerator {
            if results.count >= cap { break }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                if skippedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            if path.hasPrefix(rootPath + "/") {
                results.append(String(path.dropFirst(rootPath.count + 1)))
            }
        }
        return results
    }
}
