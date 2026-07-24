import SwiftUI
import AppKit

/// Browser for saved `.rhai` workflows under `.grok/workflows/` (project) and `~/.grok/workflows/`.
struct SavedWorkflowsPanel: View {
    let projectRoot: URL?
    var onLaunch: (SavedWorkflow, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var workflows: [SavedWorkflow] = []
    @State private var query = ""
    @State private var selection: SavedWorkflow.ID?
    @State private var argsJSON = ""
    @State private var errorMessage: String?

    private var filtered: [SavedWorkflow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return workflows }
        return workflows.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.description.localizedCaseInsensitiveContains(q)
        }
    }

    private var selected: SavedWorkflow? {
        workflows.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                WindowTrafficLights(onClose: { dismiss() })
                    .keyboardShortcut(.cancelAction)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved Workflows")
                        .font(.title2.weight(.semibold))
                    Text("Project `.grok/workflows/` and `~/.grok/workflows/`")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            TextField("Filter workflows", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            Divider()

            HSplitView {
                List(selection: $selection) {
                    if filtered.isEmpty {
                        Text("No saved workflows found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { workflow in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(workflow.name)
                                        .font(.body.weight(.medium))
                                    Spacer()
                                    Text(workflow.scope == .project ? "Project" : "User")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.secondary.opacity(0.14)))
                                }
                                if !workflow.description.isEmpty {
                                    Text(workflow.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .tag(workflow.id)
                        }
                    }
                }
                .frame(minWidth: 260, idealWidth: 320)

                detailPane
                    .frame(minWidth: 280)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .onAppear(perform: reload)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let workflow = selected {
            VStack(alignment: .leading, spacing: 14) {
                Text(workflow.name)
                    .font(.title3.weight(.semibold))
                Text(workflow.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if !workflow.description.isEmpty {
                    Text(workflow.description)
                        .font(.callout)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Optional JSON args")
                        .font(.caption.weight(.semibold))
                    TextField(#"{"target":"origin/main...HEAD"}"#, text: $argsJSON, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }

                HStack {
                    Button {
                        SavedWorkflowStore.revealInFinder(workflow.url)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }

                    Spacer()

                    Button("Launch") {
                        onLaunch(workflow, argsJSON)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        } else {
            ContentUnavailableView(
                "Select a Workflow",
                systemImage: "arrow.triangle.branch",
                description: Text("Choose a saved `.rhai` workflow to launch or reveal.")
            )
        }
    }

    private func reload() {
        workflows = SavedWorkflowStore.load(projectRoot: projectRoot)
        if selection == nil {
            selection = workflows.first?.id
        } else if !workflows.contains(where: { $0.id == selection }) {
            selection = workflows.first?.id
        }
        errorMessage = nil
    }
}

/// Sheet to kick off `/deep-research <query>`.
struct DeepResearchSheet: View {
    var onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Deep Research")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Text("Fans research questions out to parallel investigators and returns a cited report. Progress appears in the Workflows pill.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("Research query", text: $query, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)

            HStack {
                Spacer()
                Button("Start Research") {
                    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSubmit(trimmed)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480)
    }
}
