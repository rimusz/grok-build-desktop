import SwiftUI

enum SessionsDashboardCopy {
    static let windowTitle = "Sessions Dashboard"
    static let toolbarHelp = "Sessions Dashboard"
    static let toolbarHelpDetail = "Sessions Dashboard — roster, review, automations"
}

/// Snapshot of a live session for the dashboard (owned by `ContentView`).
struct SessionDashboardEntry: Identifiable, Hashable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case needsYou
        case failed
        case working
        case needsReview
        case scheduled
        case idle

        /// Same order as grouping priority so Failed is not buried under Idle.
        static let sectionOrder: [Group] = [
            .needsYou, .failed, .working, .needsReview, .scheduled, .idle,
        ]

        var title: String {
            switch self {
            case .needsYou: return "Needs you"
            case .needsReview: return "Needs review"
            case .working: return "Working"
            case .scheduled: return "Scheduled"
            case .idle: return "Idle"
            case .failed: return "Failed"
            }
        }

        var systemImage: String {
            switch self {
            case .needsYou: return "hand.raised.fill"
            case .needsReview: return "doc.text.magnifyingglass"
            case .working: return "ellipsis.circle.fill"
            case .scheduled: return "clock.arrow.2.circlepath"
            case .idle: return "moon.zzz.fill"
            case .failed: return "exclamationmark.triangle.fill"
            }
        }
    }

    let id: UUID
    let title: String
    let workspaceName: String
    let roleName: String
    var specialistName: String = ""
    var specialistGlyph: String = ""
    let group: Group
    let modelName: String
    let pendingCount: Int
    let scheduledCount: Int
    let isWorktree: Bool
    let branch: String?
    let dirtyCount: Int
}

struct SessionDashboardPanel: View {
    let entries: [SessionDashboardEntry]
    var projectName: String?
    var projectPath: String?
    var onSelect: (UUID) -> Void = { _ in }
    var onOpenPreview: (UUID) -> Void = { _ in }
    var onNewParallelSession: () -> Void = {}
    var onNewAutomation: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @AppStorage(GrokSettingsKeys.privacyMode) private var privacyMode = false
    @State private var hoveredID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(emptyDescription)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(SessionDashboardEntry.Group.sectionOrder, id: \.self) { group in
                                let groupEntries = entries.filter { $0.group == group }
                                if !groupEntries.isEmpty {
                                    section(group, entries: groupEntries)
                                }
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            footerNote
                .padding(20)
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            WindowTrafficLights(onClose: { dismiss() })
                .keyboardShortcut(.cancelAction)

            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.teal)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.teal.opacity(0.14)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(SessionsDashboardCopy.windowTitle)
                    .font(.title2.weight(.semibold))
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            Button {
                onNewParallelSession()
            } label: {
                Label("Parallel Session", systemImage: "plus.rectangle.on.rectangle")
            }
            .controlSize(.regular)
            .disabled(projectPath == nil)
            .accessibilityLabel("New Parallel Session")

            Button {
                onNewAutomation()
            } label: {
                Label("Automation", systemImage: "clock.arrow.2.circlepath")
            }
            .controlSize(.regular)
            .disabled(projectPath == nil)
            .accessibilityLabel("New Automation")
        }
        .padding()
    }

    private var headerSubtitle: String {
        if let projectPath, !projectPath.isEmpty {
            return PrivacyMode.redactPath(projectPath, enabled: privacyMode)
        }
        return "Select a project to see its live sessions."
    }

    private var emptyDescription: String {
        projectPath == nil
            ? "Select a project to see its live sessions."
            : "No live sessions in this project."
    }

    private func section(_ group: SessionDashboardEntry.Group, entries: [SessionDashboardEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: group.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color(for: group))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(color(for: group).opacity(0.16)))
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(entries.count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color(for: group))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(color(for: group).opacity(0.14)))
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(group.title), \(entries.count)")

            VStack(spacing: 8) {
                ForEach(entries) { entry in
                    card(entry)
                }
            }
        }
    }

    private func card(_ entry: SessionDashboardEntry) -> some View {
        let title = DashboardTitle.display(
            PrivacyMode.redactLabel(entry.title, placeholder: "Session", enabled: privacyMode)
        )
        let project = PrivacyMode.redactLabel(entry.workspaceName, placeholder: "Project", enabled: privacyMode)
        let hovering = hoveredID == entry.id

        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: entry.group.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color(for: entry.group))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color(for: entry.group).opacity(0.14))
                )
                .accessibilityHidden(true)

            Button {
                onSelect(entry.id)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        chip(project, systemImage: "folder")
                        if !entry.specialistName.isEmpty {
                            chip(
                                entry.specialistName,
                                systemImage: entry.specialistGlyph.isEmpty ? "person" : entry.specialistGlyph
                            )
                        } else {
                            chip(DashboardTitle.compactRole(entry.roleName), systemImage: "person")
                        }
                        if entry.isWorktree {
                            chip("Worktree", systemImage: "square.on.square")
                        }
                        if let branch = entry.branch, !branch.isEmpty {
                            chip(branch, systemImage: "arrow.triangle.branch")
                        }
                    }
                    HStack(spacing: 6) {
                        chip(entry.modelName)
                        if entry.pendingCount > 0 {
                            chip("\(entry.pendingCount) pending", tint: .orange)
                        }
                        if entry.scheduledCount > 0 {
                            chip("\(entry.scheduledCount) scheduled", tint: .teal)
                        }
                        if entry.dirtyCount > 0 {
                            chip("\(entry.dirtyCount) changed", tint: .purple)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(title)")

            if entry.dirtyCount > 0 {
                Button("Preview") {
                    onOpenPreview(entry.id)
                    dismiss()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .tint(.purple)
                .accessibilityLabel("Open Preview for \(title)")
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(hovering ? 1 : 0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color(for: entry.group).opacity(hovering ? 0.28 : 0.10), lineWidth: 1)
        )
        .onHover { hovering in
            hoveredID = hovering ? entry.id : (hoveredID == entry.id ? nil : hoveredID)
        }
    }

    private func chip(_ text: String, systemImage: String? = nil, tint: Color = .secondary) -> some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.12)))
    }

    private var footerNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Schedules run only while GrokBuild is open and that session’s grok process is alive. They do not continue after Quit.")
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

    private func color(for group: SessionDashboardEntry.Group) -> Color {
        switch group {
        case .needsYou: return .orange
        case .needsReview: return .purple
        case .working: return .accentColor
        case .scheduled: return .teal
        case .idle: return .secondary
        case .failed: return .red
        }
    }
}
