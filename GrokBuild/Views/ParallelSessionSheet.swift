import SwiftUI

/// Draft used to create a named parallel session (teammate) from the dashboard.
struct ParallelSessionSpec: Equatable, Sendable {
    var name: String
    /// Empty string follows the global default agent; any other value is a per-tab override.
    var agent: String
    var useWorktree: Bool
    var worktreeBranch: String
    var worktreePath: String
}

/// Draft used to attach a grok `/loop` schedule to a new named session.
struct AutomationSpec: Equatable, Sendable {
    var session: ParallelSessionSpec
    var interval: String
    var prompt: String
}

enum ParallelSessionCopy {
    static let windowTitle = "New Parallel Session"
    static let summary = "Start another named tab in this project so two sessions can work at the same time. Give it a role if you want a specialist; leave Default for a normal session. Ordinary New Session stays one-click."
    static let nameCaption = "Shown in the sidebar and on Sessions Dashboard."
    static let roleCaption = "Which agent this tab runs as. Default follows Settings."
    static let workspaceCaption = "Local uses this project folder. A git worktree is a separate checkout so this session can edit files without touching the main working tree."
    static let create = "Create Session"
}

enum AutomationCopy {
    static let windowTitle = "New Automation"
    static let summary = "Create a named session that repeats a prompt on a schedule using grok /loop. Use this for recurring checks, not for a one-off chat."
    static let limitation = "The schedule runs only while GrokBuild is open and this session’s grok process is alive. It does not continue after Quit."
    static let intervalCaption = "How often to run, for example 30m or 1h."
    static let promptCaption = "What grok should do each time the schedule fires."
    static let create = "Create Automation"
}

struct ParallelSessionSheet: View {
    let project: Workspace
    var isGitRepository: Bool
    var onCreate: (ParallelSessionSpec) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var agent = ""
    @State private var useWorktree = false
    @State private var worktreeBranch = ""
    @State private var worktreePath = ""
    @State private var lastAutoBranch = ""
    @State private var lastAutoPath = ""
    @State private var discoveredNames: [String] = []
    @State private var customRoleNames: [String] = []

