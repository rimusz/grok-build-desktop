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

### Browser control
- Browser tools through [`agent-browser`](https://agent-browser.dev), exposed as MCP tools to Grok sessions.
- Use a managed automation runtime (a separate Chrome/Chromium profile) or attach to an existing Chromium browser (Chrome, Brave, Edge, Arc, or custom) over CDP.
- Installs a browser-control skill into your Grok skills folder when browser tools are enabled.

### Computer Use (desktop automation)
- Optional macOS desktop-control tools exposed to Grok through an app-managed MCP helper and [`agent-desktop`](https://github.com/lahfir/agent-desktop).
- `agent-desktop` ships bundled inside the app and shares GrokBuild's Accessibility permission — nothing to install.
- Configurable permission policy (Auto / Ask / Deny), optional screenshots, step and timeout limits, and named sessions.
- Installs a Computer Use skill into your Grok skills folder when enabled.
- Optional **Cursor integration**: install from Settings → Computer Use to copy the MCP helper and `agent-desktop` into `~/.grokbuild/computer-use/` and register `grokbuild-computer-use` in `~/.cursor/mcp.json`, so Cursor Agent gets the same `computer_*` tools in any workspace.

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
