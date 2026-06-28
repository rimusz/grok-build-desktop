# GrokBuild Desktop

Native SwiftUI macOS frontend for the `grok` CLI (`grok agent stdio`).

## Read first

@ARCHITECTURE.md — app map, data flow, persistence keys, feature subsystems, and **“common tasks → files”** lookup for new chats.

## Cursor in this repo

- Rules: `.cursor/rules/` (architecture, SwiftUI, grok CLI integration, AppKit panels)
- Skills: `.cursor/skills/` (dev workflow, release, grok CLI checks)

## Grok CLI in this repo

GrokBuild stays close to the CLI. Do not reimplement CLI features (ACP, MCP, skills, permissions, plan mode) in the app unless the UI truly needs a thin wrapper.

When changing app behavior that touches the CLI:

1. Prefer existing services: `GrokProcess`, `GrokCLIService`, `ChatStore`, `UpdateChecker`.
2. Feature subsystems have their own services: `AgentBrowserService` (browser tools), `ComputerUseService` (desktop automation via bundled `agent-desktop`), `CustomModelStore` (OpenAI-compatible models in `~/.grok/config.toml`).
3. Keep workspace/session state in `WorkspaceStore` and `SessionLayoutStore`.
4. Post status via `.grokStatusChanged` when auth or process state changes.
5. Bundled grok skills live in `GrokBuild/Resources/Skills/` (`grokbuild-browser-control`, `grokbuild-computer-use`, `grokbuild-desktop`) and are copied into the app bundle at build time.

## Code style

- Minimize diff scope; match surrounding Swift/SwiftUI conventions.
- AppKit panels (About, Updates) share `AboutStyle` metrics.
- Version strings: `VERSION` + `BUILD_NUMBER` files, surfaced through `AppVersion`.
- Build with `make run` or `swift build`; do not require an Xcode project.
