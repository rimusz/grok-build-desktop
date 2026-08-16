import SwiftUI
import WebKit
import AVKit

enum MarkdownBlock: Identifiable, Hashable {
    case text(String)
    case mermaid(String)
    case latex(String, display: Bool)
    case media(InlineMediaRef)
    case code(language: String, source: String)
    case table(headers: [String], rows: [[String]])

    var id: String {
        switch self {
        case .text(let s): return "t-\(s.hashValue)"
        case .mermaid(let s): return "m-\(s.hashValue)"
        case .latex(let s, let d): return "l-\(d)-\(s.hashValue)"
        case .media(let ref): return "media-\(ref.isVideo)-\(ref.source.hashValue)"
        case .code(let language, let source): return "c-\(language)-\(source.hashValue)"
        case .table(let headers, let rows): return "tbl-\(headers.hashValue)-\(rows.hashValue)"
        }
    }
}

enum MarkdownBlockParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var remaining = text

        while !remaining.isEmpty {
            if let match = firstSpecialBlock(in: remaining) {
                let before = String(remaining[..<match.range.lowerBound])
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.text(before))
                }
                blocks.append(match.block)
                remaining = String(remaining[match.range.upperBound...])
            } else {
                blocks.append(.text(remaining))
                break
            }
        }

        return blocks.isEmpty ? [.text(text)] : blocks
    }

    /// True when `$…$` content looks like LaTeX, not currency or shell variables.
    static func looksLikeInlineMath(_ content: String) -> Bool {
        if content.contains("\\") { return true }
        if content.contains(where: { "^_{}".contains($0) }) { return true }
        if content.contains(where: { "=<>≠≤≥≈∝".contains($0) }) { return true }
        return false
    }

    private struct Match {
        let range: Range<String.Index>
        let block: MarkdownBlock
    }

    private static func firstSpecialBlock(in text: String) -> Match? {
        var best: Match?

        if let m = matchFenced(in: text) {
            best = m
        }

        if let m = matchDisplayMath(in: text) {
            if best == nil || m.range.lowerBound < best!.range.lowerBound { best = m }
        }

        if let m = matchInlineMath(in: text) {
            if best == nil || m.range.lowerBound < best!.range.lowerBound { best = m }
        }

        if let m = matchTable(in: text) {
            if best == nil || m.range.lowerBound < best!.range.lowerBound { best = m }
        }

        if let media = InlineMediaParser.firstMedia(in: text) {
            let m = Match(range: media.range, block: .media(media.ref))
            if best == nil || m.range.lowerBound < best!.range.lowerBound { best = m }
        }

        return best
    }

    private static func matchFenced(in text: String) -> Match? {
        let pattern = "```([^\\n`]*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              result.numberOfRanges > 2,
              let fullRange = Range(result.range, in: text),
              let languageRange = Range(result.range(at: 1), in: text),
              let contentRange = Range(result.range(at: 2), in: text) else { return nil }
        let language = String(text[languageRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let content = String(text[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let block: MarkdownBlock
        switch language.lowercased() {
        case "mermaid":
            block = .mermaid(content)
        case "latex", "tex", "math":
            block = .latex(content, display: true)
        default:
            block = .code(language: language, source: content)
        }
        return Match(range: fullRange, block: block)
    }

    private static func matchTable(in text: String) -> Match? {
        let lines = lineSlices(in: text)
        guard lines.count >= 2 else { return nil }
        for index in 0..<(lines.count - 1) {
            guard isTableRow(lines[index].text), isTableSeparator(lines[index + 1].text) else { continue }
            let headers = tableCells(in: lines[index].text)
            guard headers.count >= 2 else { continue }
            var rows: [[String]] = []
            var last = index + 1
            var rowIndex = index + 2
            while rowIndex < lines.count, isTableRow(lines[rowIndex].text) {
                var cells = tableCells(in: lines[rowIndex].text)
                if cells.count < headers.count {
                    cells.append(contentsOf: Array(repeating: "", count: headers.count - cells.count))
                }
                rows.append(Array(cells.prefix(headers.count)))
                last = rowIndex
                rowIndex += 1
            }
            let range = lines[index].range.lowerBound..<lines[last].range.upperBound
            return Match(range: range, block: .table(headers: headers, rows: rows))
        }
        return nil
    }

    private struct LineSlice {
        let range: Range<String.Index>
        let text: String
    }

    private static func lineSlices(in text: String) -> [LineSlice] {
        var result: [LineSlice] = []
        var start = text.startIndex
        while start < text.endIndex {
            if let newline = text[start...].firstIndex(of: "\n") {
                result.append(LineSlice(range: start..<newline, text: String(text[start..<newline])))
                start = text.index(after: newline)
            } else {
                result.append(LineSlice(range: start..<text.endIndex, text: String(text[start...])))
                break
            }
        }
        return result
    }

    static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.filter { $0 == "|" }.count >= 2
    }

    static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return false }
        let stripped = trimmed.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty
    }

    static func tableCells(in line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func matchDisplayMath(in text: String) -> Match? {
        guard let regex = try? NSRegularExpression(pattern: #"\$\$([\s\S]*?)\$\$"#) else { return nil }
        let ns = text as NSString
        guard let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              result.numberOfRanges > 1,
              let fullRange = Range(result.range, in: text),
              let contentRange = Range(result.range(at: 1), in: text) else { return nil }
        return Match(range: fullRange, block: .latex(String(text[contentRange]), display: true))
    }

    private static func matchInlineMath(in text: String) -> Match? {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\$)\$(?!\$)([^\$\n]+?)\$(?!\$)"#) else { return nil }
        let ns = text as NSString
        for result in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard result.numberOfRanges > 1,
                  let fullRange = Range(result.range, in: text),
                  let contentRange = Range(result.range(at: 1), in: text) else { continue }
            let content = String(text[contentRange])
            guard looksLikeInlineMath(content) else { continue }
            return Match(range: fullRange, block: .latex(content, display: false))
        }
        return nil
    }
}

