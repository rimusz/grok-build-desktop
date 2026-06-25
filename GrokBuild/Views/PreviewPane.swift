import SwiftUI

struct PreviewPane: View {
    let message: Message?
    let diffs: [ChatStore.DetectedDiff]
    let workspace: Workspace?
    var onClose: () -> Void = {}
    let onApply: (Message) -> Void
    let onApplySingle: ((ChatStore.DetectedDiff) -> Void)?

    @State private var selectedID: UUID?
    @State private var branchName = "No branch"
    @State private var baseBranch = "main"
    @State private var showCommitPopover = false
    @State private var showPRPopover = false
    @State private var gitTitle = ""
    @State private var gitDescription = ""
    @State private var commitAndPushLocalChanges = true
    @State private var gitOperationStatus: String?
    @State private var isRunningGitOperation = false
    @State private var canCommitOrPush = false
    @State private var canCreatePullRequest = false
    @State private var areChangedFilesExpanded = false
    @State private var changedFilesListHeight: CGFloat = 180
    @State private var usesDefaultChangedFilesHeight = true
    @GestureState private var changedFilesResizeDelta: CGFloat = 0

    private var selected: ChatStore.DetectedDiff? {
        if let id = selectedID,
           let match = diffs.first(where: { $0.id == id }) {
            return match
        }
        return nil
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
        .task(id: workspace?.id) {
            restoreChangedFilesState()
            await refreshGitContext()
        }
        .onChange(of: areChangedFilesExpanded) { _, _ in
            saveChangedFilesState()
        }
        .onChange(of: changedFilesListHeight) { _, _ in
            saveChangedFilesState()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                Image(systemName: "sidebar.right")
                    .font(.headline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close Preview")

            Text("Preview")
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
        GeometryReader { proxy in
            VStack(spacing: 0) {
                environmentPanel(defaultListHeight: defaultChangedFilesListHeight(for: proxy.size.height))

                ScrollView {
                    if areChangedFilesExpanded, let d = selected {
                        DiffView(diffText: d.raw, filePath: d.filePath)
                            .padding(12)
                    }
                }

                Divider()

                actions(for: msg)
            }
        }
    }

    private func environmentPanel(defaultListHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            environmentStaticRow(title: branchName, systemImage: "point.topleft.down.curvedto.point.bottomright.up", showsChevron: false)

            Button {
                showCommitPopover = true
            } label: {
                environmentRowContent(
                    title: "Commit or push",
                    systemImage: "smallcircle.filled.circle",
                    isEnabled: canCommitOrPush
                )
            }
            .buttonStyle(.plain)
            .disabled(!canCommitOrPush || isRunningGitOperation)
            .popover(isPresented: $showCommitPopover, arrowEdge: .bottom) {
                gitActionPopover(isPullRequest: false)
            }

            Button {
                showPRPopover = true
            } label: {
                environmentRowContent(
                    title: "Create pull request",
                    systemImage: "arrow.triangle.pull",
                    isEnabled: canCreatePullRequest
                )
            }
            .buttonStyle(.plain)
            .disabled(!canCreatePullRequest || isRunningGitOperation)
            .popover(isPresented: $showPRPopover, arrowEdge: .bottom) {
                gitActionPopover(isPullRequest: true)
            }

            changesRow

            if areChangedFilesExpanded {
                changedFilesRows(defaultHeight: defaultListHeight)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .task(id: diffs.count) {
            await refreshGitContext()
        }
    }

    private var changesRow: some View {
        Button {
            areChangedFilesExpanded.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plusminus.square")
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text("Changed Files")
                    .font(.callout.weight(.medium))
                Spacer()
                Text("\(diffs.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("+\(totalLineStats.added)")
                    .foregroundStyle(.green)
                    .font(.callout.monospacedDigit())
                Text("-\(totalLineStats.removed)")
                    .foregroundStyle(.red)
                    .font(.callout.monospacedDigit())
                Image(systemName: areChangedFilesExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func environmentStaticRow(title: String, systemImage: String, showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func environmentRowContent(title: String, systemImage: String, isEnabled: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 18)
            Text(title)
                .font(.callout.weight(.medium))
            Spacer()
        }
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.55))
        .contentShape(Rectangle())
    }

    private var totalLineStats: (added: Int, removed: Int) {
        diffs.reduce(into: (added: 0, removed: 0)) { result, diff in
            let stats = lineStats(for: diff.raw)
            result.added += stats.added
            result.removed += stats.removed
        }
    }

    private var effectiveChangedFilesListHeight: CGFloat {
        min(420, max(72, changedFilesListHeight + changedFilesResizeDelta))
    }

    private func defaultChangedFilesListHeight(for availableHeight: CGFloat) -> CGFloat {
        min(420, max(120, availableHeight * 0.5))
    }

    private var changedFilesExpandedKey: String? {
        workspace.map { "grokbuild.preview.changedFiles.expanded.\($0.id.uuidString)" }
    }

    private var changedFilesHeightKey: String? {
        workspace.map { "grokbuild.preview.changedFiles.height.\($0.id.uuidString)" }
    }

    private func restoreChangedFilesState() {
        let defaults = UserDefaults.standard
        if let expandedKey = changedFilesExpandedKey,
           defaults.object(forKey: expandedKey) != nil {
            areChangedFilesExpanded = defaults.bool(forKey: expandedKey)
        }
        if let heightKey = changedFilesHeightKey,
           defaults.object(forKey: heightKey) != nil {
            changedFilesListHeight = min(420, max(72, defaults.double(forKey: heightKey)))
            usesDefaultChangedFilesHeight = false
        } else {
            usesDefaultChangedFilesHeight = true
        }
    }

    private func saveChangedFilesState() {
        let defaults = UserDefaults.standard
        if let expandedKey = changedFilesExpandedKey {
            defaults.set(areChangedFilesExpanded, forKey: expandedKey)
        }
        if let heightKey = changedFilesHeightKey, !usesDefaultChangedFilesHeight {
            defaults.set(changedFilesListHeight, forKey: heightKey)
        }
    }

    private var defaultGitTitle: String {
        selected?.filePath.map { "Update \($0)" } ?? "Update project changes"
    }

    private func gitActionPopover(isPullRequest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Label("\(branchName) -> \(baseBranch)", systemImage: "arrow.triangle.branch")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                TextField("Title", text: $gitTitle)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))

                TextField("Description (leave empty to generate)", text: $gitDescription, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(3, reservesSpace: true)

                Spacer(minLength: 60)

                Toggle("Commit and push local changes", isOn: $commitAndPushLocalChanges)
                    .toggleStyle(.checkbox)
                    .font(.body.weight(.medium))

                if let gitOperationStatus {
                    Text(gitOperationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .frame(height: 280, alignment: .topLeading)

            Divider()

            VStack(spacing: 2) {
                if isPullRequest {
                    popoverActionRow(
                        title: "Create draft PR",
                        systemImage: "arrow.triangle.pull",
                        isPrimary: true,
                        showsShortcut: true
                    ) {
                        Task { await createPullRequest(draft: true) }
                    }
                    .keyboardShortcut(.return, modifiers: [.command])

                    popoverActionRow(
                        title: "Create PR",
                        systemImage: "arrow.triangle.pull",
                        isPrimary: false
                    ) {
                        Task { await createPullRequest(draft: false) }
                    }

                    popoverActionRow(
                        title: "Open PR in browser",
                        systemImage: "arrow.up.right",
                        isPrimary: false
                    ) {
                        Task { await openPullRequestInBrowser() }
                    }
                } else {
                    popoverActionRow(
                        title: "Commit and push",
                        systemImage: "arrow.up.circle",
                        isPrimary: true,
                        showsShortcut: true
                    ) {
                        Task { await commitAndPush() }
                    }
                    .keyboardShortcut(.return, modifiers: [.command])

                    popoverActionRow(
                        title: "Push only",
                        systemImage: "arrow.up",
                        isPrimary: false
                    ) {
                        Task { await pushOnly() }
                    }
                }
            }
            .padding(8)
        }
        .disabled(isRunningGitOperation)
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func popoverActionRow(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        showsShortcut: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .frame(width: 18)
                Text(title)
                    .font(.body.weight(.medium))
                Spacer()
                if showsShortcut {
                    Text("⌘↩")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.primary.opacity(0.12))
                        )
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(isPrimary ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isPrimary ? Color.primary.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func changedFilesRows(defaultHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(diffs.enumerated()), id: \.element.id) { index, diff in
                        changedFileRow(diff, index: index)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: usesDefaultChangedFilesHeight ? defaultHeight : effectiveChangedFilesListHeight)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .updating($changedFilesResizeDelta) { value, state, _ in
                            state = value.translation.height
                        }
                        .onEnded { value in
                            if usesDefaultChangedFilesHeight {
                                changedFilesListHeight = defaultHeight
                                usesDefaultChangedFilesHeight = false
                            }
                            changedFilesListHeight = min(420, max(72, changedFilesListHeight + value.translation.height))
                            saveChangedFilesState()
                        }
                )
                .help("Drag to resize changed files list")
        }
        .padding(.leading, 28)
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

    @MainActor
    private func refreshGitContext() async {
        guard let workspace else { return }
        branchName = GitService.currentBranch(in: workspace.path) ?? "No branch"
        baseBranch = await GitService.defaultBaseBranch(in: workspace.path)
        async let hasLocalChanges = GitService.hasLocalChanges(in: workspace.path)
        async let hasUnpushedCommits = GitService.hasUnpushedCommits(in: workspace.path, baseBranch: baseBranch)
        async let hasPRChanges = GitService.hasPullRequestSourceChanges(baseBranch: baseBranch, in: workspace.path)
        let localChanges = await hasLocalChanges
        let unpushedCommits = await hasUnpushedCommits
        let pullRequestChanges = await hasPRChanges
        canCommitOrPush = localChanges || unpushedCommits
        canCreatePullRequest = branchName != "No branch"
            && branchName != baseBranch
            && pullRequestChanges
        if gitTitle.isEmpty {
            gitTitle = defaultGitTitle
        }
    }

    @MainActor
    private func commitAndPushIfRequested() async throws {
        guard let workspace else { return }
        if commitAndPushLocalChanges, await GitService.hasLocalChanges(in: workspace.path) {
            let title = gitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw NSError(
                    domain: "PreviewPane",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Enter a title to use as the commit message."]
                )
            }
            _ = try await GitService.commitAll(message: title, in: workspace.path)
        }
        _ = try await GitService.pushCurrentBranch(in: workspace.path)
    }

    @MainActor
    private func commitAndPush() async {
        await runGitOperation {
            try await commitAndPushIfRequested()
            gitOperationStatus = "Committed and pushed \(branchName)."
            showCommitPopover = false
            await refreshGitContext()
        }
    }

    @MainActor
    private func pushOnly() async {
        await runGitOperation {
            guard let workspace else { return }
            _ = try await GitService.pushCurrentBranch(in: workspace.path)
            gitOperationStatus = "Pushed \(branchName)."
            showCommitPopover = false
            await refreshGitContext()
        }
    }

    @MainActor
    private func createPullRequest(draft: Bool) async {
        await runGitOperation {
            guard let workspace else { return }
            try await commitAndPushIfRequested()
            let title = gitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = gitDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw NSError(
                    domain: "PreviewPane",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Enter a pull request title."]
                )
            }
            let output = try await GitService.createPullRequest(
                base: baseBranch,
                head: branchName,
                title: title,
                body: body,
                draft: draft,
                in: workspace.path
            )
            gitOperationStatus = output.trimmingCharacters(in: .whitespacesAndNewlines)
            showPRPopover = false
            await refreshGitContext()
        }
    }

    @MainActor
    private func openPullRequestInBrowser() async {
        await runGitOperation {
            guard let workspace else { return }
            _ = try await GitService.openPullRequestInBrowser(in: workspace.path)
            gitOperationStatus = "Opened pull request in browser."
            showPRPopover = false
        }
    }

    @MainActor
    private func runGitOperation(_ operation: @escaping () async throws -> Void) async {
        isRunningGitOperation = true
        gitOperationStatus = "Working..."
        defer { isRunningGitOperation = false }
        do {
            try await operation()
        } catch {
            gitOperationStatus = error.localizedDescription
        }
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
