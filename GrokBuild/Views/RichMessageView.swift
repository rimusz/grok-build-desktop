import SwiftUI
import WebKit

enum MarkdownBlock: Identifiable, Hashable {
    case text(String)
    case mermaid(String)
    case latex(String, display: Bool)

    var id: String {
        switch self {
        case .text(let s): return "t-\(s.hashValue)"
        case .mermaid(let s): return "m-\(s.hashValue)"
        case .latex(let s, let d): return "l-\(d)-\(s.hashValue)"
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

    private struct Match {
        let range: Range<String.Index>
        let block: MarkdownBlock
    }

    private static func firstSpecialBlock(in text: String) -> Match? {
        var best: Match?

        if let m = matchFenced(in: text, language: "mermaid") {
            best = m
        }

        for lang in ["latex", "tex", "math"] {
            if let m = matchFenced(in: text, language: lang) {
                if best == nil || m.range.lowerBound < best!.range.lowerBound { best = m }
            }
        }

        if let m = matchDisplayMath(in: text) {
            if best == nil || m.range.lowerBound < best!.range.lowerBound { best = m }
        }

        if let m = matchInlineMath(in: text) {
            if best == nil || m.range.lowerBound < best!.range.lowerBound { best = m }
        }

        return best
    }

    private static func matchFenced(in text: String, language: String) -> Match? {
        let pattern = "```\(language)\\s*([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              result.numberOfRanges > 1,
              let fullRange = Range(result.range, in: text),
              let contentRange = Range(result.range(at: 1), in: text) else { return nil }
        let content = String(text[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let block: MarkdownBlock = language.lowercased() == "mermaid"
            ? .mermaid(content)
            : .latex(content, display: true)
        return Match(range: fullRange, block: block)
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
        guard let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              result.numberOfRanges > 1,
              let fullRange = Range(result.range, in: text),
              let contentRange = Range(result.range(at: 1), in: text) else { return nil }
        return Match(range: fullRange, block: .latex(String(text[contentRange]), display: false))
    }
}

struct RichMessageView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MarkdownBlockParser.parse(text)) { block in
                switch block {
                case .text(let chunk):
                    Text(renderedMarkdown(chunk))
                        .textSelection(.enabled)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .mermaid(let source):
                    MermaidWebView(source: source)
                        .frame(minHeight: 120)
                case .latex(let expr, let display):
                    LaTeXWebView(latex: expr, displayMode: display)
                        .frame(minHeight: display ? 48 : 28)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func renderedMarkdown(_ chunk: String) -> AttributedString {
        if let attr = try? AttributedString(
            markdown: chunk,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return attr
        }
        return AttributedString(chunk)
    }
}

private struct MermaidWebView: NSViewRepresentable {
    let source: String

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let escaped = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let html = """
        <!doctype html><html><head>
        <meta charset="utf-8">
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        <style>body{margin:0;padding:8px;background:transparent;color:#ccc;font-family:-apple-system,sans-serif}</style>
        </head><body><div class="mermaid">\(escaped)</div>
        <script>mermaid.initialize({startOnLoad:true,theme:'dark'});</script></body></html>
        """
        view.loadHTMLString(html, baseURL: nil)
    }
}

private struct LaTeXWebView: NSViewRepresentable {
    let latex: String
    let displayMode: Bool

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let escaped = latex
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
        let html = """
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
        view.loadHTMLString(html, baseURL: nil)
    }
}
