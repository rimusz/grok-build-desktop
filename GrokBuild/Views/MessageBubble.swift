import SwiftUI

struct MessageBubble: View {
    let message: Message
    var onPreview: ((Message) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 80) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                header

                content
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(background, in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: 640, alignment: message.role == .user ? .trailing : .leading)

                if message.role == .assistant && message.hasDiff {
                    Button {
                        onPreview?(message)
                    } label: {
                        Label("View & Apply Diffs", systemImage: "doc.text.magnifyingglass")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.link)
                }
            }

            if message.role != .user { Spacer(minLength: 80) }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: roleIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(roleColor)
            Text(roleLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(message.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var content: some View {
        Group {
            if message.role == .assistant {
                RichMessageView(text: message.content)
            } else {
                Text(message.content)
                    .textSelection(.enabled)
                    .font(.body)
            }
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user: "You"
        case .assistant: "Grok"
        case .system: "System"
        }
    }

    private var roleIcon: String {
        switch message.role {
        case .user: "person.fill"
        case .assistant: "sparkles"
        case .system: "info.circle"
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user: .blue
        case .assistant: .purple
        case .system: .secondary
        }
    }

    private var background: some ShapeStyle {
        switch message.role {
        case .user:
            AnyShapeStyle(Color.accentColor.opacity(0.16))
        case .assistant:
            AnyShapeStyle(.regularMaterial)
        case .system:
            AnyShapeStyle(.thinMaterial)
        }
    }
}
