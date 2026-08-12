---
name: grokbuild-grok-cli
description: Works with grok CLI integration in GrokBuild — auth state, version checks, session resume, permission settings, custom models / Cursor bridge, and bundled browser skill. Use when changing GrokProcess, GrokCLIService, UpdateChecker, CustomModelStore, CursorBridge*, or grok-related settings UI.
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

## Custom subagents (roles)

grok owns subagent orchestration (main agent delegates to subagents in parallel; gated by `--no-subagents` / Settings → Permissions "Disable subagents"). GrokBuild adds a thin CRUD editor for **roles** in Settings → **Agents** → "Custom subagents".

- **Schema (installed grok, verified via `~/.grok/README.md`):** roles live in `~/.grok/config.toml` as `[subagents.roles.<name>]` with `description`, `model` (empty = inherit parent session model), and `prompt_file`. Personas (`[subagents.personas.*]`, tone-only, no model) and `[subagents.toggle]` / `[subagents.models]` are *not* managed by the app. The third-party `~/.grok/user-settings.json` `subAgents` array is a different CLI — **not** what xAI's grok uses.
- **Storage:** `SubagentRole` + `SubagentRoleStore` in `CustomModelSettings.swift` mirror `CustomModelStore` — minimal targeted TOML edits that preserve all other content and unmanaged role keys (for example `default_capability_mode`); each instruction is written to `~/.grok/prompts/<name>.md` and referenced via `prompt_file`. Relative `prompt_file` values resolve from the user's home directory. Removing a role deletes its GrokBuild-managed prompt file.
- **UI:** `SubagentRoleEditor` sheet (name/model/instruction/description). Model picker options come from `CustomModelStore.load()` + `grok-build`. Reserved names (`general`, `general-purpose`, `explore`, `plan`, `vision`, `verify`, `computer`) are rejected. Roles are a separate concept from the read-only discovered-agents list — `grok inspect --json` does not report them — but custom role names are shown under **Run as custom role** in Settings' default-agent picker and the chat agent pill menu. Choosing one in those pickers runs the whole session as that role; to spawn it as a child subagent, ask for it in chat.
- **Why edit the file directly:** grok's `/agents` (`/config-agents`) TUI manager is a pager builtin, not exposed over `grok agent stdio` (same limitation as `/remember`). Covered by `AgentsAndCapabilitiesTests`.

## Custom models & Cursor bridge

OpenAI-compatible providers/models live in `~/.grok/config.toml` via `CustomModelStore` / `ProviderStore` (Settings → **Models**). Display names from Fetch → Add model use **Provider + model** (`ProviderModelNaming`, e.g. `MiniMax M2.5`); Cline uses `Cline …`, Cursor uses `Cursor …`. **Create custom provider…** includes a Spark LAN example (`CustomProviderExample`); Fetch models treats only localhost / 127.0.0.1 as local, so Tailscale hosts like `http://spark:8001/v1` need a dummy key.

**Managed Cursor bridge** (not Cursor IDE Compatibility / Computer Use MCP):

| Piece | Role |
|-------|------|
| `ProviderPreset.cursor` | Install provider; config.toml `api_key = "local"`, `base_url = http://127.0.0.1:18787/v1` |
| `CursorBridgeKeychain` | Real Cursor user key → Application Support `Secrets/cursor-api-key` (0600) |
| `CursorBridgeRuntime` | Spawns bundled `Resources/CursorBridge/cursor-openai-bridge.mjs` (`@cursor/sdk`); validates key via `cursor-validate-key.mjs` before save/start |
| `cursor-bridge-auth.mjs` | `resolveCursorApiKey` — SDK auth uses process env `CURSOR_API_KEY`; ignore grok's xAI session JWT / `local` Bearer unless token is `crsr_…` |
| Node ≥ 22.13 | Required on the machine (`CursorBridge.NodeRequirement` / Doctor / Settings install banner) |

Do **not** put the Cursor user key in config.toml. If chat shows `[bridge error] Invalid User API Key`, check that the bridge is using env key resolution (not forwarding the session JWT) and that Settings → Models → Cursor has a valid saved key. Pref `GrokBuild.cursorBridge.managedEnabled` is set on Cursor provider install (not a Settings toggle). Full map: `ARCHITECTURE.md` → Custom models → Cursor bridge.

## Browser backend

