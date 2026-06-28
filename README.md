# GrokBuild Desktop App

GrokBuild Desktop is a native SwiftUI macOS app for using the [`grok`](https://grok.com) CLI as a desktop AI development environment.

It gives Grok a project-focused chat UI with persistent workspaces, resumable sessions, rich message rendering, diff review, full settings for Grok CLI features, optional browser-control tools, and optional macOS desktop automation. The app stays close to the CLI: GrokBuild launches and talks to `grok agent stdio`, while the CLI remains responsible for core capabilities such as ACP, MCP, skills, subagents, `AGENTS.md` instructions, permissions, and plan mode.

![GrokBuild Desktop app showing the project sidebar, chat UI, composer, and status bar menu](docs/images/grokbuild-app.png)

## Features

### Chat & sessions
- Native macOS SwiftUI interface for `grok agent stdio`.
- Streaming chat with Markdown rendering, thinking blocks, live tool activity, permission prompts, and question cards.
- Resumable sessions with a session browser for reopening existing Grok sessions in the current project.
- Diff review of file changes proposed during a session.

### Projects & workspaces
- Persistent project sidebar with pinned projects, per-project session lists, session rename/close, and recent-session collapsing.
- Git branch and worktree management from the chat status row.
- `Open in` menu for Finder, Cursor, VS Code, Terminal, iTerm, and Zed.

### Composer
- Fixed two-line composer with command history and slash-command autocomplete.
- File attachments and voice input (dictation).
- Model, mode, and context-usage controls inline in the composer.

### Models
- Add custom OpenAI-compatible models from your own providers (e.g. MiniMax and other OpenAI-compatible endpoints).
- Define reusable providers (base URL + shared API key) and fetch their available models directly in the app.
- Models are written to `~/.grok/config.toml` and become usable via `/model <id>`; supports setting a default model (up to 28 custom models).
- **Reasoning effort** for reasoning-capable models — pick effort (Minimal through Max) from the same composer model menu; each project remembers its own model and effort and restores them when you switch workspaces.

### Browser control
Let Grok drive a **Chromium browser** for web tasks (navigate, read pages, click, type, wait, screenshot, run JS) via `browser_*` MCP tools backed by [`agent-browser`](https://agent-browser.dev).
- **Managed runtime (default)** — GrokBuild installs and uses a separate automation Chrome/Chromium profile (`agent-browser install`); no CDP URL required.
- **Existing browser** — attach to Chrome, Brave, Edge, Arc, or another Chromium browser over CDP when you want Grok to use your own window.
- Enable in **Settings → Browser**, then **Apply and Restart Grok**; toggle quickly from the chat status bar (**Browser Tools On/Off**).
- Installs a `grokbuild-browser-control` skill into your Grok skills folder so the agent knows the workflow (snapshot → ref-based click/type).

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
- **MCP servers** — configure external Model Context Protocol servers and run health checks.
- **Permissions** — session safety toggles (disable memory, web search, or subagents for new sessions).

### App experience
- Menu bar app with built-in update checks for both GrokBuild and the `grok` CLI.
- Login-state detection with a helpful `grok login` banner.
- Dark-mode-first visual design.

## Install

Download the latest release from the [GitHub Releases page](https://github.com/rimusz/grok-build-desktop/releases), then move `GrokBuild.app` to `/Applications` (or run it from the extracted release folder).

### Requirements
- macOS 26 (Tahoe) or later
- The `grok` CLI installed (usually at `~/.grok/bin/grok`)
- Logged in to the CLI — run `grok login` in your terminal

### Opening unsigned builds

Current release builds are not signed or notarized, so macOS Gatekeeper may block the app the first time you open it. Allow it with any one of these:

1. **Right-click** `GrokBuild.app` → **Open**, then confirm **Open** (bypasses the block once).
2. Open **System Settings → Privacy & Security** and click **Open Anyway** next to the blocked-app message.
3. Remove the quarantine attribute:
   ```bash
   xattr -cr /Applications/GrokBuild.app
   ```

## Building from source

### Minimal setup

You only need **Xcode Command Line Tools**:

```bash
xcode-select --install
```

That is enough to compile the app, create the `.app` bundle and DMG, and codesign/notarize.

```bash
make build          # build the release binary
make run            # build + launch the menu bar app
make app            # create dist/GrokBuild.app
make dmg            # create the .app + DMG
```

### Recommended for SwiftUI work

If you plan to edit the SwiftUI code, install the **full Xcode** IDE from the App Store for:

- SwiftUI Previews (live canvas) — the biggest advantage
- Better debugging tools (view hierarchy, environment inspection)
- A smoother experience with complex SwiftUI views

You can still build from the terminal with `make` or `swift build` with full Xcode installed.

### Signing & notarization

```bash
make signed SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
make notarize NOTARY_PROFILE=AC_PASSWORD
```

Signing requires a **Developer ID Application** certificate, and notarization requires App Store Connect access. See [BUILDING.md](BUILDING.md) for full packaging, signing, and notarization instructions (including GitHub Actions).

### Notes

The menu bar icon lives in `GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset/` and is copied into the app bundle during the build (raw PNGs at the project root also work as a fallback).
