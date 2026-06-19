import SwiftUI
import AppKit

struct WorkspacePicker: View {
    var onSelect: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedURL: URL?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose Workspace Folder")
                .font(.title2.weight(.semibold))

            Text("Grok runs inside this folder. All file operations are relative to it.")
                .foregroundStyle(.secondary)
                .font(.callout)

            HStack {
                Button {
                    presentPanel()
                } label: {
                    Label("Choose Folder…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)

                if let url = selectedURL {
                    Text(url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use Folder") {
                    if let url = selectedURL {
                        onSelect(url)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedURL == nil)
            }
        }
        .padding(28)
        .frame(width: 540, height: 220)
    }

    private func presentPanel() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.prompt = "Choose"
        p.message = "Select the folder Grok should use as its working directory."

        if p.runModal() == .OK, let u = p.url {
            selectedURL = u
            error = nil
        }
    }
}
