import SwiftUI
import WebKit
import AVKit

enum MarkdownBlock: Identifiable, Hashable {
    case text(String)
    case mermaid(String)
    case latex(String, display: Bool)
    case media(InlineMediaRef)

    var id: String {
        switch self {
        case .text(let s): return "t-\(s.hashValue)"
        case .mermaid(let s): return "m-\(s.hashValue)"
        case .latex(let s, let d): return "l-\(d)-\(s.hashValue)"
        case .media(let ref): return "media-\(ref.isVideo)-\(ref.source.hashValue)"
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

        if let media = InlineMediaParser.firstMedia(in: text) {
            let m = Match(range: media.range, block: .media(media.ref))
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
                    SizedMermaidWebView(source: source)
                case .latex(let expr, let display):
                    SizedLaTeXWebView(latex: expr, displayMode: display)
                case .media(let ref):
                    InlineMediaView(ref: ref)
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
