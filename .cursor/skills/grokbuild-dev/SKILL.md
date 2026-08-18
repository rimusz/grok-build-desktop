---
name: grokbuild-dev
description: Builds, runs, and tests the GrokBuild macOS SwiftPM app. Use when developing GrokBuild, running make targets, fixing build failures, or working on SwiftUI/AppKit UI in this repo.
---

# GrokBuild development

## Quick start

```bash
make run          # build release + launch via open
make test         # swift test + Cursor bridge auth node tests (when Node present)
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

`make run` / `make app` also run `scripts/bundle-cursor-bridge.sh` when Node ≥ 22.13 is available (installs `GrokBuild/Resources/CursorBridge` deps from `registry.npmjs.org` into the `.app`; copies `cursor-openai-bridge.mjs`, `cursor-bridge-auth.mjs`, `cursor-validate-key.mjs` — excludes `*.test.mjs`). Missing/old Node soft-skips; npm failures fail the build. Managed Cursor bridge UI: Settings → Models. Bridge SDK auth contract and Node requirement: `grokbuild-grok-cli` skill + `ARCHITECTURE.md`.

`make run` ad-hoc signs `.build/GrokBuild.app` unless `SIGN_IDENTITY` is set. Ad-hoc resign drops macOS Accessibility; the app re-prompts once per new CDHash when Computer Use is enabled. Prefer a Developer ID in `.env` for day-to-day `make run` so the trust entry sticks.

## grok CLI dependency

App requires `grok` on PATH or at `~/.grok/bin/grok`. User must run `grok login`. Test CLI: `grok --version`.

## Architecture reminders

- Process: `GrokProcess` + `ChatStore`
- Workspaces: `WorkspaceStore` + `SessionLayoutStore`
- Menu bar: `StatusBarController` + `AppDelegate`
- Full map: `ARCHITECTURE.md`
- Do not commit unless the user asks.
