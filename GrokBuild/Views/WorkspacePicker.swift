import SwiftUI
import AppKit

struct WorkspacePicker: View {
    var onSelect: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedURL: URL?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Project Folder")
                .font(.title2.weight(.semibold))

            Text("Grok runs inside this folder. All file operations are relative to it.")
                .foregroundStyle(.secondary)
                .font(.callout)

            HStack(alignment: .center, spacing: 12) {
                Button {
                    presentPanel()
                } label: {
                    Label("Choose Folder…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                selectionStatusText
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            HStack(alignment: .center, spacing: 12) {
                Spacer(minLength: 0)
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Button("Use Project") {
                    if let url = selectedURL {
                        onSelect(url)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedURL == nil)
            }
        }
        .padding(28)
        .frame(width: 540)
    }

    @ViewBuilder
    private var selectionStatusText: some View {
        if let url = selectedURL {
            Text(url.path)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text("No project folder selected")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    private func presentPanel() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.prompt = "Choose"
        p.message = "Select the project folder Grok should use as its working directory."

        if p.runModal() == .OK, let u = p.url {
            selectedURL = u
            error = nil
        }
    }
}
