# GrokBuild — quick reference

## What this is

Menu-bar macOS app wrapping `grok agent stdio`. SwiftPM executable target `GrokBuild`, macOS 14+, AppKit entry via `main.swift` + `AppDelegate`.

## Layout

| Area | Path |
|------|------|
| SwiftUI shell | `GrokBuild/ContentView.swift`, `GrokBuild/Views/` |
| CLI process + ACP | `GrokBuild/Services/GrokProcess.swift` |
| CLI commands | `GrokBuild/Services/GrokCLIService.swift` |
| Chat/session state | `GrokBuild/Services/ChatStore.swift` |
| Workspaces | `GrokBuild/Services/WorkspaceStore.swift` |
| Menu bar | `GrokBuild/StatusBarController.swift` |
| About / updates | `AboutPanel.swift`, `UpdatePanel.swift`, `AboutStyle.swift` |
| Version | `VERSION`, `BUILD_NUMBER`, `AppVersion.swift` |
| Packaging | `Makefile`, `scripts/build-macos-app.sh`, `scripts/release.sh` |

## Build

```bash
make run          # build + launch (uses open)
make test         # unit tests
make app          # dist/GrokBuild.app
make dmg          # dist/GrokBuild-macOS.dmg
make release      # local GitHub release via gh (see BUILDING.md)
```

Signing/notarization: copy `.env.example` → `.env`, then `make release RELEASE_TYPE=notarized`.

## grok CLI

- Binary search order: `GROK_CLI_PATH`, `~/.grok/bin/grok`, Homebrew paths, `PATH`.
- Version: `GrokCLIService.versionDisplayLine()` / `grok --version`.
- Updates: `UpdateChecker` (app GitHub release + `grok update --check --json`).
- Auth: `GrokProcess.needsAuthentication`; menu bar shows connected / not connected.

## UI patterns

- **About panel**: custom `NSPanel`, `AboutStyle` (396pt width, 64pt icon), fetches CLI version on open.
- **Update panel**: same visual language; no OK button; closable window.
- **Notifications**: `.showMainWindowRequested`, `.newSessionRequested`, `.grokStatusChanged`, etc. in `ContentView.swift`.

## Tests

`Tests/GrokBuildTests/` — run with `make test` or `swift test`.
