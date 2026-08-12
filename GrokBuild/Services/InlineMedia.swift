import Foundation

/// An image or video reference detected in assistant output (e.g. `/imagine` results) that the
/// chat can preview inline.
struct InlineMediaRef: Hashable, Sendable {
    let source: String
    let isVideo: Bool
}

/// Extracts inline media references from assistant text: markdown images (`![alt](url)`) and
/// standalone image/video paths or URLs. Used by `MarkdownBlockParser` to render previews.
enum InlineMediaParser {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "svg"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm"]

    private static var allExtensions: Set<String> { imageExtensions.union(videoExtensions) }

    private static func isVideo(_ source: String) -> Bool {
        videoExtensions.contains(`extension`(of: source))
    }

    private static func `extension`(of source: String) -> String {
        // Strip query/fragment before reading the extension.
        let trimmed = source.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? source
        return (trimmed as NSString).pathExtension.lowercased()
    }

    static func isMediaSource(_ source: String) -> Bool {
        allExtensions.contains(`extension`(of: source))
    }

    /// Returns the earliest media reference in `text` along with the range to replace with a
    /// preview. Markdown images consume their full `![…](…)` syntax; standalone tokens consume
    /// only the URL/path token (leading whitespace is preserved for surrounding text).
    static func firstMedia(in text: String) -> (range: Range<String.Index>, ref: InlineMediaRef)? {
        var best: (range: Range<String.Index>, ref: InlineMediaRef)?

        if let markdown = matchMarkdownImage(in: text) {
            best = markdown
        }
        if let standalone = matchStandalone(in: text) {
            if best == nil || standalone.range.lowerBound < best!.range.lowerBound {
                best = standalone
            }
        }
        return best
    }

    private static func matchMarkdownImage(in text: String) -> (range: Range<String.Index>, ref: InlineMediaRef)? {
        guard let regex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)\s]+)\)"#) else { return nil }
        let ns = text as NSString
        guard let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              result.numberOfRanges > 1,
              let fullRange = Range(result.range, in: text),
              let sourceRange = Range(result.range(at: 1), in: text) else { return nil }
        let source = String(text[sourceRange])
        return (fullRange, InlineMediaRef(source: source, isVideo: isVideo(source)))
    }

    private static func matchStandalone(in text: String) -> (range: Range<String.Index>, ref: InlineMediaRef)? {
        let extList = allExtensions.sorted().joined(separator: "|")
        let pattern = #"(?:^|\s)(\S+\.(?:"# + extList + #"))(?=$|\s)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              result.numberOfRanges > 1,
              let sourceRange = Range(result.range(at: 1), in: text) else { return nil }
        let source = String(text[sourceRange])
        return (sourceRange, InlineMediaRef(source: source, isVideo: isVideo(source)))
    }
}
