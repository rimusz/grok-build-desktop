# GrokDeck

Native SwiftUI Mac app for the `grok` CLI.

## Requirements

- macOS 14+ (Sonoma or newer)
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

You can also run directly:

```bash
swift build -c release
./.build/release/GrokDeck
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
make app     # creates dist/GrokDeck.app
make dmg     # creates .app + DMG
```

The build process uses the menu bar icon from `GrokDeck/Resources/Assets.xcassets/MenuBarIcon.imageset/`. It is automatically copied into the app bundle. (Project root PNGs are still supported as a fallback.)

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

The menu bar icon is in `GrokDeck/Resources/Assets.xcassets/MenuBarIcon.imageset/`. The build process copies the appropriate PNGs into the app bundle. (Raw PNGs at the project root also work as fallback.)

## Features (current)
- Grok Build CLI features (subagents, skills, AGENTS.md, plan mode, ACP, MCP) are the core.
- Sidebar shows Project Instructions (AGENTS.md / CLAUDE.md loaded automatically by the CLI)
- Spawn & control grok via stdio (`--no-alt-screen`)
- Workspace folder picker + persistence
- Streaming chat
- Command history (↑ / ↓)
- Markdown rendering in assistant messages
- Diff detection + Preview pane
- One-click "Apply to Workspace" (uses `/usr/bin/patch`)
- Dark mode first
- Automatic detection of "not logged in" state + helpful "Run `grok login`" banner with one-click Terminal helper
- (hardcoded Agent Team / fixed personas removed)

## Next features

- Support `--permission-mode`, model selection
- Session resume / list sessions via `grok sessions`
- Per-hunk apply + 3-way merge UI
- Slash commands in input
- File tree sidebar synced with workspace
