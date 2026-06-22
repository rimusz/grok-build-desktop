# GrokBuild Desktop App

GrokBuild Desktop is a native SwiftUI macOS app for using the `grok` CLI as a desktop AI development environment.

It gives Grok a project-focused chat UI with persistent workspaces, resumable sessions, rich message rendering, diff review, settings for Grok CLI features, and optional browser-control tools. The app stays close to the CLI: GrokBuild launches and talks to `grok agent stdio`, while the CLI remains responsible for core capabilities such as ACP, MCP, skills, subagents, AGENTS.md instructions, permissions, and plan mode.

## Features

- Native macOS SwiftUI interface for `grok agent stdio`.
- Persistent project sidebar with pinned projects, session lists, session rename/close, and recent-session collapsing.
- Session browser for resuming existing Grok sessions from the current project.
- Streaming chat with Markdown rendering, thinking blocks, live tool activity, permission prompts, and question cards.
- Fixed two-line composer with command history, slash-command autocomplete, file attachments, and voice input.
- Model, mode, and context-usage controls directly in the composer.
- Git branch and worktree sheet from the chat status row.
- `Open in` menu for Finder, Cursor, VS Code, Terminal, iTerm, and Zed.
- Settings panes for plugins, marketplace plugins, MCP servers, browser tools, and permissions.
- Browser tools integration through `agent-browser`, with support for a managed browser runtime or an existing Chromium browser.
- Browser-control skill installation into the user's Grok skills folder when browser tools are enabled.
- Login-state detection with a helpful `grok login` banner.
- Dark-mode-first visual design.

## Install

Download the latest GrokBuild Desktop app from the [GitHub Releases page](https://github.com/rimusz/grok-build-desktop/releases).

After downloading, move `GrokBuild.app` to `/Applications` or run it from the extracted release folder.

### Running Unsigned Builds

Current release builds are not signed or notarized, so macOS Gatekeeper may block the app the first time you open it. You can allow it with one of these options:

1. Remove the quarantine attribute:

   ```bash
   xattr -cr /Applications/GrokBuild.app
   ```

2. **Right-click** `GrokBuild.app`, choose **Open**, then confirm **Open**. This bypasses the block for that app.
3. Open **System Settings -> Privacy & Security** and click **Open Anyway** next to the blocked app message.

## Development Requirements

- macOS 26+
- The `grok` CLI installed (usually at `~/.grok/bin/grok`)
- You must be logged in to the CLI (`grok login` in your terminal)

## To Build & Run (Minimal Setup)

You only need **Xcode Command Line Tools**:

```bash
xcode-select --install
```

This is sufficient for:

- Compiling the app (`swift build`)
- Creating the `.app` bundle and DMG
- Codesigning and notarization

### Quick commands

```bash
make build          # Build the release binary
make run            # Build + launch the menu bar app
```

## For Development (Recommended)

If you're going to edit the SwiftUI code, install the **full Xcode** IDE from the App Store.

**Why full Xcode is worth it:**
- SwiftUI Previews (live canvas) — this is the biggest advantage
- Much better debugging tools (view hierarchy, environment inspection, etc.)
- Smoother experience when working with complex SwiftUI views

You can still build from the terminal with `make` or `swift build` even with full Xcode installed.

## Other Required Tools

- `make` (pre-installed on macOS)
- The `grok` CLI (the app is just a UI frontend for it)

### Packaging

```bash
make app     # creates dist/GrokBuild.app
make dmg     # creates .app + DMG
```

The build process uses the menu bar icon from `GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset/`. It is automatically copied into the app bundle. (Project root PNGs are still supported as a fallback.)

### Optional tools (for distribution)

- A **Developer ID Application** certificate (for `make signed`)
- App Store Connect access for notarization

See [BUILDING.md](BUILDING.md) for full packaging, signing, and notarization instructions (including GitHub Actions).

## Building

See [BUILDING.md](BUILDING.md) for full instructions.

### Quick start

```bash
make build          # build the app
make run            # builds + launches the menu bar app
```

For signed + notarized builds:

```bash
make signed SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
make notarize NOTARY_PROFILE=AC_PASSWORD
```

The menu bar icon is in `GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset/`. The build process copies the appropriate PNGs into the app bundle. (Raw PNGs at the project root also work as fallback.)
