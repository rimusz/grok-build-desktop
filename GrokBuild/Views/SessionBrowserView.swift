import SwiftUI

struct SessionBrowserView: View {
    let workspaces: [Workspace]
    var highlightedWorkspaceID: Workspace.ID?
    let liveSessionsByGrokID: [String: UUID]
    let selectedGrokSessionID: String?
    var onResume: () -> Void = {}
    var onResumeSession: (GrokSessionInfo, Workspace) -> Void
    var onSelectLive: (UUID) -> Void = { _ in }

    var body: some View {
        SessionsBrowserPanel(
            workspaces: workspaces,
            highlightedWorkspaceID: highlightedWorkspaceID,
            liveSessionsByGrokID: liveSessionsByGrokID,
            selectedGrokSessionID: selectedGrokSessionID,
            onResumeSession: { session, workspace in
                onResumeSession(session, workspace)
                onResume()
            },
            onSelectLive: { id in
                onSelectLive(id)
                onResume()
            }
        )
        .frame(minWidth: 760, minHeight: 520)
    }
}
