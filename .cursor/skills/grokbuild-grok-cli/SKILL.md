---
name: grokbuild-grok-cli
description: Works with grok CLI integration in GrokBuild — auth state, version checks, session resume, permission settings, and bundled browser skill. Use when changing GrokProcess, GrokCLIService, UpdateChecker, or grok-related settings UI.
---

# Grok CLI in GrokBuild

## Boundaries

GrokBuild is a UI shell. Core agent behavior (ACP, MCP, skills, plan mode, subagents) stays in the `grok` CLI.

## Key APIs

```swift
// One-shot commands
try await GrokCLIService().run(["--version"])
await GrokCLIService.versionDisplayLine()

// Long-running agent
GrokProcess — grok agent … stdio, ACP events

// Updates
UpdateChecker.checkAppRelease()   // notarized GitHub releases only
UpdateChecker.checkGrokCLI()      // grok update --check --json
```

## Auth & status bar

- `GrokProcess.needsAuthentication` drives login banner and menu header.
- Post `.grokStatusChanged` with `status` and `authenticated` keys.
- Menu: "GrokBuild connected to grok cli" when authenticated.

## Permission settings

Stored in `UserDefaults` via `GrokSettingsKeys` — `allowRules`, `denyRules`, `permissionMode`, `selectedAgent`, etc. Passed to `GrokLaunchOptions` in `ChatStore`.

## Session agent (`--agent`) — per tab

- **Per session tab.** Each tab launches with `ChatStore.effectiveAgentSelection` → `GrokAgentProfiles.launchArgument(for:)` → `GrokLaunchOptions.agent` → `grok --agent`.
- **Resolution:** explicit per-tab override (`SavedSessionRecord.agent`, set via `ChatStore.setSessionAgent`) when present, else the global default `grokbuild.selectedAgent` (Settings → **Agents** = default for **new** sessions). Non-overridden tabs adopt the default on next launch; overridden tabs keep their choice. Only overridden tabs persist a value (`persistedAgentSelection`).
- **Values:** `""` = grok default (no flag); any other value = discovered agent name.
- **UI:** `ChatView.agentStatusPill` menu (built-ins from `GrokAgentProfiles.builtInOptions` + discovered via `ChatStore.loadDiscoveredAgentsIfNeeded`). Picking one calls `setSessionAgent` → **restarts that tab's grok** (agents change only at launch) and posts `.liveSessionAgentChanged` → `persistSessionLayout()`.
- Discover agents via `GrokCLIService.listAgents(cwd:)` (parses `agents` from `grok inspect --json`). Keep this thin — grok owns agents/personas.

## Browser backend

Browser tools are provided by the bundled `agent-browser` CLI (`BrowserSettings.swift`), exposed to grok as an stdio MCP server (`grokbuild-browser`) via `AgentBrowserService.browserMCPConfig`; managed or external Chromium over CDP. (grok's native `browser_tab` was evaluated and removed — it wasn't exposed to sessions in practice.)

## Scheduled tasks (mirror of grok `scheduler_*`)

grok owns scheduling (`scheduler_create`/`list`/`delete`, `/loop`); the ACP surface is prompt-only, so GrokBuild can't call these tools directly. Instead it **observes** them: `GrokProcess` detects scheduler tool-call `session/update`s (`SchedulerToolParsing.schedulerName`) and yields `AcpEvent.schedulerActivity(payload:)`; `ChatStore` feeds them to `ScheduledTaskTracker` → `ChatStore.scheduledTasks`, rendered by `ChatView.tasksStatusPill`.

