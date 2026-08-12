# GrokBuild — architecture reference

**Read this first in every new chat.** This document is the canonical map of how GrokBuild works. `AGENTS.md` points here; `.cursor/rules/` add file-specific conventions.

---

## Table of contents

1. [What GrokBuild is](#what-grokbuild-is)
2. [Design rules for agents](#design-rules-for-agents)
3. [Repository layout](#repository-layout)
4. [App lifecycle & shell](#app-lifecycle--shell)
5. [Runtime architecture](#runtime-architecture)
6. [GrokProcess & ACP](#grokprocess--acp)
7. [ChatStore](#chatstore)
8. [Multi-session model](#multi-session-model-contentview)
9. [Workspaces & projects](#workspaces--projects)
10. [Persistence](#persistence-userdefaults)
11. [Feature subsystems](#feature-subsystems)
12. [Settings system](#settings-system)
13. [In-app updates](#in-app-updates)
14. [UI layout & panels](#ui-layout--panels)
15. [Notifications](#notifications)
16. [Git integration](#git-integration)
17. [Build, test & release](#build-test--release)
18. [Common tasks → files](#common-tasks--files)
19. [Tests](#tests)
20. [Anti-patterns](#anti-patterns)
21. [Related docs](#related-docs)

---

## What GrokBuild is

GrokBuild is a **menu-bar macOS app** (SwiftUI + AppKit) that is a **UI shell over the `grok` CLI**. It spawns `grok agent stdio` per chat session and speaks **ACP (Agent Client Protocol)** JSON-RPC over stdin/stdout.

| GrokBuild owns | `grok` CLI owns (do NOT reimplement in Swift) |
|----------------|-----------------------------------------------|
| Windows, sidebar, composer, settings panes | ACP session lifecycle, tool execution |
| Multi-tab sessions, LRU process cap | MCP server wiring at runtime (GrokBuild only *injects* configs) |
| Per-tab model, per-project effort, layout persistence | Skills, hooks, plugins, plan mode, subagents |
| Browser/Computer Use **enablement** + bundled skills | Agent reasoning, permissions policy enforcement |
| In-app updates (app + CLI) | `grok update`, auth (`grok login`) |

**Platform:** macOS 26+. **Version:** `VERSION` → `AppVersion.display`. **Build:** SwiftPM only — no Xcode project; use `make` / `swift build`.

---

## Competitive posture

GrokBuild is the **open-source native SwiftUI shell** for `grok agent stdio`. We steal UX ideas from peers but stay thin and grok-only.

| Peer | Shape | What we take / avoid |
|------|-------|----------------------|
| grok-build-vscode (+ Electron/AFK Pilot) | Closest ACP GUI + remote | Take session UX (status dots, steer, `@` mentions). Avoid Electron and depending on their remote stack. |
| Xnative / AskHere | Closed-source native Mac | Compete on openness + Settings depth + Browser/Computer Use. No code reuse. |
| Grok-UI | Browser ops command center | Take ops surfaces (**Doctor**, live git, usage ledger, privacy). Not a multi-host fleet. |
| OpenMausBot | Multi-CLI messaging app | Take roster/unread affordances. Stay grok-only (no Claude/Codex drivers). |
| xai-org/grok-build | Official CLI/TUI | Source of truth for ACP/events/slash. Never reimplement the agent. |

**Non-goals:** Electron rewrite, Windows port, multi-provider agent fleet, or TUI scraping. A thin **optional** Cursor OpenAI `/v1` sidecar (Node + `@cursor/sdk`, inference-only) *is* in scope; GrokBuild does not become a second full Cursor Agents product UI (see [Custom models](#custom-models) → Cursor bridge).

### ACP event inventory (what we parse vs gaps)

Parsed today (`GrokProcess.AcpEvent`, mapped in `ChatStore.consumeOutput`): `messageChunk`, `thoughtChunk`, `toolCall` / `toolCallUpdate`, `plan` / `planFileContent`, `exitPlanRequest`, `questionRequest`, `permissionRequest`, `modeChanged`, `contextUsage` (`_meta.totalTokens`), `availableCommands`, `schedulerActivity`, `workflowActivity`, `backgroundActivity`, `error`, `rawLine`.

Gaps vs peers (advertising-driven; add only when the CLI emits them): **billed cost / usage breakdown** (input/cache/output/USD) — grok only reports `_meta.totalTokens` today, so the context indicator shows tokens, not cost; **explicit subagent lifecycle** beyond `spawn_subagent` tool activity; **workflow phase/agent-allocation** richer than `workflowActivity`. Steering reuses `session/prompt` (grok never cancels a turn) rather than a dedicated event.

---

## Design rules for agents

1. **Stay thin** — UI and local state only; wrap the CLI, don't replace it.
2. **Reuse services** — extend `GrokProcess`, `GrokCLIService`, `ChatStore`, `WorkspaceStore`, `SessionLayoutStore`, and feature services below.
3. **Match conventions** — read surrounding code before editing; minimize diff scope.
4. **Draft vs applied settings** — settings panes edit *draft* keys; live Grok sessions use *applied* keys (see [Settings system](#settings-system)).
5. **Post notifications** — auth/process changes → `.grokStatusChanged`; session title changes → `.liveSessionMessagesChanged`.
6. **Docs + tests with every code change** — run `make test`, add/extend `Tests/GrokBuildTests/`, update this file and other relevant docs in the same session (`.cursor/rules/docs-and-tests.mdc`).
7. **Commit only when asked** — user rule in this repo.

---

## Repository layout

```
grok-deck2/
├── GrokBuild/                    # Main app target (SwiftUI + AppKit)
│   ├── main.swift                # NSApplication entry (NOT GrokBuildApp.swift)
│   ├── AppDelegate.swift         # Single instance, main window, menus
│   ├── MainWindowLayout.swift    # Main window min/default size + composer max width
│   ├── StatusBarController.swift # Menu bar icon + actions
│   ├── ContentView.swift         # Root view: multi-session orchestration
│   ├── Views/                    # SwiftUI screens (SettingsView is large)
│   ├── Services/                 # Business logic, CLI integration
│   ├── Models/                   # Workspace, Message, Composer types
│   ├── Resources/
│   │   ├── Assets.xcassets/      # Menu bar icon, app icon
│   │   └── Skills/               # Bundled grok skills (copied at build)
│   ├── AboutPanel.swift          # AppKit About panel
│   └── UpdatePanel.swift         # AppKit Updates panel
├── GrokBuildComputerUseMCP/      # Separate SPM target: stdio MCP bridge → agent-desktop
├── Tests/GrokBuildTests/         # Unit/integration tests
├── scripts/                      # build-macos-app.sh, release.sh, notarize.sh, install-update
├── Package.swift                 # SPM manifest (macOS 26+)
├── VERSION                       # App version source
├── Makefile                      # make run | test | app | release
├── AGENTS.md                     # Agent entry (points here)
└── BUILDING.md                   # Signing, notarization, CI
```

**Excluded from build:** `GrokBuild/GrokBuildApp.swift` (legacy `@main` — do not use).

---

## App lifecycle & shell

### Entry point

`main.swift` → `AppDelegate.applicationDidFinishLaunching`:

1. **Single instance** — advisory `flock` on `~/Library/Application Support/GrokBuild/instance.pid`. Second launch posts `com.grokbuild.showMainWindow` and exits.
2. **Activation policy** — `.regular` (Dock icon + menu bar item).
3. **Status bar** — `StatusBarController()` (actions-first menu: open/new session, settings, updates, auth recovery when signed out, quit). At launch, `GrokAuthProbe` (`GrokCLIService.swift`) best-effort checks `~/.grok/auth.json` size (the grok CLI's own cached credentials — env API keys are deliberately not treated as signed in); runtime `.grokStatusChanged` from a live process remains authoritative and overrides this hint.
4. **Update scheduler** — `UpdateScheduler.start()` (background checks).
5. **Main window** — `openMainWindow()` hosts `ContentView` in `NSHostingController`.

### Window behavior

- **Close button** hides the window (`orderOut`), does not quit (`applicationShouldTerminateAfterLastWindowClosed` → false).
- **Reopen** (Dock click) → `applicationShouldHandleReopen` → show main window.
- Frame autosave name: `"MainWindow"`.

### Dual menus

| Menu | Location | Purpose |
|------|----------|---------|
| **App menu bar** (top of screen) | `AppDelegate.setupMainMenu()` | App (About, Settings ⌘,, Hide ⌘H, Quit), Edit, Project, Session, Window |
| **Status item menu** | `StatusBarController` | Actions-first quick actions, settings, updates, auth recovery, quit |

**Status item menu order:** auth header (+ **Run `grok login` in Terminal…** / **Retry Connection** when signed out) → **Open GrokBuild** → **New Session** → **Browse Sessions…** → **Add Project…** → **Settings…** (⌘,) → **Check for Updates…** / **Upgrade Available…** → **View Usage on grok.com…** → **About GrokBuild** → **Quit GrokBuild**. DEBUG builds add **Simulate Updates** after the updates item.

Menu actions that need the main UI post notifications (e.g. `.newSessionRequested`, `.openSettingsRequested`, `.retryConnectionRequested`) that `ContentView` handles.

**Status icon:** grok mark tints for light/dark menu bars; colored dot (green ready, blue busy/starting, red error) is not template-tinted. Accessibility value reflects status text (Ready / Working / Starting / Error / Idle).

---

## Runtime architecture

```mermaid
flowchart TB
    subgraph UI["SwiftUI layer"]
        CV[ContentView]
        SV[SidebarView]
        CHV[ChatView]
        STV[SettingsView]
    end

    subgraph State["@Observable state"]
        WS[WorkspaceStore]
        CS[ChatStore per session]
        SL[SessionLayoutStore]
    end

    subgraph Process["Process layer"]
        GP[GrokProcess]
        CLI["grok agent stdio"]
    end

    subgraph OneShot["One-shot CLI"]
        GCS[GrokCLIService]
    end

    CV --> WS
    CV --> CS
    CV --> SL
    CHV --> CS
    CS --> GP
    GP --> CLI
    STV --> GCS
    GCS --> CLI
```

### Request path (send a message)

1. User types in `ChatView` → `ChatStore.send(_:)`.
2. `ChatStore` ensures workspace selected and `GrokProcess` is `.ready` (restarts if needed).
3. Appends user `Message`, creates empty assistant `Message`, sets `isStreaming`.
4. `GrokProcess.send(prompt)` → ACP `session/prompt` JSON-RPC on stdin.
5. `GrokProcess` reader parses stdout → `AcpEvent` stream.
6. `ChatStore.consumeOutput()` maps events → message text, tool cards, permissions, thinking blocks.
7. On completion → `isStreaming = false`, posts `.liveSessionMessagesChanged` (also on user send), `.grokStatusChanged`.

### CLI discovery (shared)

`GrokProcess.locateGrokCLI()` and `GrokCLIService.locateGrokCLI()` search in order:

1. `GROK_CLI_PATH` environment variable
2. `~/.grok/bin/grok`
3. Homebrew paths
4. `PATH`

User must run `grok login` for authenticated sessions. Auth failures surface in `ChatStore.authRequiredMessage` and menu bar indicator. **Launch hint:** `GrokAuthProbe` checks the grok CLI's cached credentials (non-empty `~/.grok/auth.json`) for the status menu header before any session starts — env API keys are not treated as signed in; once a `GrokProcess` runs, `.grokStatusChanged` `authenticated` wins.

---

## GrokProcess & ACP

**File:** `Services/GrokProcess.swift`

`GrokProcess` is the long-running **ACP client**. One instance per `ChatStore`.

### Process states (`GrokProcessState`)

| State | Meaning |
|-------|---------|
| `.idle` | No process |
| `.starting` | Launching CLI, ACP handshake in progress |
| `.ready` | Session created/loaded, can accept prompts |
| `.busy` | Turn in progress |
| `.failed(String)` | Startup or fatal error; check `needsAuthentication` |

### Launch command shape

```
grok [--no-memory] [--permission-mode X] [--sandbox X] [--allow RULE] … \
     agent [--reasoning-effort X] [--model M] stdio
```

Built from `GrokLaunchOptions` in `ChatStore.restartProcess`. Working directory = **workspace path**.

### ACP lifecycle

1. `start(workspace:options:)` — spawn process, `initializeACP()` (JSON-RPC handshake).
2. `createSession(workspace:mcpServers:)` **or** `loadSession(id:…)` if resuming. When `session/load` fails with `FS_NOT_FOUND` / “Path not found” (stale on-disk grok session), GrokBuild falls back to `session/new`, sets `sessionLoadStartedFreshFallback`, and `ChatStore` adds a system note — local transcript is preserved. During load, the CLI replays prior turn history via `session/update` with `_meta.isReplay: true`; `GrokProcess` skips routing those to `ChatStore` (still applies `contextUsage` / `totalTokens`) so resume does not re-drive live tool/thinking UI.
3. MCP servers from `MCPServerConfig` passed in `session/new` (browser, computer use when enabled).
4. `send(_:)` — prompt during `.ready`/`.busy`.
5. `stop()` — tear down process (LRU cap, settings reload, app shutdown).

### ACP events (`AcpEvent`)

Consumed by `ChatStore.consumeOutput()`:

| Event | UI effect |
|-------|-----------|
| `.messageChunk` | Append to streaming assistant message |
| `.thoughtChunk` | Thinking panel text |
| `.toolCall` / `.toolCallUpdate` | Live tool call cards |
| `.permissionRequest` | Permission dialog in chat |
| `.exitPlanRequest` | Plan mode approval UI |
| `.questionRequest` | Ask-user question UI |
| `.modeChanged` | Agent / Plan / Yolo selector |
| `.contextUsage` | Token usage indicator |
| `.availableCommands` | Slash command autocomplete |
| `.schedulerActivity` | Update the scheduled-tasks mirror (`ChatStore.scheduledTasks`) |
| `.error` | Error banner |

### Agent modes

`AgentMode`: `.agent`, `.plan`, `.yolo` — synced from process to `ChatStore.currentMode`.

### Model switching

`session/set_model` RPC. Failures set `modelSwitchError` / `modelSwitchNeedsNewSession` on both `GrokProcess` and `ChatStore`.

---

## ChatStore

**File:** `Services/ChatStore.swift` — `@Observable @MainActor`

One `ChatStore` per live session tab. Owns a `GrokProcess`.

### Key published state

| Property | Purpose |
|----------|---------|
| `messages` | Chat history (`Message` model) |
| `connectionState` | Mirrors `GrokProcess.state` |
| `isStreaming` / `isGrokking` | Turn in progress |
| `currentModel` / `availableModels` | Model picker (from ACP + custom models) |
| `currentMode` | agent / plan / yolo |
| `pendingPermissions` | Tool permission prompts |
| `pendingExitPlan` / `pendingQuestions` | Plan / ask-user flows |
| `fileAttachments` | Composer chips; hidden chips are excluded from the prompt |
| `imageAttachments` | Pasted/dropped images sent as ACP `image` (vision) content blocks |
| `authRequiredMessage` | Login banner text |
| `grokSessionId` | `process.sessionId` — persisted for resume |

### Lifecycle methods

| Method | When |
|--------|------|
| `prepare(workspace:)` | Lazy restore — set workspace, no process spawn |
| `start(workspace:resumeSession:)` | Full start + optional resume |
| `restartProcess(resumeSessionID:)` | Build `GrokLaunchOptions`, spawn process, inject MCP |
| `reloadConfiguration()` | Settings changed — restart with new MCP/env |
| `startNewSession()` | Fresh grok session (same project) |
| `resumeSession(_:)` | Load existing grok session id |
| `shutdown()` | Stop process (app update / prepare for shutdown) |
| `retryConnection()` | Restart after CLI update |
| `send(_:)` | User message → ACP prompt (attachments become plain paths under `Attached file(s):`, not `@` reads) |
| `compactContext()` | Sends `/compact` from the context-usage popover (no-op while streaming) |

### Composer input helpers

- **`@` file mentions** — typing `@` shows a fuzzy file picker (`FileMentionMatch` / `FileMentionFilter` / `FileMentionIndex` in `Services/FileMention.swift`; popover `FileMentionListView`). The index enumerates workspace files (cap 2000, skips `.git`/`node_modules`/`.build`/etc.) off the main thread on workspace change; selecting inserts `@<relative-path> `.
- **Image paste / drop** — pasted or dropped images (png/jpeg/gif/webp) attach as **vision** content, not path chips. Detection + MIME mapping in `Services/ImageAttachment.swift` (`ImageAttachmentSupport`); `GrokProcess.send(_:images:)` appends ACP `image` blocks (`PromptImageContent`). Non-image files still attach as plain paths. Chips: `ImageChipBar`.
- **Inline media** — assistant/`/imagine` output with image/video paths or markdown image URLs renders inline via `InlineMediaParser` (`Services/InlineMedia.swift`) → `MarkdownBlock.media` → `InlineMediaView` (NSImage / AsyncImage / AVKit `VideoPlayer`, link fallback).
- **Context popover** — `ContextUsageIndicator` (in `ChatView.swift`) is a button opening a popover with token used/limit (`ContextUsageFormatter`) and a **Compact** button (`ChatStore.compactContext`). Billed USD isn't in ACP, so tokens only.
- **Workflow run cards** — `WorkflowRunsCard` (`ComposerViews.swift`) shows live `workflowRuns` with phase/progress, agent-budget bar (`WorkflowRun.budgetFraction`), and Pause/Resume/Stop wired to existing `ChatStore.pause/resume/stopWorkflowRun` (`/workflow pause|resume|stop`).

### `restartProcess` — what gets injected

On every (re)start, `ChatStore`:

1. Loads **permission settings** from `GrokSettingsKeys` (UserDefaults).
2. Loads **applied** browser + computer use settings.
3. Installs bundled **skills** to `~/.grok/skills/` if features enabled.
4. Starts external browser if browser tools enabled (CDP mode).
5. Builds MCP list:
   - `AgentBrowserService.browserMCPConfig(settings:)` → `grokbuild-browser`
   - `ComputerUseService.computerUseMCPConfig(settings:)` → `grokbuild-computer-use`
6. Resolves the **session agent** via `GrokAgentProfiles.launchArgument(for:)` → `GrokLaunchOptions.agent` (`--agent`).
7. Passes model from the **active tab** (`SavedSessionRecord.model`), with grok-session and project-default fallbacks.

### Per-tab model + per-project reasoning effort

**Model** is **per session tab** (`SavedSessionRecord.model` in `GrokBuild.sessionLayout.v2`), matching grok's per-ACP-session `session/set_model`. Changing model in the composer updates only the active tab and posts `.liveSessionModelChanged` → `persistSessionLayout()`. Tab switch calls `bindTabSession` + `syncTabModelToLiveProcessIfNeeded()` — it does **not** overwrite from sibling tabs, and a missing saved model is ignored so workspace/app fallbacks still apply.

**Project default model** (`WorkspaceAgentSettings.model`) seeds **new** tabs only (and legacy tabs without a saved per-tab model). It is **not** updated when you change model in chat.

**Session agent** is also **per session tab** (`SavedSessionRecord.agent`). Each tab launches with its own `--agent` (`ChatStore.effectiveAgentSelection`): an explicit per-tab override when set, otherwise the global default `grokbuild.selectedAgent` (Settings → Agents). The chat status bar shows an **agent pill** (`ChatView.agentStatusPill`) whose menu lists the built-in Default option (`GrokAgentProfiles.builtInOptions`) plus agents discovered for the workspace; picking one calls `ChatStore.setSessionAgent` → **restarts that tab's grok** (agents can only change at launch) and posts `.liveSessionAgentChanged` → `persistSessionLayout()`. A tab that has not been overridden follows the global default live (so changing the default and restarting adopts it); overridden tabs keep their choice. Only overridden tabs persist a value (`ChatStore.persistedAgentSelection`).

**Reasoning effort** stays **per project** (`WorkspaceAgentSettings.reasoningEffort`):

- Loaded via `loadWorkspaceReasoningEffort()` on prepare/start; tab switch syncs effort only via `syncWorkspaceReasoningEffortFromStorage()`
- `restartProcess` reads `workspaceReasoningEffort` for `--reasoning-effort` (never the global key directly)
- The global `grokbuild.reasoningEffort` (Settings → Permissions → "Default reasoning effort") is only a **seed for new/untouched projects**: `ChatStore.resolveReasoningEffort(saved:globalDefault:)` = saved per-project value (incl. explicit "Default") if present, else the global default. Do not add a second effort editor elsewhere — the Models pane no longer has one.

### Session selection persistence

`grokbuild.sessionSelections.v1` — per **grok session id**: saved mode + model backup when resuming by grok id (e.g. Sessions browser).

---

## Multi-session model (`ContentView`)

**File:** `ContentView.swift` — root orchestrator.

### Core types

```swift
ContentView.LiveSession {
    id: UUID              // Stable tab id (persisted)
    store: ChatStore      // One GrokProcess inside
    workspace: Workspace
    title: String         // Sidebar label
    grokSessionID: String? // For lazy resume after LRU teardown
}
```

### LRU connection cap

| Constant | Value | Behavior |
|----------|-------|----------|
| `maxConnectedSessions` | 4 | Max live `grok agent stdio` processes |
| `recentSessionOrder` | MRU list | Drives eviction |

**Lazy restore at launch:** `restorePersistedSessions()` rebuilds `LiveSession` shells (titles, grok ids, disk transcripts) but only **starts the selected session's process**. Others resume on first `selectSession` via `ensureSessionStarted`. Launch selection uses `SessionRestorePolicy`: prefer the saved `selectedSessionID` when it has a **restorable transcript** (in-memory or `SessionMessageStore` user/assistant rows — stale-fallback system notes alone do not count); otherwise pick the MRU tab in that workspace with a transcript, then fall back to grok-id-only tabs. `recentSessionOrder` is rebuilt from saved `lastAccessed` timestamps at launch. Resumed sessions with no local transcript yet skip the project welcome screen (`ChatStore.isResumedSessionTab`). Stale grok session ids fall back to `session/new` with a system note (`GrokSessionLoadError`); wording reflects whether a local transcript was preserved.

**Transcript auto-repair:** When a tab's `SessionMessageStore` transcript is empty (or has no user/assistant rows) but the tab still has a `grokSessionID`, `SessionTranscriptRecovery` reads grok's on-disk `~/.grok/sessions/{encoded-cwd}/{grokSessionID}/chat_history.jsonl` via `GrokSessionTranscriptImporter` and persists imported user/assistant text. `encodeWorkspacePath` matches grok's layout: `%2FUsers%2F…%2Fproject` with **no** trailing `%2F`. Runs during `restorePersistedSessions` / `selectSession` (`ChatStore.restorePersistedMessages(for:grokSessionID:workspace:)`). Skips synthetic `<system-reminder>`-only rows and non-text session-update types. Stale-fallback-only tabs are not treated as restorable transcripts.

**Eviction:** `enforceConnectionCap()` stops processes for sessions beyond MRU cap (keeps selected + busy sessions).

### Session persistence flow

```
selectSession / send / close
    → persistSessionLayout()
    → SessionLayoutStore.saveSessions(SessionLayoutSnapshot)
```

`SavedSessionRecord`: `id`, `workspaceID`, `grokSessionID`, `title`, `model`, `lastAccessed`.

Sidebar shows max `SessionLayoutStore.maxSidebarSessions` (10) per project; older sessions in **Browse Sessions**.

### Active store routing

| Selection | Chat UI binds to |
|-----------|------------------|
| Session selected | `activeStore` = that session's `ChatStore` |
| No session | `placeholderStore` (empty state) |

### Bootstrap sequence

```
.onAppear → bootstrap() → restorePersistedSessions()
    → rebuild LiveSession array from disk (+ SessionMessageStore transcripts)
    → rebuild recentSessionOrder from lastAccessed
    → SessionRestorePolicy.restoreSelectedSessionID
    → selectSession (reloads transcript if needed)
    → ensureSessionStarted (spawn process if grokSessionID set)
```

---

## Workspaces & projects

**File:** `Services/WorkspaceStore.swift`, `Models/Workspace.swift`

A **workspace** = one folder on disk (`Workspace.path`). Multiple sessions can belong to one workspace.

| Operation | Method |
|-----------|--------|
| Add project | `WorkspaceStore.add` — dedupes by resolved path |
| Remove | `WorkspaceStore.remove` — also clears agent settings |
| Pin / reorder | `pin` / `unpin` / `moveWorkspaces` → `SessionLayoutStore` workspace layout |
| Pick folder | `WorkspacePicker` sheet |

Display name: `workspace.displayName` (custom `name` or folder basename).

---

## Persistence (UserDefaults)

**Domain:** `~/Library/Preferences/com.grokbuild.app.plist` (standard UserDefaults).

Do **not** commit exported plist files from repo root (`.gitignore`).

### Keys reference

| Key | Store | Contents |
|-----|-------|----------|
| `GrokBuild.projects.v1` | `WorkspaceStore` | `[Workspace]` JSON |
| `GrokBuild.sessionLayout.v2` | `SessionLayoutStore` | Session records, order, selection, expanded/hidden, **`pinnedSessionIDs`** (sidebar session pins; max `SessionLayoutStore.maxPinnedSessions`) |
| `GrokBuild.sessionMessages.v1` | `SessionMessageStore` | Per live-session-tab chat transcript (`[Message]` JSON by session UUID); saved on `.liveSessionMessagesChanged` (user send + turn complete) and during full `persistSessionLayout(saveMessages: true)` passes such as app quit via `.grokBuildPrepareForShutdown` |
| `GrokBuild.workspaceLayout.v1` | `SessionLayoutStore` | Pin order, workspace order, **`agentSettingsByWorkspace`** |
| `grokbuild.sessionSelections.v1` | `ChatStore` | Per grok session id: mode |
| `grokbuild.permissionMode` | `GrokSettingsKeys` | CLI permission mode |
| `grokbuild.sandboxProfile` | | Sandbox profile string |
| `grokbuild.reasoningEffort` | | Default reasoning effort (settings UI) |
| `grokbuild.noMemory` | | Legacy `--no-memory` flag key (superseded by `grokbuild.memoryEnabled`; no longer written by the UI) |
| `grokbuild.memoryEnabled` | `GrokSettingsKeys` | Cross-session memory toggle (Settings → **Memory**). `true` → `--experimental-memory`, `false` → `--no-memory`. Default off |
| `grokbuild.disableWebSearch` | | `--disable-web-search` |
| `grokbuild.noSubagents` | | `--no-subagents` |
| `grokbuild.allowRules` / `denyRules` | | Newline-separated `--allow` / `--deny` rules |
| `grokbuild.selectedAgent` | `GrokSettingsKeys` | **Default** session agent for **new** tabs (empty = grok default; otherwise a discovered agent name). Per-tab overrides live in `SavedSessionRecord.agent`. |
| `grokbuild.steerByDefault` | `GrokSettingsKeys` | Steer the running turn by default on mid-turn send (Settings → App). Default off |
| `grokbuild.privacyMode` | `GrokSettingsKeys` | Display-only Privacy Mode (Settings → App). Redacts project paths/names and session titles in the UI; never mutates persisted data |
| `grokbuild.soundOnUnfocusedFinish` | `GrokSettingsKeys` | Chime when a turn finishes and the app is unfocused (Settings → App). Default off |
| `grokbuild.browser.*` | `BrowserSettingsStore` | Draft browser settings (agent-browser CLI: runtime mode, CDP URL, profile, external app) |
| `grokbuild.browser.applied.*` | | **Applied** settings used at process start |
| `grokbuild.computerUse.*` | `ComputerUseSettingsStore` | Draft computer use settings |
| `grokbuild.computerUse.applied.*` | | **Applied** settings used at process start |
| `grokbuild.customModelProviders` | `ProviderStore` | Reusable custom model providers (UserDefaults) |
| `GrokBuild.cursorBridge.managedEnabled` | `CursorBridgeSettingsKeys` | Auto-set when Cursor provider is installed; starts the bundled sidecar on launch when a key is saved (not a Settings toggle) |
| `grokbuild.updates.autoCheckEnabled` | `UpdateSettingsStore` | Background update checks |
| `grokbuild.updates.dismissedVersion` | | Skipped GrokBuild version |
| `grokbuild.updates.dismissedCLIVersion` | | Skipped grok CLI version |
| `grokbuild.updates.lastCheckDate` | | Last check timestamp |

### External files (not UserDefaults)

| Path | Purpose |
|------|---------|
| `~/.grok/config.toml` | Custom model tables plus `[models].default`; GrokBuild-owned `grokbuild_*` model metadata keys; custom subagent roles (`[subagents.roles.*]`) |
| `~/.grok/prompts/<name>.md` | Instruction bodies for custom subagent roles (referenced by `prompt_file`) |
| `~/.grok/skills/` | Installed skills (bundled skills copied by installers) |
| `~/.grokbuild/computer-use/` | Cursor MCP helper binaries |
| `~/Library/Application Support/GrokBuild/Secrets/cursor-api-key` (0600) | Cursor API key for the managed bridge (`CursorBridgeKeychain`; migrates/deletes legacy Keychain item to avoid ad-hoc re-sign prompts) |
| `~/Library/Application Support/GrokBuild/cursor-bridge-workspace/` | Scratch cwd for the managed Cursor SDK sidecar |
| `~/Library/Application Support/GrokBuild/Updates/` | Downloaded app update zips |
| `~/Library/Application Support/GrokBuild/instance.pid` | Single-instance lock |

---

## Feature subsystems

### Browser control

| Piece | Location |
|-------|----------|
| Settings | `SettingsView` → `.browser` tab; keys in `BrowserSettings.swift` |
| Service | `AgentBrowserService.swift` — agent-browser CLI, CDP, external browser launch |
| MCP | Name: `grokbuild-browser`; config from `browserMCPConfig` |
| Skill | `Resources/Skills/grokbuild-browser-control/` + `grokbuild-grok-web/` → `BrowserSkillInstaller` (installs both when browser tools enabled) |
| Presets | `BrowserPreset` (e.g. `.grokCom`) — one-click runtime/session-name setup in `BrowserSettings.swift`, applied from the Browser pane |
| Chat UI | Status pill in `ChatView` (composer chrome). Menu offers on/off toggle, **runtime choice** (managed ↔ existing Chromium), and Open Browser Settings |

**Backend:** the bundled `agent-browser` CLI exposed to grok as an stdio MCP server (`grokbuild-browser`). Managed Chromium vs external browser (Chrome/Brave/Edge/Arc) via CDP URL.

**agent-browser tools (via MCP):** `browser_open_url`, `browser_snapshot`, `browser_click_ref`, etc.

**grok.com web:** drive grok.com via browser tools to reach web-only features (Imagine, skills, connectors), then continue locally with Computer Use — see `grokbuild-grok-web` skill.

### Agents

| Piece | Location |
|-------|----------|
| Default (new sessions) | `SettingsView` → `.agents` tab (viewer + "Default agent for new sessions" picker → `grokbuild.selectedAgent`) |
| Per-session override | `ChatView.agentStatusPill` → `ChatStore.setSessionAgent` (persisted in `SavedSessionRecord.agent`) |
| Discovery | `GrokCLIService.listAgents(cwd:)` → `GrokAgentInfo` (parses `agents` from `grok inspect --json`); loaded lazily by `ChatStore.loadDiscoveredAgentsIfNeeded` for the pill |
| Built-in options | `GrokAgentProfiles.builtInOptions` (Default only) — shared by Settings + pill |
| Selection → launch | `ChatStore.effectiveAgentSelection` → `GrokAgentProfiles.launchArgument(for:)` → `--agent` |
| **Custom subagents (roles)** | `SettingsView` → `.agents` tab "Custom subagents" section (`SubagentRoleEditor`) → `SubagentRoleStore` writes `[subagents.roles.*]` in `~/.grok/config.toml` + prompt files |

The app stays thin: grok owns agents/personas. GrokBuild surfaces discovered agents and lets the user pick one by name; `""` = grok's default agent (no `--agent`). Agent is **per session tab** (see *Per-tab model + session agent*): the global setting is the default for **new** sessions; each open session can override it from the status-bar pill, which restarts that session's grok.

**Custom subagents (roles).** grok owns subagent orchestration (the main agent delegates to subagents that run in parallel, gated by `--no-subagents`). GrokBuild adds a thin CRUD editor for **roles** — `[subagents.roles.<name>]` tables in `~/.grok/config.toml` with `model` (empty = inherit the parent session's model) and a `prompt_file`. `SubagentRole` + `SubagentRoleStore` (`CustomModelSettings.swift`) mirror `CustomModelStore`: minimal targeted TOML edits that preserve every other section and unmanaged role keys (for example `default_capability_mode`), plus the role's instruction written to `~/.grok/prompts/<name>.md`. Relative `prompt_file` values are resolved from the user's home directory to match grok's documented `.grok/prompts/...` examples. Names matching grok's built-in subagents (`general`, `general-purpose`, `explore`, `plan`, `vision`, `verify`, `computer`) are rejected. Roles are a *separate* concept from the read-only discovered agents list (`grok inspect --json` does not report roles), but custom role names are offered under **Run as custom role** in the Settings default-agent picker and the chat agent pill menu; choosing one there runs the whole session as that role rather than spawning a child subagent. grok's `/agents` TUI manager is a pager builtin not exposed over `grok agent stdio`, so editing the config file is how GrokBuild manages them.

### Scheduled tasks

grok owns scheduling (`scheduler_create` / `scheduler_list` / `scheduler_delete`, surfaced to users via the `/loop` slash command). GrokBuild does **not** call these tools directly — the ACP surface is prompt-only — so it **mirrors** them by observing tool-call activity.

| Piece | Location |
|-------|----------|
| Model + parsing | `ScheduledTaskStore.swift` — `ScheduledTask`, `SchedulerToolParsing` (detect/parse scheduler `session/update` payloads), `ScheduledTaskTracker` (accumulates list, correlating `tool_call` rawInput with completing `tool_call_update` rawOutput) |
| ACP event | `GrokProcess` yields `AcpEvent.schedulerActivity(payload:)` for any `tool_call`/`tool_call_update` whose `_meta."x.ai/tool".name` starts `scheduler_` (or rawOutput `type` starts `scheduler`) |
| Store | `ChatStore.scheduledTasks` (updated from `schedulerActivity`); actions `refreshScheduledTasks()` (drives `scheduler_list`), `createScheduledTask(interval:prompt:)` (sends `/loop`), `cancelScheduledTask(_:)` (drives `scheduler_delete`) — all via prompts, so they cost a turn |
| Chat UI | `ChatView.tasksStatusPill` — lists tasks (interval + prompt + next fire), Cancel per task, Refresh Tasks |

`scheduler_list` output is authoritative (replaces the mirror); create/delete update it incrementally. It only reflects activity seen in the live session — tasks made in the grok TUI or another session appear after a refresh. Schedules fire only while the session's grok process is alive (LRU-capped).

**Wire caveats (verified live, grok 0.2.93):** the completing `tool_call_update` carries `rawOutput` but no `_meta`, and `rawOutput.type` is CamelCase (`SchedulerList`), so detection matches `_meta` name **or** a case-insensitive `rawOutput.type` prefix. The `/loop` slash command is handled by the CLI and emits **no** scheduler tool call, so the pill updates on **Refresh** (or when grok schedules via its tool, e.g. natural-language requests).

### Background tasks (richer Tasks pill)

Extends the Tasks pill beyond scheduled `/loop` tasks to mirror background shells, monitors, and subagents observed via ACP.

| Piece | Location |
|-------|----------|
| Model + parsing | `BackgroundTaskStore.swift` — `BackgroundActivity`, `BackgroundToolParsing`, `BackgroundTaskTracker` |
| ACP event | `GrokProcess` yields `AcpEvent.backgroundActivity(payload:)` for `run_terminal_command` (when `background` in rawInput), `monitor`, `spawn_subagent`, `kill_command_or_subagent`, `get_command_or_subagent_output`, plus scheduler tools |
| Store | `ChatStore.backgroundActivities` (also keeps `scheduledTasks` in sync) |
| Chat UI | `ChatView.tasksStatusPill` — sections: Scheduled, Background commands, Monitors, Subagents |

### Rhai workflows (distinct from skill chips)

grok's **Rhai workflow engine** (`.grok/workflows/`, `/workflow`, `/workflows`) is separate from **skill slash commands** (`/design`, `/review`, …) shown as composer chips.

| Piece | Location |
|-------|----------|
| Config toggle | `WorkflowsConfigStore` — `[workflows] enabled` in `~/.grok/config.toml` (shared with grok TUI); `SettingsView` → `.workflows` (`WorkflowsSettingsPane`); posts `.workflowsConfigChanged` |
| Runs mirror | `WorkflowRunStore.swift`, `ChatStore.workflowRuns`, `AcpEvent.workflowActivity` |
| Saved scripts | `SavedWorkflowStore.swift`, `SavedWorkflowsPanel.swift` |
| Chat UI | `ChatView.workflowsStatusPill` — runs, saved workflows, deep research, Open Workflow Settings |

### Session goals (`/goal`)

| Piece | Location |
|-------|----------|
| Parsing | `ComposerModels.GoalCommand` — supports `--budget N` on set |
| State | `ChatStore.goalState` (`SessionGoalState` with optional `budget`) |
| UI | `GoalBanner`, `SetGoalSheet` in `ComposerViews.swift`; top-bar session menu |

### Fork session

| Piece | Location |
|-------|----------|
| Launch | `GrokLaunchOptions.forkSession` + `newSessionID` → `--fork-session` / `--session-id` |
| Store | `ChatStore.startForked(workspace:fromSessionID:)` |
| UI | `ContentView.forkCurrentSession()` → new tab; `ChatView` session menu **Fork session** |

### Prompt queue + Steer (mid-turn)

While `ChatStore.isStreaming`, composer sends enqueue to `ChatStore.promptQueue`; drained automatically on turn complete. Badge + menu in `ChatView` composer (`Steer into current turn` when streaming, `Send now`, `Remove`). `sendQueuedPromptNow` refuses while streaming and re-inserts the prompt if deliver fails so queued work is not dropped. Mid-turn steer/queue folds file/image chip notes into the text via `consumeComposerAttachments` and clears the chips so they cannot stick to a later prompt (vision pixels are text-noted only on that path — ACP image blocks apply to non-streaming sends).

**Steer** injects a prompt into the *running* turn without cancelling it (grok never cancels on new input). `SteerDecision.resolve(isStreaming:steerByDefault:explicitSteer:)` (in `GrokCLIService.swift`) is the pure decision; `ChatStore.steerRunningTurn` / `steerQueuedPromptNow` append the user message and call `GrokProcess.steer(_:)` (fire-and-forget `session/prompt`, id untracked). The **Steer by default** app setting (`GrokSettingsKeys.steerByDefault`, Settings → App) makes a mid-turn composer send steer instead of queue.

### Session status + unread badges

`SessionActivityStatus` (`Services/SessionStatus.swift`): `idle` / `working` / `needsInput` / `finishedUnread` / `error`, resolved by the pure `SessionStatusResolver.resolve(SessionStatusInputs)`. `ChatStore.activityStatus(hasUnreadCompletion:)` feeds `SidebarSession.status` (dot badge in `SessionSidebarRow`). Unread is tracked in `ContentView` (`unreadSessionIDs` / `lastSeenStreaming` / `lastSeenMessageCounts`) via `BackgroundSessionUnread.shouldMark`: prefer streaming `true → false` on `.liveSessionMessagesChanged` (assistant placeholder is created at turn start, so message count often does not grow on completion); focusing (`selectSession`) clears unread.

### Turn-completion sound

`TurnCompletionSound` (`Services/TurnCompletionSound.swift`) — optional chime when a turn finishes and GrokBuild is not the active app. Pure rule `shouldPlay(enabled:appActive:)`; `playIfNeeded()` reads live `NSApp.isActive`. Toggle: `GrokSettingsKeys.soundOnUnfocusedFinish` (Settings → App). Called from `ChatStore.finishPrompt` on success.

### Privacy Mode

`PrivacyMode` (`Services/PrivacyMode.swift`) — display-only redaction for screenshots/screen shares. Toggle: `GrokSettingsKeys.privacyMode` (Settings → App → **Privacy Mode**). Views that redact (`SidebarView` rows, `ChatView` project label, `SessionsBrowserPanel`) observe the key via `@AppStorage` and call `redactPath` / `redactLabel` so the UI updates immediately when the toggle changes. Persisted titles, paths, and transcripts are never rewritten.

### Session polish (sidebar + rewind)

Sidebar session context menu (`SidebarView`): rename, pin/unpin session (`SessionLayoutSnapshot.pinnedSessionIDs`, sorted above unpinned in `ContentView.visibleSessionIDs`), mark unread/read, duplicate (new empty tab with “(copy)” title), clear transcript (`ChatStore.clearTranscript`), close. Project menu includes **New Worktree Session…** (`onCreateWorktree` → `GitCheckoutSheet` with create focus). Linked worktrees show a **WT** badge via `GitService.isWorktree(at:)` (`.git` is a file). Chat-only **Rewind to Here…** on each message (`MessageBubble` context menu → confirmation) truncates the transcript with `ChatStore.rewind(to:)` (no file restore).

### Doctor + onboarding

`DoctorReport` (`Services/DoctorReport.swift`) maps `DoctorInputs` (CLI found, version, auth, config.toml, Browser/CU enabled, Node.js for the Cursor bridge, managed Cursor bridge reachable) to `DoctorCheck` rows (pure). `DoctorSheet` (`Views/DoctorSheet.swift`) collects the inputs live (`GrokCLIService.locateGrokCLI` / `versionDisplayLine`, `GrokAuthProbe`, `CursorBridgeRuntime.probeNode`, `CursorBridge.probeManaged`) and offers remediations — install the grok CLI (docs link), `grok login` (opens Terminal), and Node.js install (Homebrew Terminal command or nodejs.org) when the Node check warns. Opened via `.openDoctorRequested` (Settings → App → **Open Doctor…**).

### `/btw` aside

Sending `/btw` sets `pendingBtw`; the next assistant reply is captured in `ChatStore.btwAsideText` and shown via `BtwAsideBanner`.

### Session dashboard

`SessionDashboardPanel.swift` — groups live tabs by needs-input / working / idle / failed. Opened from chat top bar; `ContentView` owns `dashboardEntries`.

### Share session

When `/share` is advertised: session menu → `ChatStore.shareSession()`; URL parsed from assistant reply (`ShareURLParser`) and copied to pasteboard. `pendingShareURLCapture` is cleared if send fails (including async process send failure) so a later unrelated URL is not captured.

### Create skill / Imagine

When advertised: session menu **Create skill…** sheet → `/create-skill`; `ImagineSlashCommands` chips + sheet → `/imagine`.

### Compatibility layers

| Piece | Location |
|-------|----------|
| Config | `CompatConfigStore` — `[compat.cursor|claude|codex] enabled` in config.toml |
| Discovery | `GrokCLIService.listExternalCompat()` from `grok inspect --json` |
| UI | `SettingsView` → `.compatibility` (`CompatibilitySettingsPane`) |

### Memory (cross-session)

grok owns memory storage, indexing, search, and first-turn injection ([`13-memory.md`](https://docs.x.ai/build/features/memory)). GrokBuild stays thin: it flips the launch flag, browses the files read-only, and appends "Remember" notes.

| Piece | Location |
|-------|----------|
| Toggle | `SettingsView` → `.memory` tab (`MemorySettingsPane`), key `grokbuild.memoryEnabled` |
| Launch flag | `GrokLaunchOptions.experimentalMemory`; `GrokMemoryFlag.argument(noMemory:experimentalMemory:)` resolves the single flag; `ChatStore.restartProcess` sets `experimentalMemory: memoryEnabled`, `noMemory: !memoryEnabled` |
| Files | `MemoryStore.swift` — enumerate `~/.grok/memory/` (global `MEMORY.md`, `<slug-hash>/MEMORY.md`, `<slug-hash>/sessions/*.md` newest-first); `readContents`, `deleteSessionFile` (session-only guard), `appendGlobalNote` (+ pure `appendingNote`), `revealInFinder` |
| Browser UI | `MemoryBrowserPanel.swift` — grouped list + read-only preview; copy path / reveal / delete session log (with confirm) |
| Chat UI | `ChatView.memoryStatusPill` — **shown only while memory is enabled** (hidden when off; label is just "Memory"): Browse Memory Files…, Remember… (writes global note via `ChatStore.remember`), Open Memory Settings |

**Enable/disable is a launch flag, app-scoped** (not `config.toml`), so the grok TUI is unaffected. `--no-memory` has absolute priority in grok, so the app never emits both flags.

**ACP limitation (verified live, grok 0.2.93):** enabling memory registers the read tools `memory_search`/`memory_get` and automatic first-turn recall, but `/remember`, `/flush`, `/dream`, `/memory` are **TUI pager builtins** and are **not** exposed over `grok agent stdio`. So the app writes "Remember" notes by appending directly to global `MEMORY.md` (grok's file watcher reindexes them); flush/dream run **automatically** (session end / pre-compaction / dream gates) or in the grok TUI — the app does not surface buttons for them.

### Computer Use

| Piece | Location |
|-------|----------|
| Settings | `SettingsView` → `.computerUse` tab; keys in `ComputerUseSettings.swift` |
| Service | `ComputerUseService.swift` — agent-desktop discovery, permissions probe |
| MCP helper | **`GrokBuildComputerUseMCP/`** separate SPM executable (stdio MCP → `agent-desktop`) |
| MCP name | `grokbuild-computer-use` |
| Skill | `Resources/Skills/grokbuild-computer-use/` |
| Cursor bridge | `ComputerUseCursorInstaller` — copies helper, merges `~/.cursor/mcp.json` |

**Tools:** `computer_snapshot`, `computer_click`, `computer_type`, `computer_screenshot`, etc.

**Permissions:** macOS Accessibility; merged status from GrokBuild, helper, agent-desktop, CLI.

### Custom models

| Piece | Location |
|-------|----------|
| Settings | `SettingsView` → `.models`; `CustomModelStore`, `CustomModelSettings` |
| Persistence | Providers in UserDefaults; model entries written to **`~/.grok/config.toml`** |
| Metadata | GrokBuild-owned TOML keys (`grokbuild_context_tokens`, `grokbuild_supports_*`) drive UI hints only |
| Chat | Merged into `ChatStore.availableModels` via `mergeCustomModels()` |
| Cline Pass | Same **Fetch models** button as other providers (required before Add model); live list from `https://api.cline.bot/api/v1/ai/cline/recommended-models` (`clinePass` array, no API key) via `ProviderModelFetcher.fetchClinePassRecommended`. No hardcoded model table |
| Display names | Fetch → Add model sets `name` as **Provider + model** via `ProviderModelNaming` (e.g. `MiniMax M2.5`); Cline uses `Cline …`, Cursor uses `Cursor …` |
| Settings list order | Installed models, the default-model picker (after built-ins), the Add-model fetched picker, and the Agents role-editor model picker are **A–Z by Provider + model** (`CustomModelListOrdering`; computed from the provider + model id, not a slug stored in `name`; tie-break on id). `config.toml` table order is unchanged until the user saves for another reason |

**`api_backend` + `env_key` (depth).** `CustomModel` carries `apiBackend` (`ModelAPIBackend`: `chat_completions` / `responses` / `messages`; default omitted from TOML to keep files tidy) and `envKey` (`env_key` — grok reads the key from an env var instead of inline). Both round-trip through `CustomModelStore` and are editable in the model editor (Settings → Models). This is the shared path for BYOK and localhost bridges.

**Cursor bridge.** Installed like any other provider: Settings → Models → **1. Add Provider** → **Cursor** (`ProviderPreset.cursor`). Paste a Cursor API key (`CursorBridgeKeychain` → Application Support `Secrets/cursor-api-key`; config.toml keeps `api_key = "local"`), save/install, and GrokBuild enables `CursorBridgeRuntime` — bundled Node script `Resources/CursorBridge/cursor-openai-bridge.mjs` (`@cursor/sdk`) on `127.0.0.1:18787`. Auth for SDK calls uses process env `CURSOR_API_KEY` via `cursor-bridge-auth.mjs` (`resolveCursorApiKey`) — grok often sends the xAI session JWT as `Authorization: Bearer …` even with `api_key = "local"`; the bridge ignores that JWT (and placeholders) unless the Bearer token is a Cursor `crsr_…` key. On start it **fetches** the `/v1/models` catalog only; models are added the same way as other providers (**Fetch models** → **Add model**). Added models get `providerID = cursor`, table id `cursor-<slug>` (`CursorBridge.importID`), and display name like `Cursor Composer 2.5` (same “Provider + model” pattern as Cline) — not the catalog `owned_by` field. Catalog aliases `default` / `auto` / `auto-smart` are filtered out of Fetch / Add model. `CursorBridgeRuntime.reconcile` / orphan reattach avoid false “exited unexpectedly” after relaunch when port `18787` is still live — but only while a Cursor API key is still saved; clearing the key (or launching with none) stops owned + orphan listeners so the UI cannot show Running with a No key badge. Saving/installing the Cursor provider requires a key (Add/Save stays disabled otherwise); before persist and before `startIfNeeded` spawns/reattaches, `CursorBridgeRuntime.validateAPIKey` runs bundled `cursor-validate-key.mjs` (`Cursor.models.list`) and rejects bad keys without starting the sidecar. The bridge starts via **Save / Add Provider** (and on subsequent launches while the Cursor provider remains installed with a saved key). There is no separate “Enable on launch” toggle — removing the Cursor provider (or clearing the key) stops the sidecar. Packaging: `scripts/bundle-cursor-bridge.sh` (`npm install` against `registry.npmjs.org` into `Contents/Resources/CursorBridge`; soft-skips only when Node is missing/too old — npm/copy failures fail the build so Settings cannot ship without the sidecar). Requires Node ≥ 22.13 on the machine (`CursorBridge.NodeRequirement` + `CursorBridgeRuntime.probeNode`); Settings and Doctor surface a warning with **Install with Homebrew…** / **nodejs.org…** when missing or too old. Cursor IDE need not be open. Preference: `GrokBuild.cursorBridge.managedEnabled` (install/remove only). No external community-bridge detect/import. Inference-only: grok keeps its ACP tools. Cursor subscription/ToS is the user's responsibility. `[compat.cursor]` (rules/skills) and the Computer Use Cursor MCP are unrelated.

OpenAI-compatible provider URLs; not a replacement for grok-native models. Custom model metadata is a UI fallback: ACP-reported model names/context limits stay authoritative when the CLI provides them. Reasoning-effort support is **opt-out** — `grokbuild_supports_reasoning_effort` defaults to `true` for new models and for existing config.toml entries missing the key, so the effort control keeps showing until the user disables it. Models explicitly marked as not supporting reasoning effort do not receive `--reasoning-effort` at launch, and the composer hides the effort picker for them.

### Bundled desktop skill

`Resources/Skills/grokbuild-desktop/` — hints for agents working on GrokBuild itself (copied at build, not auto-installed).

`Resources/Skills/grokbuild-ship-pr/` — commit → push → PR → wait for CI/Copilot → address feedback loop (copied at build, not auto-installed). Cursor twin: `.cursor/skills/ship-pr/`.

### MCP config shape

`MCPServerConfig` → JSON for ACP `session/new`. Supports stdio (command + args + env) and http/sse transports.

---

## Settings system

**File:** `Views/SettingsView.swift` (large — search `SettingsTab`, pane struct names).

### Tabs (`SettingsTab`)

Ordered config-first (session config → capabilities → grok ecosystem/inspection → app). `.agents` is the default landing tab (generic Settings gear + initial state; `.app` when an update is pending).

The settings chrome uses a custom horizontal **scrollable** tab bar (`SettingsView.settingsTabBar`) instead of `TabView`’s compressing segmented control — full titles stay readable; the bar scrolls sideways in a narrow window and auto-scrolls the selected tab into view. Visited panes stay mounted in a `ZStack` (`SettingsTabKeepAlive`) so `@State` / `.task` are not reset when switching tabs.

| Tab | Pane | Data source |
|-----|------|-------------|
| `.agents` | Discovered agents + **default** session-agent picker (new sessions) + **custom subagent roles** CRUD | `listAgents`, `grokbuild.selectedAgent`, `SubagentRoleStore` |
| `.models` | Custom providers | `CustomModelStore` |
| `.permissions` | Session safety toggles | `GrokSettingsKeys` |
| `.memory` | Cross-session memory toggle + browser | `grokbuild.memoryEnabled`, `MemoryStore` |
| `.workflows` | Rhai workflows enable toggle | `WorkflowsConfigStore` → `[workflows] enabled` in config.toml |
| `.browser` | Browser tools | `BrowserSettingsStore` draft keys |
| `.computerUse` | Desktop automation | `ComputerUseSettingsStore` draft keys |
| `.mcpServers` | External MCP + health | `listMCPServers` |
| `.skills` | Discovered skills | `listSkills` |
| `.plugins` | Installed plugins | `listPlugins` |
| `.marketplace` | Marketplace sources + install | `listPlugins(includeAvailable:)`, `listAvailablePlugins` |
| `.compatibility` | Cursor/Claude/Codex compat toggles | `CompatConfigStore`, `listExternalCompat` |
| `.hooks` | Hooks list | `GrokCLIService.listHooks` |
| `.app` | App + CLI updates | `UpdateScheduler`, `UpdateSettingsStore` |

### Draft vs applied pattern

| Feature | Draft keys | Applied keys | When applied |
|---------|------------|--------------|--------------|
| Browser | `grokbuild.browser.*` | `grokbuild.browser.applied.*` | **Enable toggle** applies immediately; other fields via **Apply and Restart** |
| Computer Use | `grokbuild.computerUse.*` | `grokbuild.computerUse.applied.*` | Same pattern |

**Live Grok sessions read applied settings only** in `ChatStore.restartProcess` → `BrowserSettingsStore.loadApplied()` / `ComputerUseSettingsStore.loadApplied()`.

Changing settings that affect MCP → call `ChatStore.reloadConfiguration()` (restarts process).

Permissions tab (`GrokSettingsKeys`) apply on next `restartProcess` (no separate applied copy).

Each settings pane puts its own "Refresh"/action buttons **inline in the pane header**, not in a `.toolbar { }` modifier — a window-level `.toolbar` item declared on one tab's view leaks into the shared title bar and can persist after switching to a tab that declares no toolbar of its own (observed and fixed on `PluginsSettingsPane`). Don't reintroduce `.toolbar` on settings pane views; use an inline header button instead.

---

## In-app updates

Two parallel updaters — **GrokBuild app** (GitHub) and **grok CLI** (`grok update`). Same UI surfaces: menu bar, main-window banner, `UpdatePanel`.

| Service | Role |
|---------|------|
| `UpdateChecker.swift` | Detect: notarized GitHub releases; `grok update --check --json` |
| `UpdateScheduler.swift` | Background checks; cache; `hasActionableAppUpdate` / `hasActionableCLIUpdate` |
| `UpdateSettingsStore.swift` | Auto-check, skip/dismiss per version |
| `AppUpdater.swift` | Download, verify, install, relaunch |
| `GrokCLIUpdater.swift` | Run `grok update`, phases, re-check |
| `UpdateUI.swift` | Present panel; `restartLiveSessions()` |
| `UpdatePanel.swift` | AppKit UI for both updaters |
| `UpdateDebugSimulator.swift` | **DEBUG only** — simulate updates (compiled out of release) |

```mermaid
sequenceDiagram
    participant UI as GrokBuild_UI
    participant Sched as UpdateScheduler
    participant Check as UpdateChecker
    participant AppUp as AppUpdater
    participant CLIUp as GrokCLIUpdater
    participant CLI as grok_CLI
    participant Sessions as LiveSessions

    Sched->>Check: GitHub releases + grok update --check --json
    Check-->>Sched: cached app + CLI status
    Sched-->>UI: banner / menu / panel
    UI->>AppUp: downloadAndVerify / installAndRestart
    AppUp->>Sessions: .grokBuildPrepareForShutdown
    AppUp->>AppUp: ditto via grokbuild-install-update
    UI->>CLIUp: updateCLI()
    CLIUp->>Sessions: .grokBuildPrepareForShutdown
    CLIUp->>CLI: grok update
    CLIUp->>Check: re-check CLI version
    UI->>Sessions: .grokBuildRestartSessionsRequested
```

### App updates

| Step | Detail |
|------|--------|
| Detect | `checkAppRelease()` — newest **notarized** release from GitHub list |
| Notarized filter | Title `(Notarized)` or notes contain `properly code-signed and notarized`; unsigned ignored |
| Download | `GrokBuild-{tag}.app.zip` → `~/Library/Application Support/GrokBuild/Updates/` |
| Verify | `codesign` + `spctl`; Team ID must match installed app |
| Install | `scripts/grokbuild-install-update.sh` (bundled) — wait PID, `ditto`, `open` |
| Skip | `grokbuild.updates.dismissedVersion` |

### CLI updates

| Step | Detail |
|------|--------|
| Detect | `grok update --check --json` |
| Install | `grok update` via `GrokCLIService.updateGrokCLI()` |
| Safety | `.grokBuildPrepareForShutdown` before binary swap |
| Restart | **Restart Sessions** → `retryConnection()` on each live session |
| Skip | `grokbuild.updates.dismissedCLIVersion` |

### UI surfaces

- **Menu:** **Upgrade Available…** / **Check for Updates…** — refresh checks, then open `UpdatePanel` directly (whether or not updates are available)
- **Banner:** `UpdatesBanner` in `ContentView` — **Updates Available** opens `UpdatePanel`
- **Panel:** dual sections; mutual busy lock during install

### DEBUG simulate updates

Menu **Simulate Updates** (`#if DEBUG` only — use `make run-debug`, not `make run`): fake `99.0.0` pending updates and show the main-window banner only. Same discovery flow as real updates — open the update panel from the banner. Simulated app install relaunches GrokBuild without replacing the binary; simulated CLI updates never run `grok update`. **Clear Simulation** runs real checks.

---

## UI layout & panels

### Main window (`ContentView`)

Minimum size **1100×720** and default **1200×800** (`MainWindowLayout` via `AppDelegate`) — sized so sidebar, composer, and status pills stay readable. Composer fills the chat column (`composerMaxWidth` = infinity) — no mid-width 780pt cap. Project status row scrolls horizontally; Browser Tools / Computer Use pills are icon-only when configured (full label only for setup-needed).

```
┌─────────────────────────────────────────────────┐
│ UpdatesBanner (optional)                        │
├──────────────┬──────────────────────────────────┤
│ SidebarView  │  ChatView  │  PreviewPane (opt)  │
│ - projects   │  composer  │  diff review        │
│ - sessions   │  messages  │  commit / PR        │
├──────────────┴──────────────────────────────────┤
│ SettingsView (replaces chat when open)          │
└─────────────────────────────────────────────────┘
```

### Key views

| File | Role |
|------|------|
| `SidebarView.swift` | Project list, session list, pins, settings entry |
| `ChatView.swift` | Composer, messages, model/effort popover, workflow chips, goal banner, feature pills, empty/welcome state (quick-start chips + no-project CTA) |
| `ComposerViews.swift` | File chips, workflow chips, goal banner, plan/question cards |
| `GrokChatChrome.swift` | Shared session chrome |
| `RichMessageView.swift` / `MessageBubble.swift` | Markdown, thinking, tools, permissions. `RichMessageView` parses mermaid/LaTeX blocks; WKWebView embeds reload only when source changes, report a fixed height after load (avoids lazy-list layout loops), and inline `$…$` spans require math signals (not currency/`$PATH`). |
| `PreviewPane.swift` | Diff detection from assistant messages; apply/commit |
| `SessionBrowserView.swift` | Resume historical grok sessions; per-row **delete** + **Clear Empty** bulk cleanup (`GrokCLIService.deleteSession` + `SessionNameStore.removeName`) |
| `GitCheckoutSheet.swift` | Branch switch / worktree create |
| `WorkspacePicker.swift` | Add project folder |

### AppKit panels (not SwiftUI sheets)

| Panel | File | Style |
|-------|------|-------|
| About | `AboutPanel.swift` | `AboutStyle` metrics |
| Updates | `UpdatePanel.swift` | Same shared style |
| Sessions browser | `SessionsBrowserPanel.swift` | Optional AppKit host |

Shared metrics: `AboutStyle.swift` (icon size, fonts).

---

## Notifications

Defined in `ContentView.swift` (`extension Notification.Name`).

### General

| Name | Posted when | Handler |
|------|-------------|---------|
| `.grokStatusChanged` | Process state/auth change | `StatusBarController` icon + title |
| `.showMainWindowRequested` | Menu bar open | `AppDelegate.openMainWindow` |
| `.chooseWorkspaceRequested` | Add project | `ContentView` → picker sheet |
| `.newSessionRequested` | Menu new session | `ContentView.startNewSessionForCurrentProject` |
| `.sessionsRequested` | Browse sessions | Session browser sheet |
| `.stopGenerationRequested` | Stop shortcut | `ChatStore.stop` |
| `.focusInputRequested` | Focus composer | `ChatView` |
| `.retryConnectionRequested` | Menu bar retry when signed out | `ContentView` → `activeStore.retryConnection()` |
| `.openSettingsRequested` | Settings from App or status menu (⌘,) | `ContentView.openSettings` (`.app` tab when update pending, else `.agents`) |
| `.workspaceAgentSettingsChanged` | Reasoning effort saved | Sync effort to sibling sessions in project |
| `.liveSessionModelChanged` | Tab model changed in composer | `persistSessionLayout()` |
| `.liveSessionAgentChanged` | Tab session agent changed via pill | `persistSessionLayout()` |
| `.liveSessionMessagesChanged` | Messages updated | Sidebar title refresh |
| `.subagentRolesChanged` | Custom subagent roles saved in Settings | `ChatView` refreshes `cachedCustomSubagentNames` in the agent pill |
| `.openDoctorRequested` | Settings → App → Open Doctor… | `ContentView` presents `DoctorSheet` |

`GrokProcess.notifyStatus()` posts `.grokStatusChanged` **asynchronously on the main queue** so background CLI/IO threads never block waiting for the menu-bar observer (which is registered on `queue: .main`). `ChatStore.postStatusUpdate` runs on `@MainActor` and posts inline.

### Updates

| Name | Use |
|------|-----|
| `.grokBuildUpdateAvailable` | Actionable update found |
| `.grokBuildUpdateStateChanged` | Check finished or version skipped |
| `.grokBuildUpdaterPhaseChanged` | App download/install phase |
| `.grokBuildCLIUpdaterPhaseChanged` | CLI update phase |
| `.grokBuildPrepareForShutdown` | Stop all live sessions |
| `.grokBuildRestartSessionsRequested` | Reconnect after CLI update |
| `.grokBuildCLIUpdated` | CLI update succeeded |

**Convention:** post `.grokStatusChanged` with `userInfo: ["status": "ready"|"busy"|"error"|"starting"|"idle", "authenticated": Bool]`.

---

## Git integration

**File:** `Services/GitService.swift`

Used from sidebar status row and `GitCheckoutSheet`:

- List branches, checkout, create branch
- Worktree add/open (`ContentView.createWorktree` / project **New Worktree Session…**)
- `isWorktree(at:)` — true when `.git` is a file (linked worktree); drives the sidebar **WT** badge
- Shown in `ContentView` via `gitCheckoutRequest` sheet

Not a full git UI — thin wrapper over `git` CLI in workspace path.

---

## Build, test & release

```bash
make run       # release build + open .build/GrokBuild.app
make run-debug # debug build + open .build/GrokBuild.app (Simulate Updates menu)
make test      # swift test
make app       # dist/GrokBuild.app (unsigned packaging)
make install   # copy to /Applications
make release   # GitHub release via scripts/release.sh
```

| Script | Purpose |
|--------|---------|
| `scripts/build-macos-app.sh` | Assemble `.app` bundle, copy resources/skills |
| `scripts/release.sh` | Build, zip, DMG, `gh release create` |
| `scripts/notarize.sh` | Notarize signed app |
| `scripts/grokbuild-install-update.sh` | In-app replace + relaunch |

**SPM targets:** `GrokBuild` (app), `GrokBuildComputerUseMCP` (MCP helper), `GrokBuildTests`.

**Resources in bundle:** `Assets.xcassets`, three skill folders (`Package.swift` `resources:`).

**Release types:** `unsigned` (default tag push) vs `notarized` (manual CI / `make release RELEASE_TYPE=notarized`). Only **notarized** releases are offered by the in-app updater.

See `BUILDING.md` for signing, notarization, CI workflow.

---

## Common tasks → files

| Task | Start here |
|------|------------|
| **Composer, send, streaming** | `ChatView.swift`, `ChatStore.send`, `consumeOutput` |
| **Workflow slash chips** | `WorkflowSlashCommands` in `ComposerModels.swift`, `WorkflowChipBar` in `ComposerViews.swift`, `ChatView` composer |
| **Session goal banner** | `GoalBanner` in `ComposerViews.swift`, `ChatStore.goalState` + `/goal` helpers, `GoalCommand` in `ComposerModels.swift` |
| **Empty/welcome state, quick starts** | `ChatView.swift` (`welcomeState`, `noProjectState`, `QuickStartChip`), `QuickStartPrompt` in `ComposerModels.swift` |
| **ACP events / tool cards** | `GrokProcess` (`AcpEvent`), `RichMessageView` |
| **Permissions UI** | `ChatStore.pendingPermissions`, `MessageBubble` |
| **Model / effort picker** | `ChatView`, `ChatStore.setModel`, `applyReasoningEffort` |
| **Per-tab model** | `SavedSessionRecord.model`, `ChatStore.bindTabSession`, `.liveSessionModelChanged` |
| **Per-tab session agent** | `SavedSessionRecord.agent`, `ChatStore.setSessionAgent` / `effectiveAgentSelection`, `ChatView.agentStatusPill`, `.liveSessionAgentChanged` |
| **Per-project reasoning effort** | `SessionLayoutStore.saveAgentSettings`, `ChatStore.loadWorkspaceReasoningEffort` |
| **New / resume session** | `ChatStore.startNewSession`, `resumeSession`, `GrokProcess.loadSession` |
| **Sidebar sessions** | `ContentView` (`selectSession`, `persistSessionLayout`, LRU, pin/unread/duplicate/clear) |
| **Session pin / WT badge** | `SessionLayoutSnapshot.pinnedSessionIDs`, `GitService.isWorktree`, `SidebarView` |
| **Chat rewind / clear transcript** | `ChatStore.rewind(to:)`, `clearTranscript()`, message context menu in `ChatView` |
| **Privacy Mode** | `PrivacyMode.swift`, `GrokSettingsKeys.privacyMode`, Settings → App |
| **Session restore at launch** | `ContentView.restorePersistedSessions`, `SessionRestorePolicy`, `SessionTranscriptRecovery`, `ensureSessionStarted` |
| **Add/remove project** | `WorkspaceStore`, `WorkspacePicker` |
| **Browser tools** | `AgentBrowserService`, `BrowserSettingsStore`, settings `.browser` (agent-browser CLI over MCP) |
| **Session agent** | `GrokAgentProfiles`, `GrokCLIService.listAgents`, settings `.agents` |
| **Custom subagents (roles)** | `SubagentRole` / `SubagentRoleStore` (`CustomModelSettings.swift`), `SubagentRoleEditor` in `SettingsView`, `~/.grok/config.toml` `[subagents.roles.*]` + `~/.grok/prompts/` |
| **Scheduled tasks** | `ScheduledTaskStore.swift`, `ChatStore.scheduledTasks` + refresh/create/cancel, `ChatView.tasksStatusPill`, `AcpEvent.schedulerActivity` |
| **Background tasks** | `BackgroundTaskStore.swift`, `ChatStore.backgroundActivities`, `AcpEvent.backgroundActivity` |
| **Rhai workflows** | `WorkflowsConfigStore`, `WorkflowRunStore`, `SavedWorkflowStore`, `ChatView.workflowsStatusPill`, `.workflowsConfigChanged` |
| **Fork / share / queue** | `GrokLaunchOptions.forkSession`, `ChatStore.startForked`, `shareSession`, `promptQueue`, `btwAsideText` |
| **Dashboard** | `SessionDashboardPanel.swift`, `ContentView.dashboardEntries` |
| **Compat** | `CompatConfigStore`, `CompatibilitySettingsPane`, `listExternalCompat` |
| **Memory (cross-session)** | `MemoryStore.swift`, `MemoryBrowserPanel.swift`, settings `.memory`, `GrokMemoryFlag`, `ChatView.memoryStatusPill`, `ChatStore.remember`/`isMemoryEnabled` |
| **Computer Use** | `ComputerUseService`, `GrokBuildComputerUseMCP/main.swift`, `.computerUse` |
| **Voice control / mic entitlements** | `VoiceInputService`, `scripts/GrokBuild.entitlements`, `scripts/codesign-app-bundle.sh` (`device.audio-input` for Hardened Runtime) |
| **Custom models** | `CustomModelStore`, `CustomModelListOrdering`, `~/.grok/config.toml` |
| **Cursor bridge / api_backend** | `ProviderPreset.cursor`, `CursorBridge.swift`, `CursorBridgeRuntime.swift`, `CursorBridgeKeychain.swift`, `Resources/CursorBridge/`, `ModelAPIBackend` + `CustomModel.apiBackend/envKey`, Add Provider flow in `CustomModelsSettingsPane` |
| **Session status / steer / sound** | `SessionStatus.swift`, `SteerDecision` (`GrokCLIService.swift`), `ChatStore.steerRunningTurn`, `TurnCompletionSound.swift`, `SidebarSession.status` |
| **@ file mentions** | `Services/FileMention.swift`, `FileMentionListView`, `ChatView` (`mentionMatch`, `loadFileMentionIndex`) |
| **Image vision attachments** | `Services/ImageAttachment.swift`, `ChatStore.addImageAttachment`, `GrokProcess.send(_:images:)`, `ImageChipBar` |
| **Inline media preview** | `Services/InlineMedia.swift`, `MarkdownBlock.media`, `InlineMediaView` (`RichMessageView.swift`) |
| **Context usage popover** | `ContextUsageFormatter.swift`, `ContextUsageIndicator` + `ChatStore.compactContext` |
| **Workflow run cards** | `WorkflowRunsCard` (`ComposerViews.swift`), `WorkflowRun.budgetFraction/isActive`, `ChatStore.pause/resume/stopWorkflowRun` |
| **Doctor** | `DoctorReport.swift`, `DoctorSheet.swift`, `.openDoctorRequested` |
| **Settings tab** | `SettingsView` — search pane struct by tab |
| **MCP injection** | `ChatStore.restartProcess` → `browserMCPConfig` / `computerUseMCPConfig` |
| **Skill install** | `BrowserSkillInstaller`, `ComputerUseSkillInstaller` |
| **Diff review / apply** | `PreviewPane`, `ChatStore` diff detection on `Message.hasDiff` |
| **Menu bar / auth** | `StatusBarController`, `GrokAuthProbe`, `ChatStore.authRequiredMessage` |
| **Main window / single instance** | `AppDelegate` |
| **In-app updates** | `UpdateScheduler`, `UpdateChecker`, `AppUpdater`, `GrokCLIUpdater`, `UpdatePanel` |
| **Simulate updates (dev)** | `UpdateDebugSimulator`, `#if DEBUG` menu in `StatusBarController` |
| **About / version** | `AppVersion.swift`, `AboutPanel` |
| **Git branch/worktree** | `GitCheckoutSheet`, `GitService` |
| **Release / notarize** | `scripts/release.sh`, `.github/workflows/release.yml`, `BUILDING.md` |

---

## Tests

```bash
make test    # Tests/GrokBuildTests/
```

| File | Covers |
|------|--------|
| `SessionPersistenceTests.swift` | Layout/workspace persistence, per-tab model + per-tab session agent (record round-trip, default-follow vs explicit override) |
| `BrowserIntegrationTests.swift` | Browser MCP config, skill install, settings round-trip, external browser launch args, presets |
| `AgentsAndCapabilitiesTests.swift` | `GrokAgentProfiles` launch-arg mapping + built-in options/display names, `GrokAgentInfo` parsing, `SubagentRole` validation/suggested-name + `SubagentRoleStore` TOML parse/rewrite (instruction round-trip, relative prompt files, preserve unrelated content/unmanaged role fields, inherit-model omission) |
| `ScheduledTaskTests.swift` | Scheduler tool detection + `ScheduledTaskTracker` (list authoritative, create prompt-correlation, delete, casing tolerance) |
| `MemoryStoreTests.swift` | `MemoryStore` enumeration/grouping (global/workspace/session, newest-first), session-only delete guard, note appending; `GrokMemoryFlag` mapping + memory-enabled default in `AgentsAndCapabilitiesTests` |
| `ComputerUseIntegrationTests.swift` | Computer use MCP, Cursor installer, permissions |
| `QuickStartPromptTests.swift` | Empty-state quick-start prompt catalog (`QuickStartPrompt.defaults`) |
| `UpdateCheckerTests.swift` | Version compare, GitHub asset selection, CLI JSON parse, notarized filter |
| `GrokCLIUpdaterTests.swift` | Updater helpers / phase reset |
| `StatusBarMenuTests.swift` | `GrokStatus` string mapping, auth menu copy, update menu title helpers |
| `GrokAuthProbeTests.swift` | Launch-time auth probe: `~/.grok/auth.json` size check (present / empty / missing) |
| `MarkdownBlockParserTests.swift` | Inline-math heuristic and mermaid/LaTeX block parsing in `RichMessageView` |
| `CompetitiveUXTests.swift` | Session status resolution, steer-vs-queue decision, Cursor bridge (ports/URL/import/parse), Doctor report mapping, unfocused-finish sound rule, Privacy Mode redaction, worktree detection, chat rewind/clear, pinned-session layout decode |
| `CustomModelTests.swift` | (extended) `api_backend` + `env_key` TOML round-trip and `ModelAPIBackend.parse` defaults; Settings model list A–Z by Provider + model (`CustomModelListOrdering`) |

Prefer extending existing test files. Test pure logic without launching real `grok` when possible.

---

## Anti-patterns

| Don't | Do instead |
|-------|------------|
| Reimplement ACP, MCP protocol, or grok skills in Swift | Inject MCP configs; let CLI execute tools |
| Add `@main` to `GrokBuildApp.swift` | Keep `main.swift` + `AppDelegate` |
| Read draft browser/computer settings in `ChatStore` | Use `loadApplied()` at process start |
| Use `/releases/latest` for app updates | Use notarized release scan in `UpdateChecker` |
| Auto-run `grok update` silently | Explicit button + confirm in `UpdatePanel` |
| Store chat history in UserDefaults | Messages live in memory; only session *metadata* persists |
| Add an Xcode project | Stay on SwiftPM + Makefile |
| Commit without user request | Ask first |

---

## Related docs

| Doc | Use |
|-----|-----|
| `AGENTS.md` | Agent entry point (points here) |
| `README.md` | User-facing features |
| `BUILDING.md` | Signing, notarization, release CI |
| `.cursor/rules/` | Architecture, SwiftUI, CLI integration, AppKit panels |
| `.cursor/skills/grokbuild-*` | Dev workflow, release, CLI checks |
| `.cursor/skills/ship-pr/` | Commit → push → PR → CI/Copilot feedback loop (Cursor) |
| `GrokBuild/Resources/Skills/grokbuild-desktop/SKILL.md` | Hints for agents editing GrokBuild |
| `GrokBuild/Resources/Skills/grokbuild-ship-pr/SKILL.md` | Same ship-PR loop for grok agent sessions |