/// Line-oriented markdown so session answers match grok CLI: blue headings, cyan
/// ``code``, lists, and preserved ASCII diagrams (not HTML paragraph wrapping).
enum GrokMarkdownStyle {
    static let headingColor = Color(red: 88 / 255, green: 166 / 255, blue: 255 / 255)
    static let codeColor = Color(red: 125 / 255, green: 207 / 255, blue: 255 / 255)

    static func attributed(_ chunk: String) -> AttributedString {
        var result = AttributedString()
        let parts = chunk.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for (index, part) in parts.enumerated() {
            result.append(attributedLine(String(part)))
            if index < parts.count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    static func attributedLine(_ line: String) -> AttributedString {
        if let heading = heading(from: line) {
            var styled = inline(heading.text)
            styled.foregroundColor = headingColor
            styled.font = headingFont(level: heading.level)
            for run in styled.runs {
                if run.inlinePresentationIntent?.contains(.code) == true {
                    styled[run.range].foregroundColor = codeColor
                    styled[run.range].font = headingFont(level: heading.level).monospaced()
                }
            }
            return styled
        }
        if let item = listItem(from: line) {
            var prefix = AttributedString(item.prefix)
            prefix.append(inline(item.text))
            return prefix
        }
        return inline(line)
    }

    static func heading(from line: String) -> (level: Int, text: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(#{1,6})\s+(.+)$"#) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 2,
              let hashes = Range(match.range(at: 1), in: line),
              let body = Range(match.range(at: 2), in: line) else { return nil }
        return (String(line[hashes]).count, String(line[body]))
    }

    static func listItem(from line: String) -> (prefix: String, text: String)? {
        guard let unordered = try? NSRegularExpression(pattern: #"^(\s*)([-*+])\s+(.+)$"#) else { return nil }
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let match = unordered.firstMatch(in: line, range: full),
           match.numberOfRanges > 3,
           let indent = Range(match.range(at: 1), in: line),
           let body = Range(match.range(at: 3), in: line) {
            return (String(line[indent]) + "• ", String(line[body]))
        }
        guard let ordered = try? NSRegularExpression(pattern: #"^(\s*)(\d+\.)\s+(.+)$"#) else { return nil }
        if let match = ordered.firstMatch(in: line, range: full),
           match.numberOfRanges > 3,
           let indent = Range(match.range(at: 1), in: line),
           let number = Range(match.range(at: 2), in: line),
           let body = Range(match.range(at: 3), in: line) {
            return (String(line[indent]) + String(line[number]) + " ", String(line[body]))
        }
        return nil
    }

    static func inline(_ text: String) -> AttributedString {
        var attr = (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(text)
        for run in attr.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                attr[run.range].foregroundColor = codeColor
                attr[run.range].font = .body.monospaced()
            }
        }
        return attr
    }

    static func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.semibold)
        case 2: return .title3.weight(.semibold)
        default: return .headline
        }
    }
}

struct RichMessageView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MarkdownBlockParser.parse(text)) { block in
                switch block {
                case .text(let chunk):
                    Text(GrokMarkdownStyle.attributed(chunk))
                        .textSelection(.enabled)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .mermaid(let source):
                    SizedMermaidWebView(source: source)
                case .latex(let expr, let display):
                    SizedLaTeXWebView(latex: expr, displayMode: display)
                case .media(let ref):
                    InlineMediaView(ref: ref)
                case .code(_, let source):
                    MarkdownCodeBlockView(source: source)
                case .table(let headers, let rows):
                    MarkdownTableView(headers: headers, rows: rows)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownCodeBlockView: View {
    let source: String

    var body: some View {
        Text(source)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    tableCell(header, header: true)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                        tableCell(value, header: false)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.primary.opacity(0.28), lineWidth: 1)
        )
    }

