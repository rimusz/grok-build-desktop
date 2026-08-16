import SwiftUI

struct MessageBubble: View {
    let message: Message
    /// When true, render assistant text plainly — `RichMessageView` re-parses the full
    /// body on every chunk and can freeze the UI on long streaming turns.
    var isStreaming: Bool = false
    /// Chat-only rewind: keep transcript up to this message. Nil hides the menu item.
    var onRewind: (() -> Void)? = nil
    var rewindDisabled: Bool = false

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.content)
                    .textSelection(.enabled)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: 420, alignment: .trailing)
                    .modifier(MessageRewindMenu(onRewind: onRewind, disabled: rewindDisabled))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                if message.hasActivityParts {
                    ForEach(Array(message.parts.enumerated()), id: \.offset) { _, part in
                        switch part {
                        case .text(let text):
                            assistantText(text)
                        case .activity(let line):
                            GrokActivityLineView(line: line)
                        }
                    }
                    .modifier(MessageRewindMenu(onRewind: onRewind, disabled: rewindDisabled))
                } else if !message.content.isEmpty {
                    assistantText(message.content)
                        .modifier(MessageRewindMenu(onRewind: onRewind, disabled: rewindDisabled))
                }
            }
        case .system:
            Text(message.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
                .modifier(MessageRewindMenu(onRewind: onRewind, disabled: rewindDisabled))
        }
    }

    @ViewBuilder
    private func assistantText(_ text: String) -> some View {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyView()
        } else if isStreaming {
            Text(text)
                .textSelection(.enabled)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            RichMessageView(text: text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MessageRewindMenu: ViewModifier {
    var onRewind: (() -> Void)?
    var disabled: Bool

    func body(content: Content) -> some View {
        if let onRewind {
            content.contextMenu {
                Button("Rewind to Here…") {
                    onRewind()
                }
                .disabled(disabled)
            }
        } else {
            content
        }
    }
}
