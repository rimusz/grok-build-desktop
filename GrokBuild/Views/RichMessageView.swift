import SwiftUI

/// Renders assistant messages with lightweight markdown support.
/// Uses AttributedString (built-in) for headings, code, lists, bold, links.
struct RichMessageView: View {
    let text: String

    var body: some View {
        Text(rendered)
            .textSelection(.enabled)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rendered: AttributedString {
        // Fall back gracefully if markdown parsing fails
        if let attr = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return attr
        }
        return AttributedString(text)
    }
}
