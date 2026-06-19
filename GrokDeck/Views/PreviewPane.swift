import SwiftUI

struct PreviewPane: View {
    let message: Message?
    let diffs: [ChatStore.DetectedDiff]
    let workspace: Workspace?
    let onApply: (Message) -> Void
    let onApplySingle: ((ChatStore.DetectedDiff) -> Void)?

    @State private var selectedID: UUID?

    private var selected: ChatStore.DetectedDiff? {
        if let id = selectedID { return diffs.first { $0.id == id } }
        return diffs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let msg = message, !diffs.isEmpty {
                content(for: msg)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack {
            Label("Preview", systemImage: "sidebar.right")
                .font(.headline)
            Spacer()
            if let ws = workspace {
                Text(ws.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func content(for msg: Message) -> some View {
        VStack(spacing: 0) {
            if diffs.count > 1 {
                Picker("", selection: Binding(
                    get: { selectedID ?? diffs.first!.id },
                    set: { selectedID = $0 }
                )) {
                    ForEach(diffs) { d in
                        Text(d.filePath ?? "patch").tag(d.id)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }

            ScrollView {
                if let d = selected {
                    DiffView(diffText: d.raw, filePath: d.filePath)
                        .padding(12)
                }
            }

            Divider()

            actions(for: msg)
        }
    }

    private func actions(for msg: Message) -> some View {
        HStack(spacing: 8) {
            Button {
                // future: reject / annotate
            } label: {
                Label("Reject", systemImage: "xmark")
            }
            .disabled(true)

            Spacer()

            if let d = selected, let applySingle = onApplySingle {
                Button {
                    applySingle(d)
                } label: {
                    Label("Apply File", systemImage: "arrow.down.doc")
                }
            }

            Button {
                onApply(msg)
            } label: {
                Label("Apply All", systemImage: "arrow.down.doc.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .buttonStyle(.bordered)
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No code changes")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text("When Grok emits diffs or patches they appear here for review and apply.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Diff renderer

struct DiffView: View {
    let diffText: String
    let filePath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p = filePath {
                HStack(spacing: 6) {
                    Image(systemName: "doc")
                    Text(p)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(diffText, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diffLines.enumerated()), id: \.offset) { _, item in
                    Text(item.text)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(item.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(item.background, in: Rectangle())
                }
            }
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var diffLines: [(text: String, color: Color, background: Color)] {
        diffText.components(separatedBy: .newlines).map { raw in
            if raw.hasPrefix("+") && !raw.hasPrefix("+++") {
                return (raw, Color.green, Color.green.opacity(0.10))
            } else if raw.hasPrefix("-") && !raw.hasPrefix("---") {
                return (raw, Color.red, Color.red.opacity(0.10))
            } else if raw.hasPrefix("@@") {
                return (raw, Color.blue, Color.blue.opacity(0.08))
            } else {
                return (raw, .primary, .clear)
            }
        }
    }
}
