import SwiftUI
import AppKit

/// Read-only browser over grok's `~/.grok/memory/` files, modeled on `SessionsBrowserPanel`:
/// a grouped list on the left and a read-only preview on the right. Session logs can be deleted
/// (with confirmation); global/workspace `MEMORY.md` are protected, matching grok's TUI `/memory`.
struct MemoryBrowserPanel: View {
    var showsHeader: Bool = true

    @Environment(\.dismiss) private var dismiss

    @State private var files: [MemoryFile] = []
    @State private var query = ""
    @State private var selection: MemoryFile.ID?
    @State private var previewText = ""
    @State private var errorMessage: String?
    @State private var pendingDeletion: MemoryFile?

    private struct MemorySection: Identifiable {
        let id: String
        let title: String
        let files: [MemoryFile]
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HStack(alignment: .center, spacing: 12) {
                    WindowTrafficLights(onClose: { dismiss() })
                        .keyboardShortcut(.cancelAction)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Memory")
                            .font(.title2.weight(.semibold))
                        Text(MemoryStore.baseURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)

                    Button {
                        reload()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .padding()

                Divider()
            }

            HStack {
                TextField("Filter memory files", text: $query)
                    .textFieldStyle(.roundedBorder)
                if !showsHeader {
                    Button {
                        reload()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, showsHeader ? 12 : 8)

            Divider()

            HSplitView {
                fileList
                    .frame(minWidth: 240, idealWidth: 300, maxWidth: 420)
                previewPane
                    .frame(minWidth: 320, maxWidth: .infinity)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(8)
            }
        }
        .frame(minWidth: showsHeader ? 720 : 0, minHeight: showsHeader ? 480 : 0)
        .task { reload() }
        .onChange(of: selection) { _, _ in loadPreview() }
        .alert(item: $pendingDeletion) { file in
            Alert(
                title: Text("Delete Memory Log?"),
                message: Text("“\(file.title)” will be permanently removed from \(file.workspaceLabel ?? "this project")'s memory. This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) { delete(file) },
                secondaryButton: .cancel()
            )
        }
    }

    private var fileList: some View {
        List(selection: $selection) {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.files) { file in
                        row(file)
                            .tag(file.id)
                            .contextMenu { rowMenu(file) }
                    }
                }
            }
        }
        .overlay {
            if files.isEmpty {
                ContentUnavailableView(
                    "No Memory Files",
                    systemImage: "brain",
                    description: Text("Nothing saved under \(MemoryStore.baseURL.path) yet. Enable memory and let Grok recall or save facts across sessions.")
                )
                .padding()
            } else if sections.isEmpty {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "magnifyingglass",
                    description: Text("No memory files matched your filter.")
                )
            }
        }
    }

    private func row(_ file: MemoryFile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon(for: file.scope))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let modified = file.modifiedAt {
                    Text(modified, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func rowMenu(_ file: MemoryFile) -> some View {
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.path, forType: .string)
        }
        Button("Reveal in Finder") {
            MemoryStore.revealInFinder(file)
        }
        if file.scope == .session {
            Divider()
            Button("Delete Log", role: .destructive) {
                pendingDeletion = file
            }
        }
    }

    private var previewPane: some View {
        Group {
            if let file = selectedFile {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(file.title)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            MemoryStore.revealInFinder(file)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")
                    }
                    .padding(10)
                    Divider()
                    ScrollView {
                        Text(previewText.isEmpty ? "(empty)" : previewText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select a File",
                    systemImage: "doc.text",
                    description: Text("Pick a memory file to preview its contents.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedFile: MemoryFile? {
        files.first { $0.id == selection }
    }

    private var filteredFiles: [MemoryFile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return files }
        return files.filter {
            $0.title.lowercased().contains(trimmed)
                || ($0.workspaceLabel?.lowercased().contains(trimmed) ?? false)
                || $0.path.lowercased().contains(trimmed)
        }
    }

    private var sections: [MemorySection] {
        let filtered = filteredFiles
        var result: [MemorySection] = []

        let globals = filtered.filter { $0.scope == .global }
        if !globals.isEmpty {
            result.append(MemorySection(id: "global", title: "Global", files: globals))
        }

        var order: [String] = []
        var byLabel: [String: [MemoryFile]] = [:]
        for file in filtered where file.scope != .global {
            let label = file.workspaceLabel ?? "Workspace"
            if byLabel[label] == nil { order.append(label) }
            byLabel[label, default: []].append(file)
        }
        for label in order {
            result.append(MemorySection(id: label, title: "Workspace · \(label)", files: byLabel[label] ?? []))
        }
        return result
    }

    private func icon(for scope: MemoryScope) -> String {
        switch scope {
        case .global: return "globe"
        case .workspace: return "folder"
        case .session: return "clock"
        }
    }

    private func reload() {
        files = MemoryStore.load()
        if selection == nil || !files.contains(where: { $0.id == selection }) {
            selection = files.first?.id
        }
        loadPreview()
    }

    private func loadPreview() {
        guard let file = selectedFile else {
            previewText = ""
            return
        }
        previewText = MemoryStore.readContents(file) ?? "(could not read file)"
    }

    private func delete(_ file: MemoryFile) {
        do {
            try MemoryStore.deleteSessionFile(file)
            if selection == file.id { selection = nil }
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
