import SwiftUI

struct MessageBubble: View {
    let message: Message

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
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 0) {
                if !message.content.isEmpty {
                    RichMessageView(text: message.content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .system:
            Text(message.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
        }
    }
}
