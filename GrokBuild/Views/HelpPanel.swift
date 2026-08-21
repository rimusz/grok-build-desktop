import AppKit
import SwiftUI

enum HelpTopic: String, CaseIterable, Identifiable {
    case overview
    case gettingStarted
    case settings
    case models
    case agents
    case sessions
    case browserAndComputerUse

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: return HelpMenuCopy.help
        case .gettingStarted: return HelpMenuCopy.gettingStarted
        case .settings: return HelpMenuCopy.settingsGuide
        case .models: return HelpMenuCopy.models
        case .agents: return HelpMenuCopy.agentsRolesAndSubagents
        case .sessions: return HelpMenuCopy.sessions
        case .browserAndComputerUse: return HelpMenuCopy.browserAndComputerUse
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "questionmark.circle"
        case .gettingStarted: return "play.circle"
        case .settings: return "gearshape"
        case .models: return "cpu"
        case .agents: return "person.2.badge.gearshape"
        case .sessions: return "square.grid.2x2"
        case .browserAndComputerUse: return "desktopcomputer"
        }
    }
}

enum HelpMenuCopy {
    static let help = "GrokBuild Help"
    static let gettingStarted = "Getting Started"
    static let settingsGuide = "Settings Guide"
    static let models = "Models"
    static let agentsRolesAndSubagents = "Agents, Roles & Subagents"
    static let sessions = "Sessions"
    static let browserAndComputerUse = "Browser & Computer Use"

    static let agentDefinition =
        "An Agent is a saved GrokBuild identity with instructions, appearance, and a session shortcut."
    static let sessionRoleDefinition =
        "A session role runs the entire current session through grok --agent."
    static let subagentDefinition =
        "A subagent is a child worker that grok spawns during a turn."

