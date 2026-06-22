import SwiftUI

@main
struct GrokBuildApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("preferredAppearance") private var appearance: String = "dark"

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .preferredColorScheme(appearance == "dark" ? .dark : .light)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1024, height: 720)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About GrokBuild") {
                    AboutPanel.show()
                }
            }

            CommandMenu("Project") {
                Button("Add Project…") {
                    NotificationCenter.default.post(name: .chooseWorkspaceRequested, object: nil)
                }
                .keyboardShortcut("O", modifiers: [.command, .shift])
            }

            CommandMenu("Session") {
                Button("New Session") {
                    NotificationCenter.default.post(name: .newSessionRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Browse Sessions…") {
                    NotificationCenter.default.post(name: .sessionsRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Stop Generation") {
                    NotificationCenter.default.post(name: .stopGenerationRequested, object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)

                Button("Focus Input") {
                    NotificationCenter.default.post(name: .focusInputRequested, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
            }
        }
    }
}
