import SwiftUI
import WebKit

// MARK: - File chips

struct FileChipBar: View {
    let attachments: [FileAttachment]
    var onToggleHidden: (UUID) -> Void
    var onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { attachment in
                    FileChipView(
                        attachment: attachment,
                        onToggleHidden: { onToggleHidden(attachment.id) },
                        onRemove: { onRemove(attachment.id) }
                    )
                }
            }
        }
    }
}

private struct FileChipView: View {
    let attachment: FileAttachment
    var onToggleHidden: () -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onToggleHidden) {
                Image(systemName: attachment.isHidden ? "eye.slash" : "doc")
                    .font(.caption2)
            }
            .buttonStyle(.plain)

            Text(attachment.relativePath.split(separator: "/").last.map(String.init) ?? attachment.relativePath)
                .font(.caption)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.08), in: Capsule())
        .help(attachment.isHidden ? "\(attachment.path) (excluded from prompt)" : attachment.path)
    }
}

// MARK: - Workflow chips

struct WorkflowChipBar: View {
    let commands: [SlashCommand]
    var isDisabled: Bool = false
    var onSelect: (SlashCommand) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(commands) { command in
                    WorkflowChip(command: command, isDisabled: isDisabled) {
                        onSelect(command)
                    }
                }
            }
        }
    }
}

private struct WorkflowChip: View {
    let command: SlashCommand
    var isDisabled: Bool
    var onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            Text(displayName)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Color.primary.opacity(isHovered && !isDisabled ? 0.10 : 0.06),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .onHover { isHovered = $0 }
        .help(command.description.isEmpty ? SkillSlashCommands.slashText(for: command) : command.description)
    }

    private var displayName: String {
        command.name.replacingOccurrences(of: "-", with: " ")
    }
}

// MARK: - Goal banner