    static let modelsSharedConfig =
        "Custom providers and models are written to ~/.grok/config.toml. They work in GrokBuild sessions and in the grok CLI/TUI via /model <id>."
    static let modelsFetchBeforeAdd =
        "Fetch models from a provider before adding one. Loopback URLs (localhost, 127.0.0.1, 0.0.0.0, host.docker.internal) can omit the API key; LAN or Tailscale hosts need a dummy key such as not-needed."
    static let sessionsDashboardDefinition =
        "Sessions Dashboard lists this project’s live named sessions grouped by status."
    static let sessionsHistoryDefinition =
        "Sessions History lists this project’s archived grok sessions so you can resume or delete them."
    static let browserEnableDefinition =
        "The Browser and Computer Use enable switches apply immediately and restart grok. Other runtime or permission edits still use Apply and Restart Grok."
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
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
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
                body: "Open Getting Started for the basic flow, Settings Guide for configuration, Models for custom providers, Agents, Roles & Subagents for identity and delegation, Sessions for Dashboard versus History, or Browser & Computer Use for automation setup."
            )

        case .gettingStarted:
            numberedStep(1, "Add a project", "Click the + in the Projects section and choose a folder.")
            numberedStep(2, "Start a session", "Select the project, then create a session or choose an Agent.")
            numberedStep(3, "Configure the session", "Use the composer controls to choose the whole-session role, mode, model, and reasoning effort. Add custom providers from Help → Models if you need more than the built-in grok models.")
            numberedStep(4, "Describe the outcome", "Prompt normally. Grok can use its tools and delegate to subagents when appropriate.")
            numberedStep(5, "Track parallel work", "Use the sidebar and Sessions Dashboard for live tabs in this project. Sessions History is the archive of past grok sessions.")
            numberedStep(6, "Add capabilities", "Open Settings to configure permissions, Browser, Computer Use, Memory, Workflows, MCP servers, skills, and custom roles. Settings → App → Open Doctor… checks the grok CLI, auth, Node.js, and the Cursor bridge.")

        case .settings:
            helpSection(
                "Session defaults",
                bullets: [
                    "Agents — choose the default main agent for new sessions, browse discovered agents, and manage custom roles. Saved roster Agents are managed in the sidebar.",
                    "Models — manage providers and models shared with the grok CLI, and choose its default model. See the Models topic for the add-provider flow.",
                    "Permissions — configure permission mode, sandboxing, reasoning defaults, subagents, and allow/deny rules.",
                ]
            )
            helpSection(
                "Capabilities",
                bullets: [
                    "Memory — enable cross-session memory and browse or add memory notes.",
                    "Workflows — enable grok’s Rhai workflows.",
                    "Browser — configure browser MCP tools, runtime, profile, and CDP connection. See Browser & Computer Use for setup.",
                    "Computer Use — configure native macOS automation, permissions, policy, and limits. See Browser & Computer Use for Accessibility.",
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
                    "App — updates, steering behavior, completion sound, Privacy Mode, and Doctor diagnostics (CLI, auth, config.toml, Node.js, Cursor bridge).",
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

        case .models:
            helpSection("Shared with the grok CLI", body: HelpMenuCopy.modelsSharedConfig)
            helpSection(
                "Models-only use",
                body: "You can open Settings → Models with no project and without grok login. Entries still work later in GrokBuild sessions and immediately in the grok TUI."
            )
            numberedStep(1, "Add a provider", "Open Settings → Models → 1. Add Provider. Expand Provider Templates and Install a preset (OpenAI, MiniMax, Ollama, Cursor, and others), or choose Create custom provider… for any OpenAI-compatible endpoint.")
            numberedStep(2, "Save the endpoint and key", "Enter the base URL and API key, then save so it appears under Your Providers. The key is shared by every model on that provider.")
            numberedStep(3, "Fetch, then add models", "On the provider row, Fetch models, then Add model. Pick from the fetched list. GrokBuild supports up to 28 custom models, listed A–Z by provider and model.")
            numberedStep(4, "Use the model", "Choose it in the composer picker, set Default Model for new tabs, or type /model <id> in chat. Existing tabs keep their own per-tab model.")
            helpSection("Keys for local and LAN servers", body: HelpMenuCopy.modelsFetchBeforeAdd)
            helpSection(
                "Custom provider example",
                body: "Create custom provider… includes an NVIDIA DGX Spark fill-in (http://spark:8001/v1 with dummy key not-needed). Spark and similar LAN servers ignore the dummy key; Fetch still requires one because that host is not loopback."
            )
            helpSection(
                "Cursor models",
                bullets: [
                    "Install the Cursor template, paste a Cursor API key from cursor.com/dashboard?tab=integrations, then save. GrokBuild checks the key and starts a local OpenAI sidecar on 127.0.0.1:18787.",
                    "The real key is stored under Application Support, not Keychain and not config.toml (models keep api_key = \"local\").",
                    "Needs system Node ≥ 22.13. Doctor can install Node via Homebrew or nodejs.org. Cursor IDE does not need to be open.",
                    "Then Fetch models and Add model (names like Cursor Composer 2.5). Grok keeps its own tools; Cursor subscription and terms are yours.",
                    "This is not Settings → Compatibility → Cursor, and not the Computer Use Cursor MCP.",
                ]
            )
            helpSection(
                "Optional model fields",
                bullets: [
                    "API backend — OpenAI Chat Completions (default), OpenAI Responses, or Anthropic Messages.",
                    "Env key — keep the secret in an environment variable instead of writing it into config.toml.",
                    "Context window, vision, thinking, and reasoning-effort hints are UI metadata; grok remains authoritative when it reports limits.",
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

        case .sessions:
            helpSection("Sessions Dashboard", body: HelpMenuCopy.sessionsDashboardDefinition)
            helpSection("Sessions History", body: HelpMenuCopy.sessionsHistoryDefinition)
            helpSection(
                "Live work in this project",
                bullets: [
                    "The dashboard groups tabs as Needs you, Failed, Working, Needs review, Scheduled, and Idle.",
                    "New Parallel Session starts another named tab in this project (optional role and git worktree) so two sessions can work at once.",
                    "New Automation creates a named session that repeats a prompt on a schedule (/loop). Schedules only fire while GrokBuild is open and that session process is alive.",
                    "Needs review lists tabs with uncommitted changes; Preview opens the diff pane to apply, commit, or open a PR.",
                ]
            )
            helpSection(
                "Sidebar and archive",
                bullets: [
                    "Pin a session to keep it in the global Pinned section. Settle finished work into a restorable shelf.",
                    "Sessions History (clock) resumes or deletes archived grok sessions for this project. It is not the live dashboard.",
                    "Right-click a message to Rewind to Here — that truncates chat only and does not restore files.",
                    "Each tab keeps its own model. New tabs follow Settings → Models → Default Model.",
                ]
            )
            helpSection(
                "Git worktrees",
                body: "Use the selected project’s branch chip or Branches & Worktrees… to check out a branch. New Worktree Session… starts a tab in a linked worktree (WT badge)."
            )

        case .browserAndComputerUse:
            helpSection("When enablement applies", body: HelpMenuCopy.browserEnableDefinition)
            helpSection(
                "Browser",
                bullets: [
                    "Settings → Browser. Turn on the switch after the agent-browser CLI is installed (Homebrew: brew install agent-browser, or npm).",
                    "Use the managed automation profile by default, or attach to Chrome, Brave, Edge, Arc, or another Chromium browser over CDP.",
                    "A new managed profile starts on a blank tab until Grok opens a URL. Attaching to an existing browser lets Grok interact with that window.",
                    "Runtime, profile, and CDP edits still need Apply and Restart Grok.",
                ]
            )
            helpSection(
                "Computer Use",
                bullets: [
                    "Settings → Computer Use. agent-desktop is bundled — there is nothing extra to install.",
                    "Grant macOS Accessibility for GrokBuild. Screen Recording is optional and only needed for screenshots.",
                    "After a local make run ad-hoc rebuild, macOS may drop Accessibility trust. Re-add the app in System Settings → Privacy & Security → Accessibility, or follow the in-app prompt.",
                    "Policy, step limits, and timeouts use Apply and Restart Grok. The Computer Use Cursor MCP is unrelated to Settings → Models → Cursor.",
                ]
            )
            helpSection(
                "Doctor",
                body: "Settings → App → Open Doctor… checks the grok CLI, auth, config.toml, Browser/Computer Use, Node.js, and whether the Cursor bridge is reachable."
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
