import AppKit
import SwiftUI

enum HelpTopic: String, CaseIterable, Identifiable {
    case overview
    case gettingStarted
    case settings
    case agents

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: return HelpMenuCopy.help
        case .gettingStarted: return HelpMenuCopy.gettingStarted
        case .settings: return HelpMenuCopy.settingsGuide
        case .agents: return HelpMenuCopy.agentsRolesAndSubagents
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "questionmark.circle"
        case .gettingStarted: return "play.circle"
        case .settings: return "gearshape"
        case .agents: return "person.2.badge.gearshape"
        }
    }
}

enum HelpMenuCopy {
    static let help = "GrokBuild Help"
    static let gettingStarted = "Getting Started"
    static let settingsGuide = "Settings Guide"
    static let agentsRolesAndSubagents = "Agents, Roles & Subagents"

    static let agentDefinition =
        "An Agent is a saved GrokBuild identity with instructions, appearance, and a session shortcut."
    static let sessionRoleDefinition =
        "A session role runs the entire current session through grok --agent."
    static let subagentDefinition =
        "A subagent is a child worker that grok spawns during a turn."
}

@MainActor
enum HelpPanel {
    private static var panel: NSPanel?

    static func show(topic: HelpTopic = .overview) {
        let rootView = HelpPanelView(initialTopic: topic)

        if let panel {
            panel.contentView = NSHostingView(rootView: rootView)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = HelpMenuCopy.help
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.minSize = NSSize(width: 640, height: 460)
        window.center()
        window.makeKeyAndOrderFront(nil)
        panel = window
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct HelpPanelView: View {
    @State private var selection: HelpTopic

    init(initialTopic: HelpTopic) {
        _selection = State(initialValue: initialTopic)
    }

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.systemImage)
                    .tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(selection.title, systemImage: selection.systemImage)
                        .font(.title2.weight(.semibold))

                    content(for: selection)
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private func content(for topic: HelpTopic) -> some View {
        switch topic {
        case .overview:
            helpSection(
                "What GrokBuild does",
                body: "GrokBuild is a native macOS workspace and session UI for the grok CLI. Grok still owns execution, tools, delegation, permissions, and model behavior."
            )
            helpSection(
                "Core workflow",
                bullets: [
                    "Add projects and keep multiple restorable sessions per project.",
                    "Choose a model, session role, and permission mode from the composer.",
                    "Use the dashboard to track working, waiting, failed, scheduled, and review-ready sessions.",
                    "Enable Browser, Computer Use, Memory, Workflows, skills, and MCP servers from Settings.",
                ]
            )
            helpSection(
                "Where to go next",
                body: "Open Getting Started for the basic flow, Settings Guide for configuration, or Agents, Roles & Subagents for the identity and delegation model."
            )

        case .gettingStarted:
            numberedStep(1, "Add a project", "Click the + in the Projects section and choose a folder.")
            numberedStep(2, "Start a session", "Select the project, then create a session or choose an Agent.")
            numberedStep(3, "Configure the session", "Use the composer controls to choose the whole-session role, mode, model, and reasoning effort.")
            numberedStep(4, "Describe the outcome", "Prompt normally. Grok can use its tools and delegate to subagents when appropriate.")
            numberedStep(5, "Track parallel work", "Use the sidebar and Sessions Dashboard to switch between sessions and see what needs attention.")
            numberedStep(6, "Add capabilities", "Open Settings to configure permissions, Browser, Computer Use, Memory, Workflows, MCP servers, skills, and custom roles.")

        case .settings:
            helpSection(
                "Session defaults",
                bullets: [
                    "Agents — choose the default main agent for new sessions, browse discovered agents, and manage custom roles. Saved roster Agents are managed in the sidebar.",
                    "Models — manage providers and models shared with the grok CLI, and choose its default model.",
                    "Permissions — configure permission mode, sandboxing, reasoning defaults, subagents, and allow/deny rules.",
                ]
            )
            helpSection(
                "Capabilities",
                bullets: [
                    "Memory — enable cross-session memory and browse or add memory notes.",
                    "Workflows — enable grok’s Rhai workflows.",
                    "Browser — configure browser MCP tools, runtime, profile, and CDP connection.",
                    "Computer Use — configure native macOS automation, permissions, policy, and limits.",
                ]
            )
            helpSection(
                "Extensions",
                bullets: [
                    "MCP Servers — inspect external tool-server configuration and health.",
                    "Skills — browse skills discovered by grok.",
                    "Plugins — inspect and manage installed plugins.",
                    "Marketplace — inspect and manage plugin sources.",
                ]
            )
            helpSection(
                "Integration",
                bullets: [
                    "Compatibility — inspect Cursor, Claude, and Codex compatibility layers.",
                    "Hooks — inspect project and user hook configuration.",
                ]
            )
            helpSection(
                "Application",
                bullets: [
                    "App — updates, steering behavior, completion sound, Privacy Mode, and Doctor diagnostics.",
                ]
            )
            helpSection(
                "When changes take effect",
                bullets: [
                    "The Agents default applies to new sessions; Save Default & Apply to Current also updates the active session.",
                    "Browser and Computer Use enable switches apply immediately and restart grok; their other runtime edits use Apply and Restart Grok.",
                    "Permissions and other panes with Apply and Restart Grok save settings, then restart active connections so launch flags or tools change.",
                    "Model, role, MCP, skill, plugin, and hook editors update shared grok configuration. Restart or start a new session when the pane indicates it is required.",
                    "Button labels and status text in each pane are the source of truth for pending versus applied changes.",
                ]
            )

        case .agents:
            helpSection("Agent", body: HelpMenuCopy.agentDefinition)
            helpSection("Session role", body: HelpMenuCopy.sessionRoleDefinition)
            helpSection("Subagent", body: HelpMenuCopy.subagentDefinition)
            helpSection(
                "Using Agents",
                bullets: [
                    "Create an Agent from the + in the Agents section. Its instructions sync to its linked custom role.",
                    "Click an Agent to focus its live session in the current project or start a new one.",
                    "Pin important Agents. The default active-only list also includes Agents with a live session in the current project.",
                    "Use Show all agents to create, edit, start, pin, duplicate, or delete any saved Agent.",
                ]
            )
            helpSection(
                "Running roles and spawning subagents",
                bullets: [
                    "The composer’s Run this session as menu changes the role for the whole session and restarts grok.",
                    "Choosing a custom role does not spawn a child worker.",
                    "To use a role as a subagent, ask grok to delegate a task to it in your prompt.",
                ]
            )
            helpSection(
                "Example",
                body: "Use Chief to keep scope and coordinate, Scout to research, Builder to implement, and Verifier to review. Run them as separate visible sessions, or ask Chief to delegate focused work to a linked role as a subagent."
            )
        }
    }

    @ViewBuilder
    private func helpSection(_ title: String, body: String? = nil, bullets: [String] = []) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if let body {
                Text(body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                    Text(bullet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func numberedStep(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.14)))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