Browser tools are provided by the bundled `agent-browser` CLI (`BrowserSettings.swift`), exposed to grok as an stdio MCP server (`grokbuild-browser`) via `AgentBrowserService.browserMCPConfig`; managed or external Chromium over CDP. (grok's native `browser_tab` was evaluated and removed — it wasn't exposed to sessions in practice.)

## Scheduled tasks (mirror of grok `scheduler_*`)

grok owns scheduling (`scheduler_create`/`list`/`delete`, `/loop`); the ACP surface is prompt-only, so GrokBuild can't call these tools directly. Instead it **observes** them: `GrokProcess` detects scheduler tool-call `session/update`s (`SchedulerToolParsing.schedulerName`) and yields `AcpEvent.schedulerActivity(payload:)`; `ChatStore` feeds them to `ScheduledTaskTracker` → `ChatStore.scheduledTasks`, rendered by `ChatView.tasksStatusPill`.

- **Authoritative refresh:** `scheduler_list` output replaces the mirror; create/delete update incrementally (correlating `tool_call` rawInput with completing `tool_call_update` rawOutput).
- **Actions drive grok via prompts** (cost a turn): `refreshScheduledTasks()` (`scheduler_list`), `createScheduledTask(interval:prompt:)` (`/loop`), `cancelScheduledTask(_:)` (`scheduler_delete`).
- **Wire shape (verified live, grok 0.2.93):** the initiating `tool_call` carries `_meta."x.ai/tool".name` = `scheduler_*` and `rawInput`; the **completing** `tool_call_update` carries **`rawOutput`** but **no `_meta`**, and `rawOutput.type` is **CamelCase** (`SchedulerCreate` / `SchedulerList` / `SchedulerDelete`). Detection must match `_meta` name OR a **case-insensitive** `rawOutput.type` prefix — see `SchedulerToolParsing`.
- **`/loop` caveat:** the `/loop` slash command is handled by the CLI and does **not** emit a `scheduler_*` tool call, so the pill only updates after **Refresh** (or when grok schedules via its tool, e.g. natural-language requests). The mirror only reflects the live session; schedules fire only while that session's grok process is alive (LRU-capped). Covered by `ScheduledTaskTests` (includes the real captured create→list sequence).

## Background tasks (richer Tasks pill)

Same mirror pattern as schedulers, extended in `BackgroundTaskStore.swift`:

- **Kinds:** scheduled (`scheduler_*`), background `run_terminal_command` (when `background: true` in rawInput), `monitor`, subagent tools (`spawn_subagent`, etc.).
- **ACP:** `GrokProcess` yields `AcpEvent.backgroundActivity(payload:)`; `ChatStore.backgroundActivities` feeds `ChatView.tasksStatusPill` (sectioned menu).
- Covered by `BackgroundTaskTests`.

## Rhai workflows vs skill chips

Two different grok features — do not conflate them in UI copy:

| Feature | What it is | GrokBuild surface |
|---------|------------|-------------------|
| **Skill chips** | User-invocable skills from `grok inspect` (`/design`, `/review`, …) | `SkillSlashCommands` composer chips |
| **Rhai workflows** | Background scripts in `.grok/workflows/`, `/workflow` tools | `[workflows] enabled` in config.toml (`WorkflowsConfigStore`), `WorkflowsSettingsPane`, `workflowsStatusPill`, `SavedWorkflowsPanel` |

`WorkflowsConfigStore.setEnabled` posts `.workflowsConfigChanged` so the chat pill refreshes without restart.

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

1. **`make test`** — extend `UpdateCheckerTests`, `CustomModelTests`, `CompetitiveUXTests`, or other service tests as appropriate. Bridge auth helper: `node --test GrokBuild/Resources/CursorBridge/cursor-bridge-auth.test.mjs` (also run by `make test` when Node is present).
2. **`ARCHITECTURE.md`** — GrokProcess/ACP flow, custom models / Cursor bridge, persistence keys, notifications.
3. **`README.md`** — if user-visible CLI/settings behavior changed.
4. **This skill** + `grok-cli-integration.mdc` — if APIs, custom-model, or Cursor bridge contracts changed.
5. **Bundled skill `SKILL.md`** — if install path, tools, or agent instructions changed.

## Workspace instructions

Per-project `AGENTS.md` in workspace roots is surfaced in the sidebar; this repo's root `AGENTS.md` applies when GrokBuild desktop is the workspace.
