---
name: grokbuild-desktop
description: Develops the GrokBuild macOS app in this repository. Use when editing Swift/SwiftUI code, Makefile packaging, release scripts, About/Update panels, or grok CLI integration in grok-build-desktop.
---

# GrokBuild Desktop (this repo)

## Read first

- `AGENTS.md` and `ARCHITECTURE.md` at the repository root
- `BUILDING.md` for packaging and release

## Build

```bash
make run
make test
```

SwiftPM target `GrokBuild`, macOS 26+. No Xcode project required.

## Where to change things

| Change | Location |
|--------|----------|
| Chat UI | `GrokBuild/Views/`, `ContentView.swift` |
| CLI process | `GrokProcess.swift`, `ChatStore.swift` |
| Menu bar / About | `StatusBarController.swift`, `AboutPanel.swift` |
| Updates | `UpdateChecker.swift`, `UpdatePanel.swift` |
| Version bump | `VERSION` |

## Rules

- Stay thin over the `grok` CLI — do not duplicate agent/MCP/skills logic in the app.
- Match `AboutStyle` for AppKit panels.
- Minimize diff scope; only commit when the user asks.
