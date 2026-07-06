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

1. Read `ARCHITECTURE.md` for file layout.
2. Prefer `make` over ad-hoc `xcodebuild` (no `.xcodeproj`).
3. After Swift changes, run `swift build` or `make build`.

## Definition of done (every code change)

**Do not finish a task with code-only diffs.** Same session:

1. **`make test`** — must pass; add tests in `Tests/GrokBuildTests/` for behavior you changed.
2. **Computer Use** — required for **every** code change, not only SwiftUI view edits. `make run` to repackage/relaunch (not just `make build`), then drive the app (`snapshot` → navigate to affected state → `click`/`type` → `screenshot` when helpful). Default: **`user-grokbuild-computer-use` MCP**; fallback: `agent-desktop` directly or Orca `computer-use` CLI. Service/persistence changes still need a live check of the user-visible outcome.
3. **`ARCHITECTURE.md`** — update source map, persistence, notifications, or common tasks → files when structure/flow changes.
4. **`README.md`** — update when users would notice the change.
5. **`BUILDING.md`** — update when build/packaging/scripts change.
6. **Skills/rules** — update relevant `.cursor/skills/` or `.cursor/rules/` if workflow changed.

Full checklist: `.cursor/rules/docs-and-tests.mdc`.

## Common tasks

| Task | Command |
|------|---------|
| Package .app | `make app` → `dist/GrokBuild.app` |
| DMG | `make dmg` |
| Clean | `make clean` |
| Unit tests | `make test` |

## grok CLI dependency

App requires `grok` on PATH or at `~/.grok/bin/grok`. User must run `grok login`. Test CLI: `grok --version`.

## Architecture reminders

- Process: `GrokProcess` + `ChatStore`
- Workspaces: `WorkspaceStore` + `SessionLayoutStore`
- Menu bar: `StatusBarController` + `AppDelegate`
- Full map: `ARCHITECTURE.md`
- Do not commit unless the user asks.