- **Authoritative refresh:** `scheduler_list` output replaces the mirror; create/delete update incrementally (correlating `tool_call` rawInput with completing `tool_call_update` rawOutput).
- **Actions drive grok via prompts** (cost a turn): `refreshScheduledTasks()` (`scheduler_list`), `createScheduledTask(interval:prompt:)` (`/loop`), `cancelScheduledTask(_:)` (`scheduler_delete`).
- **Wire shape (verified live, grok 0.2.93):** the initiating `tool_call` carries `_meta."x.ai/tool".name` = `scheduler_*` and `rawInput`; the **completing** `tool_call_update` carries **`rawOutput`** but **no `_meta`**, and `rawOutput.type` is **CamelCase** (`SchedulerCreate` / `SchedulerList` / `SchedulerDelete`). Detection must match `_meta` name OR a **case-insensitive** `rawOutput.type` prefix — see `SchedulerToolParsing`.
- **`/loop` caveat:** the `/loop` slash command is handled by the CLI and does **not** emit a `scheduler_*` tool call, so the pill only updates after **Refresh** (or when grok schedules via its tool, e.g. natural-language requests). The mirror only reflects the live session; schedules fire only while that session's grok process is alive (LRU-capped). Covered by `ScheduledTaskTests` (includes the real captured create→list sequence).

## Memory (cross-session)

The app owns the **toggle**; grok owns storage/index/injection. `grokbuild.memoryEnabled` (Settings → **Memory**) maps in `ChatStore.restartProcess` via `GrokMemoryFlag.argument(noMemory:experimentalMemory:)`:

- `true` → `--experimental-memory`; `false` → `--no-memory` (grok gives `--no-memory` absolute priority, so the app never emits both). It's a launch flag — **app-scoped**, not written to `~/.grok/config.toml`, so the grok TUI is unaffected. Supersedes the old Permissions "Disable memory" toggle (`grokbuild.noMemory` key is now legacy/unused).
- **Files:** `MemoryStore.swift` enumerates `~/.grok/memory/` (global `MEMORY.md`, `<slug-hash>/MEMORY.md`, `<slug-hash>/sessions/*.md` newest-first); `MemoryBrowserPanel.swift` is a read-only viewer (copy/reveal/delete-session, session-only guard). `ChatView.memoryStatusPill` (label "Memory", **only rendered when memory is enabled** — no off-state pill) surfaces Browse / Remember / Open Memory Settings.
- **ACP limitation (verified live, grok 0.2.93):** enabling memory registers `memory_search`/`memory_get` + first-turn recall, but `/remember`, `/flush`, `/dream`, `/memory` are **TUI pager builtins** and are **not** in `availableCommands` over `grok agent stdio`. So **Remember** writes a note directly to global `MEMORY.md` (`MemoryStore.appendGlobalNote`; grok's watcher reindexes it) via `ChatStore.remember`; flush/dream are not surfaced (they run automatically / in the TUI). Do not add `/flush`/`/dream` prompt actions — they'd be treated as literal text. Covered by `MemoryStoreTests` + `GrokMemoryFlag` tests.

## Bundled skills

Skills ship under `GrokBuild/Resources/Skills/` and install to `~/.grok/skills/` when features are enabled:
- `grokbuild-browser-control` — `BrowserSkillInstaller`
- `grokbuild-grok-web` — `BrowserSkillInstaller` (installed alongside browser-control when browser tools enabled; drives grok.com web features like Imagine/skills/connectors via browser tools)
- `grokbuild-computer-use` — `ComputerUseSkillInstaller`
- `grokbuild-desktop` — bundled only (GrokBuild self-hints)

Browser **quick presets** (`BrowserPreset` in `BrowserSettings.swift`) apply runtime/session-name/CDP settings for common targets (e.g. `.grokCom`).

## After changing CLI integration

Same session, before finishing:

1. **`make test`** — extend `UpdateCheckerTests`, integration tests, or service tests as appropriate.
2. **`ARCHITECTURE.md`** — GrokProcess/ACP flow, persistence keys, notifications, feature subsystem table.
3. **`README.md`** — if user-visible CLI/settings behavior changed.
4. **This skill** + `grok-cli-integration.mdc` — if APIs or update-check behavior changed.
5. **Bundled skill `SKILL.md`** — if install path, tools, or agent instructions changed.

## Workspace instructions

Per-project `AGENTS.md` in workspace roots is surfaced in the sidebar; this repo's root `AGENTS.md` applies when GrokBuild desktop is the workspace.
