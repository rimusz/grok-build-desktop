import SwiftUI

enum AgentEditorCopy {
    static let createTitle = "New Agent"
    static let editTitle = "Edit Agent"
    static let summary = "An Agent is a durable identity: name, instructions, and look. Saving also updates the linked grok role prompt so sessions started from Agents use these instructions."
    static let nameCaption = "Shown in the sidebar Agents section."
    static let missionCaption = "What this Agent should do. Saved into the linked role prompt."
    static let appearanceCaption = "Glyph and accent used in the sidebar."
    static let roleCaption = "Optional custom role this session runs as. Leave empty to use a slug of the agent name."
    static let permissionCaption = "Preference only in this release. Session permissions still follow Settings until launch mapping lands."
    static let save = "Save Agent"
}

struct AgentEditorSheet: View {
    let agent: SpecialistAgent?
    let existingNames: [String]
    let customRoleNames: [String]
    var onSave: (SpecialistAgent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var mission: String
    @State private var glyph: String
    @State private var color: String
    @State private var roleName: String
    @State private var permissionProfile: SpecialistAgentPermissionProfile

    init(
        agent: SpecialistAgent?,
        existingNames: [String],
        customRoleNames: [String],
        onSave: @escaping (SpecialistAgent) -> Void
    ) {
        self.agent = agent
        self.existingNames = existingNames
        self.customRoleNames = customRoleNames
        self.onSave = onSave
        _name = State(initialValue: agent?.name ?? "")
        _mission = State(initialValue: agent?.mission ?? "")
        _glyph = State(initialValue: agent?.glyph ?? "person.fill")
        _color = State(initialValue: SpecialistAgent.canonicalizeColor(agent?.color ?? "") ?? "#5E5CE6")
        _roleName = State(initialValue: agent?.roleName ?? "")
        _permissionProfile = State(initialValue: agent?.permissionProfile ?? .inherit)
    }

    private var draft: SpecialistAgent {
        SpecialistAgent(
            id: agent?.id ?? UUID(),
            name: name,
            mission: mission,
            glyph: glyph,
            color: color,
            roleName: roleName,
            permissionProfile: permissionProfile,
            browserEnabled: agent?.browserEnabled ?? false,
            computerUseEnabled: agent?.computerUseEnabled ?? false,
            preferredSkills: agent?.preferredSkills ?? [],
            createdAt: agent?.createdAt ?? Date(),
            updatedAt: agent?.updatedAt ?? Date(),
            lastSessionID: agent?.lastSessionID,
            isPinned: agent?.isPinned ?? false
        )
    }

    private var validationError: String? {
        if let error = draft.validationError { return error }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare(agent?.name ?? "") != .orderedSame,
           existingNames.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return "An agent named \"\(trimmed)\" already exists."
        }
        return nil
    }

    private var canSave: Bool { validationError == nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                WindowTrafficLights(onClose: { dismiss() })
                    .keyboardShortcut(.cancelAction)
                Image(systemName: glyph)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SpecialistAgentRoster.color(from: color))
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(SpecialistAgentRoster.color(from: color).opacity(0.14))
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent == nil ? AgentEditorCopy.createTitle : AgentEditorCopy.editTitle)
                        .font(.title2.weight(.semibold))
                    Text("Agent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(AgentEditorCopy.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    editorField(title: "Name", caption: AgentEditorCopy.nameCaption) {
                        TextField("Chief", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Agent name")
                    }
                    editorField(title: "Instructions", caption: AgentEditorCopy.missionCaption) {
                        TextField("Route work, keep scope, synthesize final answer", text: $mission, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                            .accessibilityLabel("Agent instructions")
                    }
                    editorField(title: "Appearance", caption: AgentEditorCopy.appearanceCaption) {
                        appearancePickers
                    }
                    editorField(title: "Linked role", caption: AgentEditorCopy.roleCaption) {
                        Picker("Linked role", selection: $roleName) {
                            Text("Automatic from name").tag("")
                            if !customRoleNames.isEmpty {
                                Section("Custom roles") {
                                    ForEach(customRoleNames, id: \.self) { role in
                                        Text(role).tag(role)
                                    }
                                }
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Linked role")
                    }
                    editorField(title: "Permission preference", caption: AgentEditorCopy.permissionCaption) {
                        Picker("Permission preference", selection: $permissionProfile) {
                            Text("Inherit").tag(SpecialistAgentPermissionProfile.inherit)
                            Text("Read only").tag(SpecialistAgentPermissionProfile.readOnly)
                            Text("Workspace write").tag(SpecialistAgentPermissionProfile.workspaceWrite)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Permission preference")
                    }

                    if let validationError {
                        Text(validationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button(AgentEditorCopy.save) {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(AgentEditorCopy.save)
            }
            .padding()
        }
        .frame(width: 520, height: 640)
    }

    private var appearancePickers: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(SpecialistAgentRoster.glyphChoices, id: \.self) { choice in
                    Button {
                        glyph = choice
                    } label: {
                        Image(systemName: choice)
                            .font(.body)
                            .frame(width: 28, height: 28)
                            .foregroundStyle(glyph == choice ? .white : .primary)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(glyph == choice ? SpecialistAgentRoster.color(from: color) : Color.secondary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice)
                    .accessibilityAddTraits(glyph == choice ? .isSelected : [])
                }
            }
            HStack(spacing: 8) {
                ForEach(SpecialistAgentRoster.colorChoices, id: \.self) { choice in
                    Button {
                        color = choice
                    } label: {
                        Circle()
                            .fill(SpecialistAgentRoster.color(from: choice))
                            .frame(width: 18, height: 18)
                            .overlay {
                                if color == choice {
                                    Circle().strokeBorder(Color.primary, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice)
                    .accessibilityAddTraits(color == choice ? .isSelected : [])
                }
            }
        }
    }

    private func editorField<Content: View>(
        title: String,
        caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
