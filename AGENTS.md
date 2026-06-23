# GrokBuild Desktop

Native SwiftUI macOS frontend for the `grok` CLI (`grok agent stdio`).

## Read first

@RTK.md

## Cursor in this repo

- Rules: `.cursor/rules/` (architecture, SwiftUI, grok CLI integration, AppKit panels)
- Skills: `.cursor/skills/` (dev workflow, release, grok CLI checks)

## Grok CLI in this repo

GrokBuild stays close to the CLI. Do not reimplement CLI features (ACP, MCP, skills, permissions, plan mode) in the app unless the UI truly needs a thin wrapper.

When changing app behavior that touches the CLI:

1. Prefer existing services: `GrokProcess`, `GrokCLIService`, `ChatStore`, `UpdateChecker`.
2. Keep workspace/session state in `WorkspaceStore` and `SessionLayoutStore`.
3. Post status via `.grokStatusChanged` when auth or process state changes.
4. Bundled grok skill for browser tools: `GrokBuild/Resources/Skills/grokbuild-browser-control/`.

## Code style

- Minimize diff scope; match surrounding Swift/SwiftUI conventions.
- AppKit panels (About, Updates) share `AboutStyle` metrics.
- Version strings: `VERSION` + `BUILD_NUMBER` files, surfaced through `AppVersion`.
- Build with `make run` or `swift build`; do not require an Xcode project.