    private func tableCell(_ text: String, header: Bool) -> some View {
        Text(GrokMarkdownStyle.inline(text))
            .font(header ? .callout.weight(.semibold) : .body)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.primary.opacity(0.22)).frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.22)).frame(height: 1)
            }
    }
}

/// Renders an inline image or video preview from an assistant/`imagine` media reference,
/// falling back to a tappable link when the source can't be loaded.
struct InlineMediaView: View {
    let ref: InlineMediaRef

    private var resolvedURL: URL? {
        if let url = URL(string: ref.source), let scheme = url.scheme,
           scheme == "http" || scheme == "https" {
            return url
        }
        if ref.source.hasPrefix("/") {
            let path = (ref.source as NSString).expandingTildeInPath
            return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        if ref.source.hasPrefix("~") {
            let path = (ref.source as NSString).expandingTildeInPath
            return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        return nil
    }

    var body: some View {
        Group {
            if let url = resolvedURL {
                if ref.isVideo {
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(maxWidth: 420, minHeight: 200, maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    imageView(for: url)
                }
            } else {
                fallbackLink
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func imageView(for url: URL) -> some View {
        if url.isFileURL {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 420, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                fallbackLink
            }
        } else {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 420, maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure:
                    fallbackLink
                case .empty:
                    ProgressView().frame(width: 40, height: 40)
                @unknown default:
                    fallbackLink
                }
            }
        }
    }

    private var fallbackLink: some View {
        Group {
            if let url = URL(string: ref.source), url.scheme != nil {
                Link(destination: url) {
                    Label(ref.source, systemImage: ref.isVideo ? "film" : "photo")
                        .font(.caption)
                }
            } else {
                Label(ref.source, systemImage: ref.isVideo ? "film" : "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct SizedMermaidWebView: View {
    let source: String
    private let minHeight: CGFloat = 120
    @State private var height: CGFloat = 120

    var body: some View {
        MermaidWebView(source: source) { newHeight in
            // Never shrink below the fallback: a premature/small scrollHeight
            // (mermaid renders after didFinish) must not collapse the block.
            let clamped = max(newHeight, minHeight)
            if abs(clamped - height) > 1 {
                height = clamped
            }
        }
        .frame(height: height)
    }
}

private struct SizedLaTeXWebView: View {
    let latex: String
    let displayMode: Bool
    private let minHeight: CGFloat
    @State private var height: CGFloat

    init(latex: String, displayMode: Bool) {
        self.latex = latex
        self.displayMode = displayMode
        let floorHeight: CGFloat = displayMode ? 48 : 28
        self.minHeight = floorHeight
        _height = State(initialValue: floorHeight)
    }

    var body: some View {
        LaTeXWebView(latex: latex, displayMode: displayMode) { newHeight in
            let clamped = max(newHeight, minHeight)
            if abs(clamped - height) > 1 {
                height = clamped
            }
        }
        .frame(height: height)
    }
}

private struct MermaidWebView: NSViewRepresentable {
    let source: String
    var onHeightChange: (CGFloat) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onHeightChange = onHeightChange
        guard source != context.coordinator.lastLoadedSource else { return }
        context.coordinator.lastLoadedSource = source
        view.loadHTMLString(Self.html(for: source), baseURL: nil)
    }

    private static func html(for source: String) -> String {
        let escaped = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        return """
        <!doctype html><html><head>
        <meta charset="utf-8">
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        <style>body{margin:0;padding:8px;background:transparent;color:#ccc;font-family:-apple-system,sans-serif}</style>
        </head><body><div class="mermaid">\(escaped)</div>
        <script>mermaid.initialize({startOnLoad:true,theme:'dark'});</script></body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedSource: String?
        var onHeightChange: (CGFloat) -> Void

        init(onHeightChange: @escaping (CGFloat) -> Void) {
            self.onHeightChange = onHeightChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                guard let height = webViewScrollHeight(from: result) else { return }
                DispatchQueue.main.async {
                    self.onHeightChange(height)
                }
            }
        }
    }
}

private func webViewScrollHeight(from result: Any?) -> CGFloat? {
    let raw: CGFloat?
    if let value = result as? Double { raw = CGFloat(value) }
    else if let value = result as? Int { raw = CGFloat(value) }
    else if let value = result as? CGFloat { raw = value }
    else { raw = nil }
    // Ignore non-positive readings (transient/blocked load) so the fallback height holds.
    guard let height = raw, height > 0 else { return nil }
    return height
}

private struct LaTeXWebView: NSViewRepresentable {
    let latex: String
    let displayMode: Bool
    var onHeightChange: (CGFloat) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onHeightChange = onHeightChange
        let key = "\(displayMode)|\(latex)"
        guard key != context.coordinator.lastLoadedKey else { return }
        context.coordinator.lastLoadedKey = key
        view.loadHTMLString(Self.html(latex: latex, displayMode: displayMode), baseURL: nil)
    }

    private static func html(latex: String, displayMode: Bool) -> String {
        let escaped = latex
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
        return """
        <!doctype html><html><head>
        <meta charset="utf-8">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
        <script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
        <style>body{margin:0;padding:4px 8px;background:transparent}</style>
        </head><body><div id="math"></div>
        <script>
        katex.render('\(escaped)', document.getElementById('math'), { displayMode: \(displayMode ? "true" : "false"), throwOnError: false });
        </script></body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedKey: String?
        var onHeightChange: (CGFloat) -> Void

        init(onHeightChange: @escaping (CGFloat) -> Void) {
            self.onHeightChange = onHeightChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                guard let height = webViewScrollHeight(from: result) else { return }
                DispatchQueue.main.async {
                    self.onHeightChange(height)
                }
            }
        }
    }
}
