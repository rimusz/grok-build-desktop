---
name: grokbuild-dev
description: Builds, runs, and tests the GrokBuild macOS SwiftPM app. Use when developing GrokBuild, running make targets, fixing build failures, or working on SwiftUI/AppKit UI in this repo.
---

# GrokBuild development

## Quick start

```bash
make run          # build release + launch via open
make test         # swift test
swift build       # debug build
xed .             # open Package.swift in Xcode (optional)
```

## Before UI work

1. Read `RTK.md` for file layout.
2. Prefer XcodeBuildMCP or `make` over ad-hoc `xcodebuild` (no `.xcodeproj`).
3. After Swift changes, run `swift build` or `make build`.

## Common tasks

| Task | Command |
|------|---------|
| Package .app | `make app` → `dist/GrokBuild.app` |
| DMG | `make dmg` |
| Clean | `make clean` |

## grok CLI dependency

App requires `grok` on PATH or at `~/.grok/bin/grok`. User must run `grok login`. Test CLI: `grok --version`.

## Architecture reminders

- Process: `GrokProcess` + `ChatStore`
- Workspaces: `WorkspaceStore`
- Menu bar: `StatusBarController` + `AppDelegate`
- Do not commit unless the user asks.
