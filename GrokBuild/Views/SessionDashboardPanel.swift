import SwiftUI

/// Snapshot of a live session for the dashboard (owned by `ContentView`).
struct SessionDashboardEntry: Identifiable, Hashable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case needsInput
        case working
        case idle
        case failed

        var title: String {
            switch self {
            case .needsInput: return "Needs input"
            case .working: return "Working"
            case .idle: return "Idle"
            case .failed: return "Failed"
            }
        }

        var systemImage: String {
            switch self {
            case .needsInput: return "hand.raised"
            case .working: return "ellipsis.circle"
            case .idle: return "moon.zzz"
            case .failed: return "exclamationmark.triangle"
            }
        }
    }

    let id: UUID
    let title: String
    let workspaceName: String
    let group: Group
    let modelName: String
    let pendingCount: Int
}

struct SessionDashboardPanel: View {
    let entries: [SessionDashboardEntry]
    var onSelect: (UUID) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Session Dashboard")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            if entries.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Open a project and start a session to see it here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(SessionDashboardEntry.Group.allCases, id: \.self) { group in
                        let groupEntries = entries.filter { $0.group == group }
                        if !groupEntries.isEmpty {
                            Section(group.title) {
                                ForEach(groupEntries) { entry in
                                    Button {
                                        onSelect(entry.id)
                                        dismiss()
                                    } label: {
                                        HStack(alignment: .top) {
                                            Image(systemName: group.systemImage)
                                                .foregroundStyle(color(for: group))
                                                .frame(width: 20)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(entry.title)
                                                    .font(.headline)
                                                Text(entry.workspaceName)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                HStack(spacing: 8) {
                                                    Text(entry.modelName)
                                                        .font(.caption2)
                                                        .foregroundStyle(.tertiary)
                                                    if entry.pendingCount > 0 {
                                                        Text("\(entry.pendingCount) pending")
                                                            .font(.caption2.weight(.medium))
                                                            .foregroundStyle(.orange)
                                                    }
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    private func color(for group: SessionDashboardEntry.Group) -> Color {
        switch group {
        case .needsInput: return .orange
        case .working: return .accentColor
        case .idle: return .secondary
        case .failed: return .red
        }
    }
}
