# GrokBuild Desktop App

GrokBuild Desktop is a native SwiftUI macOS app for using the [`grok`](https://grok.com) CLI as a desktop AI development environment.

It gives Grok a project-focused chat UI with persistent workspaces, resumable sessions, rich message rendering, diff review, full settings for Grok CLI features, optional browser-control tools, and optional macOS desktop automation. The app stays close to the CLI: GrokBuild launches and talks to `grok agent stdio`, while the CLI remains responsible for core capabilities such as ACP, MCP, skills, subagents, `AGENTS.md` instructions, permissions, and plan mode.

![GrokBuild Desktop app showing the project sidebar, chat UI, composer, and status bar menu](docs/images/grokbuild-app.png)

## Features

### Chat & sessions
- Native macOS SwiftUI interface for `grok agent stdio`.
- Streaming chat with Markdown rendering, thinking blocks, live tool activity, permission prompts, and question cards.
- Guided empty state — a new session offers one-tap quick-start prompts (explain the project, find a bug, add tests, review changes), and a first launch with no projects shows an **Add Project** call-to-action.
- Resumable sessions with a session browser for reopening existing Grok sessions in the current project, including per-session delete and a one-click **Clear Empty** cleanup for unnamed, empty sessions.
- Diff review of file changes proposed during a session.
- Multi-tab sessions with lazy restore and an LRU cap on live Grok processes (see [ARCHITECTURE.md](ARCHITECTURE.md)).
- Empty or corrupted tab transcripts can be rebuilt from grok's on-disk `chat_history.jsonl` when a session id is still known.

### Projects & workspaces
- Persistent project sidebar with pinned projects, per-project session lists, session rename/close, and recent-session collapsing.
- Per-tab **model** — each session tab remembers its own model (matches grok per-session `session/set_model`). New tabs inherit the project default from Settings when set.
- Per-project **reasoning effort** — restored when you switch projects.
- Git branch and worktree management from the chat status row.
- `Open in` menu for Finder, Cursor, VS Code, Terminal, iTerm, and Zed.

### Composer
- Fixed two-line composer with command history and slash-command autocomplete.
- Workflow chips — one-tap shortcuts for curated slash commands (`design`, `implement`, `execute-plan`, `review`, `pr-babysit`, `code-review`) when the grok CLI advertises them over ACP.
- Session goal banner — when you set a goal with `/goal <objective>`, a banner above the composer shows the objective with **Status**, **Pause**/**Resume**, and **Clear** actions (`/goal status`, `/goal pause`, `/goal resume`, `/goal clear`).
- File attachments as plain paths (grok chooses how to read each file; avoids forced whole-file reads and binary failures).
- Voice control (dictation).
- Model, mode, and context-usage controls inline in the composer (model is per session tab).

### Models
- Add custom OpenAI-compatible models from your own providers (e.g. MiniMax and other OpenAI-compatible endpoints).
- Define reusable providers (base URL + shared API key) and fetch their available models directly in the app.
- Models are written to `~/.grok/config.toml` and become usable via `/model <id>`; supports setting a default model (up to 28 custom models).
- Add GrokBuild-only metadata for custom models: context-window size, image/thinking hints, and whether reasoning effort should appear for that model.
- **Reasoning effort** for reasoning-capable models — pick effort (Minimal through Max) from the composer model menu; it stays available for custom models unless you turn it off in their settings. Effort is saved **per project**; set the starting default for new projects in **Settings → Permissions → Default reasoning effort**.

### Browser control
Let Grok drive a **Chromium browser** for web tasks (navigate, read pages, click, type, wait, screenshot, run JS) via `browser_*` MCP tools backed by [`agent-browser`](https://agent-browser.dev), configured in **Settings → Browser**:
- **Managed runtime (default)** — GrokBuild installs and uses a separate automation Chrome/Chromium profile (`agent-browser install`); no CDP URL required.
- **Existing browser** — attach to Chrome, Brave, Edge, Arc, or another Chromium browser over CDP when you want Grok to use your own window.
- Enable in **Settings → Browser**, then **Apply and Restart Grok**. The chat status bar pill gives a quick **Browser Tools On/Off** toggle plus a one-click **runtime switch** (managed ↔ existing Chromium) that restarts Grok for you.
- **Quick Presets** — one-click setups for common targets, e.g. **grok.com (existing Chrome)** configures external Chrome with a dedicated `grok-com` session name and a visible window so you can log in once and let the agent drive grok.com web features (Imagine, web-only skills/connectors) that the CLI doesn't expose.
- Installs `grokbuild-browser-control` and `grokbuild-grok-web` skills into your Grok skills folder so the agent knows the workflow (snapshot → ref-based click/type) and how to combine grok.com web with local Computer Use.

### Computer Use (desktop automation)
Let Grok control **native macOS UI** — apps, menus, dialogs, Finder, Safari, and system windows — via `computer_*` MCP tools backed by [`agent-desktop`](https://github.com/lahfir/agent-desktop).
- Tools include accessibility snapshots, ref-based click/type, keyboard shortcuts, waits, optional screenshots, and listing apps/windows.
- `agent-desktop` is **bundled in GrokBuild** and reuses the app's Accessibility permission (grant once in **Settings → Computer Use**).
- Enable in settings or from the chat status bar (**Computer Use On/Off**); optional **Allow screenshot tool** (needs Screen Recording).
- Safety controls: action policy (Auto / Ask / Deny), step and timeout limits, accessibility-first automation (physical mouse off by default).
- Installs a `grokbuild-computer-use` skill; use Computer Use for macOS apps, Browser control for websites in Chromium.
- Optional **Cursor integration** — **Install for Cursor** copies the MCP helper to `~/.grokbuild/computer-use/` and registers `grokbuild-computer-use` in `~/.cursor/mcp.json` so Cursor Agent gets the same tools globally.

### Grok CLI integration
- **Hooks** — inspect automation hooks discovered from Grok, Cursor, Claude, project, and plugin sources.
- **Plugins** — manage installed Grok plugins and add trusted plugin sources.
- **Marketplace** — browse available plugins and manage marketplace sources.
- **Skills** — view user, project, compatibility, and plugin skills available to Grok.
- **Agents** — browse the agents Grok discovers for the project and choose the **default agent for new sessions** (grok's default, or a discovered agent by name), passed through as `grok --agent`. Each open session also has its **own** agent picker in the chat status bar — switch it there to run a different agent per session; changing it restarts that session's Grok.
- **MCP servers** — configure external Model Context Protocol servers and run health checks.
- **Permissions** — session safety toggles (disable memory, web search, or subagents for new sessions).

### App experience
- Menu bar item plus main window (Dock icon); single-instance app with status bar quick actions (open/new session, settings ⌘,, updates, sign-in recovery).
- Status menu header shows grok CLI sign-in state at launch (based on `~/.grok/auth.json` from `grok login`); when signed out, **Run `grok login` in Terminal…** and **Retry Connection** appear in the menu. A running session's `.grokStatusChanged` updates override the launch hint.
- Menu bar icon shows a colored status dot (ready / working / starting / error) with accessibility labels; the grok mark still adapts to light/dark menu bars.
- **Settings…** (⌘,) in the status menu and App menu opens Settings in the main window.
- Built-in update checks for **GrokBuild** and the **`grok` CLI** (background on launch + daily; manual via **Check for Updates…** — opens the updates panel directly).
- **In-app GrokBuild updates** — for signed + **notarized** releases only: background check shows a main-window banner; click **Updates Available** to open the panel, download `GrokBuild-{tag}.app.zip`, verify signature, **Install and Restart** (via bundled install helper).
- **In-app grok CLI updates** — banner → updates panel → **Update grok CLI** runs `grok update`; live sessions stop during the upgrade and can be restarted afterward.
- **Settings → App** — installed versions, auto-check toggle, pending update status.
- Login-state detection with a helpful `grok login` banner and menu-bar sign-in recovery actions.
- Dark-mode-first visual design.

## Install

Download a release from the [GitHub Releases page](https://github.com/rimusz/grok-build-desktop/releases), then move `GrokBuild.app` to `/Applications` (or run it from the extracted folder).

**Recommended:** choose a release titled **`(Notarized)`** — no Gatekeeper warnings, and the in-app updater only offers **notarized** builds (unsigned releases on GitHub are ignored by the updater even if they are newer).

Release assets are versioned, e.g. `GrokBuild-v0.1.10.app.zip` and `GrokBuild-v0.1.10-macOS.dmg`.

### Requirements
- macOS 26 (Tahoe) or later
- The `grok` CLI installed (usually at `~/.grok/bin/grok`)
- Logged in to the CLI — run `grok login` in your terminal

### Opening unsigned builds

Some releases are published as **`(Unsigned)`** for development. macOS Gatekeeper may block them the first time you open:

1. **Right-click** `GrokBuild.app` → **Open**, then confirm **Open** (bypasses the block once).
2. Open **System Settings → Privacy & Security** and click **Open Anyway** next to the blocked-app message.
3. Remove the quarantine attribute:
   ```bash
   xattr -cr /Applications/GrokBuild.app
   ```

Unsigned builds do not receive in-app GrokBuild upgrade offers. Use a notarized release for one-click updates, or build from source.

## Building from source

### Minimal setup

You only need **Xcode Command Line Tools**:

```bash
xcode-select --install
```

That is enough to compile the app, create the `.app` bundle and DMG, and codesign/notarize.

```bash
make build          # build the release binary
make test           # run unit tests
make run            # build release + launch from .build/GrokBuild.app
make run-debug      # build debug + launch — includes menu **Simulate Updates**
make app            # create dist/GrokBuild.app
make dmg            # create the .app + DMG
```

See [BUILDING.md](BUILDING.md) for packaging, signing, notarization, and GitHub releases.

### Recommended for SwiftUI work

If you plan to edit the SwiftUI code, install the **full Xcode** IDE from the App Store for:

- SwiftUI Previews (live canvas) — the biggest advantage
- Better debugging tools (view hierarchy, environment inspection)
- A smoother experience with complex SwiftUI views

You can still build from the terminal with `make` or `swift build` with full Xcode installed:

```bash
xed .          # open Package.swift in Xcode
```

### Signing & notarization

```bash
cp .env.example .env   # optional: SIGN_IDENTITY, NOTARY_PROFILE
make signed SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
make notarize NOTARY_PROFILE=AC_PASSWORD
make release RELEASE_TYPE=notarized
```

Signing requires a **Developer ID Application** certificate, and notarization requires App Store Connect access. Full details: [BUILDING.md](BUILDING.md).

### Developer documentation

| Doc | Purpose |
|-----|---------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | **Start here** — app structure, data flow, persistence, updates, common tasks → files |
| [AGENTS.md](AGENTS.md) | Agent/copilot entry point |
| [BUILDING.md](BUILDING.md) | Build, sign, notarize, release CI |

Debug builds (`make run-debug`) include a menu-bar **Simulate Updates** submenu for testing the update UI without publishing releases. It is compiled out of release builds (`make run`, `make app`, GitHub releases).