struct GoalBanner: View {
    let state: SessionGoalState
    @Bindable var store: ChatStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.isPaused ? "pause.circle" : "target")
                .foregroundStyle(state.isPaused ? Color.secondary : Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Goal")
                        .font(.caption.weight(.semibold))
                    Text(state.statusLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(state.isPaused ? Color.secondary : Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    if let budgetLabel = state.budgetLabel {
                        Text(budgetLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(state.objective)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button("Status") {
                    Task { _ = await store.refreshGoalStatus() }
                }
                .controlSize(.small)
                .disabled(store.isStreaming)

                if state.isPaused {
                    Button("Resume") {
                        Task { _ = await store.resumeGoal() }
                    }
                    .controlSize(.small)
                    .disabled(store.isStreaming)
                } else {
                    Button("Pause") {
                        Task { _ = await store.pauseGoal() }
                    }
                    .controlSize(.small)
                    .disabled(store.isStreaming)
                }

                Button("Clear") {
                    Task { _ = await store.clearGoal() }
                }
                .controlSize(.small)
                .disabled(store.isStreaming)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }
}

struct SetGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var objective = ""
    @State private var budgetText = ""
    let onSubmit: (String, Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set Goal")
                .font(.headline)
            TextField("Objective", text: $objective)
                .textFieldStyle(.roundedBorder)
            TextField("Budget (optional)", text: $budgetText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Set Goal") {
                    let budget = Int(budgetText.trimmingCharacters(in: .whitespacesAndNewlines))
                    onSubmit(objective, budget)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

struct BtwAsideBanner: View {
    let text: String
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Aside (/btw)", systemImage: "text.bubble")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Plan card

struct PlanReviewCard: View {
    let plan: ExitPlanRequest
    var onRespond: (ExitPlanRequest.PlanVerdict, String) -> Void

    @State private var comment = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                Text("Plan ready for review")
                    .font(.subheadline.weight(.semibold))
            }

            if !plan.planText.isEmpty {
                RichMessageView(text: plan.planText)
                    .frame(maxHeight: 240)
            }

            TextField("Optional comment…", text: $comment)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button("Approve & implement") {
                    onRespond(.approved, comment)
                }
                .buttonStyle(.borderedProminent)

                Button("Reject") {
                    onRespond(.rejected, comment)
                }
                .buttonStyle(.bordered)

                Button("Cancel") {
                    onRespond(.abandoned, comment)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.blue.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Question card

struct QuestionCard: View {
    let request: QuestionRequest
    var onSubmit: ([String: String]) -> Void
    var onSkip: () -> Void

    @State private var selections: [[String]] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "questionmark.circle")
                Text("Grok is asking")
                    .font(.subheadline.weight(.semibold))
            }

            ForEach(Array(request.questions.enumerated()), id: \.element.id) { index, question in
                QuestionBlock(
                    question: question,
                    selection: selections.indices.contains(index) ? selections[index] : [],
                    onSelect: { label in
                        guard selections.indices.contains(index) else { return }
                        if question.multiSelect {
                            if let i = selections[index].firstIndex(of: label) {
                                selections[index].remove(at: i)
                            } else {
                                selections[index].append(label)
                            }
                        } else {
                            selections[index] = [label]
                            if request.questions.count == 1 {
                                submit()
                            }
                        }
                    }
                )
            }

            if request.questions.count > 1 || request.questions.first?.multiSelect == true {
                HStack {
                    Button("Submit") { submit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!allAnswered)

                    Button("Skip", action: onSkip)
                        .buttonStyle(.bordered)
                }
            } else if request.questions.first?.options.isEmpty == true {
                Button("Skip", action: onSkip)
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.green.opacity(0.35), lineWidth: 1)
        )
        .onAppear {
            selections = request.questions.map { _ in [] }
        }
    }

    private var allAnswered: Bool {
        guard selections.count == request.questions.count else { return false }
        return zip(request.questions, selections).allSatisfy { question, chosen in
            !question.text.isEmpty && (!question.options.isEmpty ? !chosen.isEmpty : true)
        }
    }

    private func submit() {
        var answers: [String: String] = [:]
        for (question, chosen) in zip(request.questions, selections) {
            answers[question.text] = chosen.joined(separator: ", ")
        }
        onSubmit(answers)
    }
}

private struct QuestionBlock: View {
    let question: QuestionItem
    let selection: [String]
    var onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question.text)
                .font(.callout.weight(.medium))

            if question.options.isEmpty {
                Text("No options provided — use Skip.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(question.options) { option in
                        Button {
                            onSelect(option.label)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: selection.contains(option.label) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection.contains(option.label) ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .foregroundStyle(.primary)
                                    if let description = option.description, !description.isEmpty {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(
                                selection.contains(option.label)
                                    ? Color.accentColor.opacity(0.1)
                                    : Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Mic button

struct MicButton: View {
    @Bindable var voice: VoiceInputService
    @Binding var input: String
    @State private var baseText = ""

    var body: some View {
        Button(action: toggle) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(accessibilityLabel)
        .disabled(isDisabled)
    }

    private var iconName: String {
        switch voice.state {
        case .listening: return "waveform.circle.fill"
        case .transcribing: return "ellipsis.circle"
        case .unavailable: return "mic.slash"
        case .idle: return "mic"
        }
    }

    private var iconColor: Color {
        switch voice.state {
        case .listening: return .red
        case .transcribing: return .orange
        case .unavailable: return .secondary
        case .idle: return .secondary
        }
    }

    private var helpText: String {
        switch voice.state {
        case .listening: return "Listening… click to stop"
        case .transcribing: return "Transcribing…"
        case .unavailable(let msg): return msg
        case .idle: return "Voice control"
        }
    }

    private var accessibilityLabel: String {
        switch voice.state {
        case .listening: return "Stop voice control"
        case .transcribing: return "Transcribing voice control"
        case .unavailable: return "Voice control unavailable"
        case .idle: return "Voice control"
        }
    }

    private var isDisabled: Bool {
        if case .unavailable = voice.state { return true }
        return false
    }

    private func toggle() {
        switch voice.state {
        case .listening, .transcribing:
            voice.stop()
        case .idle:
            baseText = input
            voice.start(
                onPartial: { partial in
                    input = baseText.isEmpty ? partial : "\(baseText) \(partial)"
                },
                onFinal: { final in
                    input = baseText.isEmpty ? final : "\(baseText) \(final)"
                }
            )
        case .unavailable:
            break
        }
    }
}
