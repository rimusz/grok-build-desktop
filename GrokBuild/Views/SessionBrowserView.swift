import SwiftUI

struct SessionBrowserView: View {
    @Bindable var store: ChatStore
    let workspace: Workspace?
    var onResume: () -> Void = {}
    var onResumeSession: ((GrokSessionInfo) -> Void)?

    private let service = GrokCLIService()

    @State private var sessions: [GrokSessionInfo] = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sessions")
                        .font(.title2.weight(.semibold))
                    Text(workspace?.path.path ?? "Select a project to list matching sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding()

            Divider()

            HStack {
                TextField("Search sessions", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await loadSessions() }
                    }
                Button("Search") {
                    Task { await loadSessions() }
                }
                Button("Recent") {
                    query = ""
                    Task { await loadSessions() }
                }
            }
            .padding()

            List {
                ForEach(sessions) { session in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(session.summary.isEmpty ? "(no summary)" : session.summary)
                                .font(.headline)
                                .lineLimit(2)
                            Spacer()
                            Button("Resume") {
                                Task {
                                    if let onResumeSession {
                                        onResumeSession(session)
                                    } else {
                                        await store.resumeSession(session)
                                    }
                                    onResume()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(workspace == nil)
                        }

                        HStack(spacing: 10) {
                            Text(session.id)
                                .font(.caption.monospaced())
                            Text(session.status)
                                .font(.caption)
                            Text("Created \(session.created)")
                                .font(.caption)
                            Text("Updated \(session.updated)")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                }
            }
            .overlay {
                if sessions.isEmpty && !isLoading {
                    ContentUnavailableView("No Sessions", systemImage: "clock.arrow.circlepath", description: Text(query.isEmpty ? "No recent sessions for this project." : "No sessions matched your search."))
                }
            }

            if isLoading {
                ProgressView()
                    .padding(.bottom, 10)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding()
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .task { await loadSessions() }
    }

    private func loadSessions() async {
        isLoading = true
        errorMessage = nil
        do {
            let cwd = workspace?.path
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedQuery.isEmpty {
                sessions = try await service.listSessions(limit: 50, cwd: cwd)
            } else {
                sessions = try await service.searchSessions(query: trimmedQuery, limit: 50, cwd: cwd)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
