import SwiftUI

struct PreviewPane: View {
    let message: Message?
    let diffs: [ChatStore.DetectedDiff]
    let workspace: Workspace?
    let onApply: (Message) -> Void
    let onApplySingle: ((ChatStore.DetectedDiff) -> Void)?

    @State private var selectedID: UUID?

    private var selected: ChatStore.DetectedDiff? {
        if let id = selectedID,
           let match = diffs.first(where: { $0.id == id }) {
            return match
        }
        return diffs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if !diffs.isEmpty {
                content(for: message)
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

    private func content(for msg: Message?) -> some View {
        VStack(spacing: 0) {
            changedFilesList

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

    private var changedFilesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Changed Files", systemImage: "doc.on.doc")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(diffs.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 4) {
                ForEach(Array(diffs.enumerated()), id: \.element.id) { index, diff in
                    changedFileRow(diff, index: index)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func changedFileRow(_ diff: ChatStore.DetectedDiff, index: Int) -> some View {
        let isSelected = selected?.id == diff.id
        let stats = lineStats(for: diff.raw)

        return Button {
            selectedID = diff.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(diff.filePath ?? "Patch \(index + 1)")
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if stats.added > 0 || stats.removed > 0 {
                    Text("+\(stats.added) -\(stats.removed)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private func lineStats(for diffText: String) -> (added: Int, removed: Int) {
        var added = 0
        var removed = 0
        for line in diffText.components(separatedBy: .newlines) {
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                added += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                removed += 1
            }
        }
        return (added, removed)
    }

    private func actions(for msg: Message?) -> some View {
        HStack(spacing: 8) {
            if msg == nil {
                Label("Existing project changes", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else if let msg {
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
