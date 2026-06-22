import SwiftUI

struct GitCheckoutRequest: Identifiable {
    let project: Workspace
    var focusCreateWorktree: Bool = false

    var id: Workspace.ID { project.id }
}

struct GitCheckoutSheet: View {
    let project: Workspace
    var focusCreateWorktree: Bool
    var onSwitchBranch: (String) -> Void
    var onOpenWorktree: (GitWorktreeInfo) -> Void
    var onCreateBranch: (String) -> Void
    var onCreateWorktree: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var branches: [GitBranchInfo] = []
    @State private var worktrees: [GitWorktreeInfo] = []
    @State private var currentBranch: String?
    @State private var filter = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showNewBranchForm = false
    @State private var showNewWorktreeForm = false
    @State private var newBranchName = ""
    @State private var newWorktreeBranch = ""
    @State private var newWorktreePath = ""

    private var filteredBranches: [GitBranchInfo] {
        guard !filter.isEmpty else { return branches }
        return branches.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    private var filteredWorktrees: [GitWorktreeInfo] {
        guard !filter.isEmpty else { return worktrees }
        return worktrees.filter {
            $0.path.path.localizedCaseInsensitiveContains(filter) ||
            $0.branchLabel.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            TextField("Search branches and worktrees", text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !filteredBranches.isEmpty {
                        sectionHeader("Branches")
                        ForEach(filteredBranches) { branch in
                            branchRow(branch)
                        }
                    }

                    if !filteredWorktrees.isEmpty {
                        sectionHeader("Worktrees")
                        ForEach(filteredWorktrees) { worktree in
                            worktreeRow(worktree)
                        }
                    }

                    if filteredBranches.isEmpty && filteredWorktrees.isEmpty && !isLoading {
                        Text(filter.isEmpty ? "No branches or worktrees found." : "No matches.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                    }

                    sectionHeader("Create")
                    createSection
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Divider()

            HStack {
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
        }
        .frame(width: 520, height: 560)
        .task { await reload() }
        .onAppear {
            if focusCreateWorktree {
                showNewWorktreeForm = true
                if newWorktreePath.isEmpty {
                    let sibling = project.path.deletingLastPathComponent()
                    newWorktreePath = sibling
                        .appendingPathComponent("\(project.path.lastPathComponent)-worktree")
                        .path
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Git Branches & Worktrees")
                .font(.title2.weight(.semibold))
            Text(project.displayName)
                .font(.headline)
            Text(project.path.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let currentBranch {
                Text("Current branch: \(currentBranch)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func branchRow(_ branch: GitBranchInfo) -> some View {
        Button {
            guard !branch.isCurrent else { return }
            onSwitchBranch(branch.name)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(branch.name)
                    .font(.body)
                Spacer()
                if branch.isCurrent {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(branch.isCurrent)
    }

    private func worktreeRow(_ worktree: GitWorktreeInfo) -> some View {
        let isCurrentCheckout = worktree.path.standardizedFileURL.path == project.path.standardizedFileURL.path

        return Button {
            onOpenWorktree(worktree)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(worktree.branchLabel)
                        .font(.body)
                    Text(worktree.path.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if isCurrentCheckout {
                    Text("Here")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var createSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup("New branch", isExpanded: $showNewBranchForm) {
                HStack {
                    TextField("Branch name", text: $newBranchName)
                        .textFieldStyle(.roundedBorder)
                    Button("Create & switch") {
                        let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        onCreateBranch(name)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 16)

            DisclosureGroup("New worktree", isExpanded: $showNewWorktreeForm) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("New branch name", text: $newWorktreeBranch)
                        .textFieldStyle(.roundedBorder)
                    TextField("Worktree path", text: $newWorktreePath)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Spacer()
                        Button("Create worktree") {
                            let branch = newWorktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines)
                            let path = newWorktreePath.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !branch.isEmpty, !path.isEmpty else { return }
                            onCreateWorktree(branch, path)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            newWorktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            newWorktreePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    @MainActor
    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        currentBranch = GitService.currentBranch(in: project.path)
        do {
            async let branchList = GitService.listLocalBranches(in: project.path)
            async let worktreeList = GitService.listWorktrees(in: project.path)
            branches = try await branchList
            worktrees = try await worktreeList
        } catch {
            errorMessage = error.localizedDescription
            branches = []
            worktrees = []
        }
    }
}
