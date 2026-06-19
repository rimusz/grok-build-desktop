import SwiftUI

@main
struct GrokDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("preferredAppearance") private var appearance: String = "dark"

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .preferredColorScheme(appearance == "dark" ? .dark : .light)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About GrokDeck") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "GrokDeck",
                            .version: "0.2.0",
                            .credits: NSAttributedString(
                                string: "Native SwiftUI Mac frontend for the grok CLI.",
                                attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
                            )
                        ]
                    )
                }
            }

            CommandMenu("Workspace") {
                Button("Choose Workspace…") {
                    NotificationCenter.default.post(name: .chooseWorkspaceRequested, object: nil)
                }
                .keyboardShortcut("O", modifiers: [.command, .shift])
            }

            CommandMenu("Chat") {
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
