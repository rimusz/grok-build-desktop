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
        .help(attachment.path)
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
        case .idle: return "Voice input"
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
