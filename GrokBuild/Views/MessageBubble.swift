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
            VStack(alignment: .leading, spacing: 0) {
                if !message.content.isEmpty {
                    if isStreaming {
                        Text(message.content)
                            .textSelection(.enabled)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(MessageRewindMenu(onRewind: onRewind, disabled: rewindDisabled))
                    } else {
                        RichMessageView(text: message.content)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(MessageRewindMenu(onRewind: onRewind, disabled: rewindDisabled))
                    }
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
