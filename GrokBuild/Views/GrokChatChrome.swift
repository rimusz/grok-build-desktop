import SwiftUI

struct ChatSessionRow: Identifiable, Hashable {
    enum Status: Hashable {
        case idle
        case working
        case needsYou
        case unread
        case error
    }

    let id: UUID
    let title: String
    let subtitle: String
    let status: Status
    var grokSessionID: String?
}

struct SessionStatusDot: View {
    let status: ChatSessionRow.Status

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch status {
        case .idle: return Color.secondary.opacity(0.45)
        case .working: return .blue
        case .needsYou: return .yellow
        case .unread: return .green
        case .error: return .red
        }
    }
}

struct SessionGearPopover: View {
    @Bindable var store: ChatStore
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model and Effort")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Model", selection: Binding(
                get: { store.currentModel },
                set: { store.setModel($0) }
            )) {
                ForEach(store.availableModels, id: \.self) { modelId in
                    Text(store.modelDisplayName(modelId)).tag(modelId)
                }
            }
            .labelsHidden()

            Divider()

            Button("Compact conversation") {
                Task { _ = await store.send("/compact") }
            }

            Button("Settings…", action: onOpenSettings)

            Divider()

            Text(store.currentModelContextLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 240)
    }
}

struct GrokkingIndicator: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.45)) { context in
            let phase = Int(context.date.timeIntervalSince1970 / 0.45) % 3
            HStack(spacing: 4) {
                Text("Grokking")
                Text(String(repeating: ".", count: phase + 1))
                    .frame(width: 16, alignment: .leading)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

struct ThinkingBlock: View {
    let text: String
    let duration: TimeInterval?
    let isExpanded: Bool
    let isLive: Bool
    var onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                    Text(headerTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded, !text.isEmpty {
                Text(text)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    private var headerTitle: String {
        if isLive { return "Thinking…" }
        if let duration {
            let seconds = max(1, Int(duration.rounded()))
            return "Thought for \(seconds)s"
        }
        return "Thinking"
    }
}

struct ToolCallRow: View {
    let title: String
    let kind: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(title)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(kind)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    private var iconName: String {
        let k = kind.lowercased()
        if k.contains("browser") { return "globe" }
        if k.contains("read") { return "doc.text" }
        if k.contains("edit") || k.contains("write") { return "pencil" }
        if k.contains("exec") || k.contains("run") || k.contains("terminal") { return "terminal" }
        return "wrench"
    }
}

struct ToolActivityGroup: View {
    let tools: [ChatStore.LiveToolCall]
    let isExpanded: Bool
    var onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: summaryIconName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)

                    Text(summaryTitle)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(tools.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tools) { tool in
                        ToolCallRow(title: tool.title, kind: tool.kind)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 3)
    }

    private var summaryTitle: String {
        if tools.count == 1, let tool = tools.first {
            return tool.title
        }
        if browserToolCount == tools.count {
            return "Browser activity"
        }
        if browserToolCount > 0 {
            return "Tool activity · \(browserToolCount) browser"
        }
        return "Tool activity"
    }

    private var summaryIconName: String {
        browserToolCount > 0 ? "globe" : "wrench"
    }

    private var browserToolCount: Int {
        tools.filter { $0.kind.localizedCaseInsensitiveContains("browser") }.count
    }
}