    private var canCreate: Bool {
        guard ParallelSessionNaming.isValidName(name) else { return false }
        if useWorktree {
            return isGitRepository && ParallelSessionNaming.isValidWorktree(
                branch: worktreeBranch,
                path: worktreePath
            )
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            NamedSessionSheetHeader(
                title: ParallelSessionCopy.windowTitle,
                projectPath: project.path.path,
                systemImage: "plus.rectangle.on.rectangle",
                tint: .teal,
                onClose: { dismiss() }
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(ParallelSessionCopy.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    NamedSessionFields(
                        name: $name,
                        agent: $agent,
                        useWorktree: $useWorktree,
                        worktreeBranch: $worktreeBranch,
                        worktreePath: $worktreePath,
                        namePlaceholder: "Reviewer",
                        nameAccessibility: "Session name",
                        nameCaption: ParallelSessionCopy.nameCaption,
                        roleCaption: ParallelSessionCopy.roleCaption,
                        workspaceCaption: ParallelSessionCopy.workspaceCaption,
                        isGitRepository: isGitRepository,
                        discoveredNames: discoveredNames,
                        customRoleNames: customRoleNames
                    )
                }
                .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button(ParallelSessionCopy.create) {
                    onCreate(currentSpec)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(ParallelSessionCopy.create)
            }
            .padding()
        }
        .frame(width: 520, height: 520)
        .task { await loadRoles() }
        .onAppear { seedWorktreeDefaults() }
        .onChange(of: name) { _, _ in syncAutoWorktreeFields() }
    }

    private var currentSpec: ParallelSessionSpec {
        ParallelSessionSpec(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            agent: agent,
            useWorktree: useWorktree && isGitRepository,
            worktreeBranch: worktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines),
            worktreePath: worktreePath.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func seedWorktreeDefaults() {
        let branch = ParallelSessionNaming.defaultBranch(fromName: name)
        let path = ParallelSessionNaming.defaultWorktreePath(projectPath: project.path, name: name)
        worktreeBranch = branch
        worktreePath = path
        lastAutoBranch = branch
        lastAutoPath = path
    }

    private func syncAutoWorktreeFields() {
        let branch = ParallelSessionNaming.defaultBranch(fromName: name)
        let path = ParallelSessionNaming.defaultWorktreePath(projectPath: project.path, name: name)
        if worktreeBranch == lastAutoBranch { worktreeBranch = branch }
        if worktreePath == lastAutoPath { worktreePath = path }
        lastAutoBranch = branch
        lastAutoPath = path
    }

    private func loadRoles() async {
        let lists = await NamedSessionRoleLists.load(cwd: project.path)
        discoveredNames = lists.discovered
        customRoleNames = lists.custom
    }
}

struct AutomationSheet: View {
    let project: Workspace
    var isGitRepository: Bool
    var onCreate: (AutomationSpec) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var agent = ""
    @State private var interval = "1h"
    @State private var prompt = ""
    @State private var useWorktree = false
    @State private var worktreeBranch = ""
    @State private var worktreePath = ""
    @State private var lastAutoBranch = ""
    @State private var lastAutoPath = ""
    @State private var discoveredNames: [String] = []
    @State private var customRoleNames: [String] = []

    private var canCreate: Bool {
        guard ParallelSessionNaming.isValidName(name) else { return false }
        guard ParallelSessionNaming.isValidAutomation(interval: interval, prompt: prompt) else { return false }
        if useWorktree {
            return isGitRepository && ParallelSessionNaming.isValidWorktree(
                branch: worktreeBranch,
                path: worktreePath
            )
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            NamedSessionSheetHeader(
                title: AutomationCopy.windowTitle,
                projectPath: project.path.path,
                systemImage: "clock.arrow.2.circlepath",
                tint: .teal,
                onClose: { dismiss() }
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(AutomationCopy.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    limitationNote
                    NamedSessionFields(
                        name: $name,
                        agent: $agent,
                        useWorktree: $useWorktree,
                        worktreeBranch: $worktreeBranch,
                        worktreePath: $worktreePath,
                        namePlaceholder: "Nightly triage",
                        nameAccessibility: "Automation name",
                        nameCaption: ParallelSessionCopy.nameCaption,
                        roleCaption: ParallelSessionCopy.roleCaption,
                        workspaceCaption: ParallelSessionCopy.workspaceCaption,
                        isGitRepository: isGitRepository,
                        discoveredNames: discoveredNames,
                        customRoleNames: customRoleNames
                    )
                    LabeledSheetField(title: "Interval", caption: AutomationCopy.intervalCaption) {
                        TextField("1h", text: $interval)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Loop interval")
                    }
                    LabeledSheetField(title: "Prompt", caption: AutomationCopy.promptCaption) {
                        TextField("Check for failing tests and summarize what broke", text: $prompt, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                            .accessibilityLabel("Loop prompt")
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button(AutomationCopy.create) {
                    onCreate(AutomationSpec(
                        session: ParallelSessionSpec(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            agent: agent,
                            useWorktree: useWorktree && isGitRepository,
                            worktreeBranch: worktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines),
                            worktreePath: worktreePath.trimmingCharacters(in: .whitespacesAndNewlines)
                        ),
                        interval: interval.trimmingCharacters(in: .whitespacesAndNewlines),
                        prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(AutomationCopy.create)
            }
            .padding()
        }
        .frame(width: 520, height: 640)
        .task { await loadRoles() }
        .onAppear { seedWorktreeDefaults() }
        .onChange(of: name) { _, _ in syncAutoWorktreeFields() }
    }

    private var limitationNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(AutomationCopy.limitation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func seedWorktreeDefaults() {
        let branch = ParallelSessionNaming.defaultBranch(fromName: name)
        let path = ParallelSessionNaming.defaultWorktreePath(projectPath: project.path, name: name)
        worktreeBranch = branch
        worktreePath = path
        lastAutoBranch = branch
        lastAutoPath = path
        if isGitRepository {
            useWorktree = true
        }
    }

    private func syncAutoWorktreeFields() {
        let branch = ParallelSessionNaming.defaultBranch(fromName: name)
        let path = ParallelSessionNaming.defaultWorktreePath(projectPath: project.path, name: name)
        if worktreeBranch == lastAutoBranch { worktreeBranch = branch }
        if worktreePath == lastAutoPath { worktreePath = path }
        lastAutoBranch = branch
        lastAutoPath = path
    }

    private func loadRoles() async {
        let lists = await NamedSessionRoleLists.load(cwd: project.path)
        discoveredNames = lists.discovered
        customRoleNames = lists.custom
    }
}

private enum NamedSessionRoleLists {
    static func load(cwd: URL) async -> (discovered: [String], custom: [String]) {
        let agents = (try? await GrokCLIService().listAgents(cwd: cwd)) ?? []
        let builtIn = Set(GrokAgentProfiles.builtInOptions.map(\.id))
        let discovered = agents.map(\.name).filter { !builtIn.contains($0) }
        let discoveredSet = Set(discovered)
        let custom = SubagentRoleStore.load().map(\.name).filter { !builtIn.contains($0) && !discoveredSet.contains($0) }
        return (discovered, custom)
    }
}

private struct NamedSessionSheetHeader: View {
    let title: String
    let projectPath: String
    let systemImage: String
    let tint: Color
    let onClose: () -> Void
    @AppStorage(GrokSettingsKeys.privacyMode) private var privacyMode = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            WindowTrafficLights(onClose: onClose)
                .keyboardShortcut(.cancelAction)
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(PrivacyMode.redactPath(projectPath, enabled: privacyMode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}

private struct NamedSessionFields: View {
    @Binding var name: String
    @Binding var agent: String
    @Binding var useWorktree: Bool
    @Binding var worktreeBranch: String
    @Binding var worktreePath: String
    var namePlaceholder: String
    var nameAccessibility: String
    var nameCaption: String
    var roleCaption: String
    var workspaceCaption: String
    var isGitRepository: Bool
    var discoveredNames: [String]
    var customRoleNames: [String]

    var body: some View {
        LabeledSheetField(title: "Name", caption: nameCaption) {
            TextField(namePlaceholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(nameAccessibility)
        }
        LabeledSheetField(title: "Role", caption: roleCaption) {
            Picker("Role", selection: $agent) {
                ForEach(GrokAgentProfiles.builtInOptions) { option in
                    Text(option.title).tag(option.id)
                }
                if !discoveredNames.isEmpty {
                    Section("Discovered") {
                        ForEach(discoveredNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                if !customRoleNames.isEmpty {
                    Section("Run as custom role") {
                        ForEach(customRoleNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Session role")
        }
        LabeledSheetField(title: "Workspace", caption: workspaceCaption) {
            Picker("Workspace", selection: $useWorktree) {
                Text("Local project").tag(false)
                Text("Git worktree").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(!isGitRepository)
            .accessibilityLabel("Workspace mode")
            .help(isGitRepository
                  ? ParallelSessionCopy.workspaceCaption
                  : "Worktrees need a git repository.")
            if useWorktree && isGitRepository {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("New branch name", text: $worktreeBranch)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Worktree branch")
                    TextField("Worktree path", text: $worktreePath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Worktree path")
                }
                .padding(.top, 4)
            }
        }
    }
}

private struct LabeledSheetField<Content: View>: View {
    let title: String
    let caption: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
