# GrokBuild Desktop

Native SwiftUI macOS frontend for the `grok` CLI (`grok agent stdio`).

## Read first

@ARCHITECTURE.md — app map, data flow, persistence keys, feature subsystems, and **“common tasks → files”** lookup for new chats.

## Cursor in this repo

- Rules: `.cursor/rules/` (architecture, SwiftUI, grok CLI integration, AppKit panels, **docs-and-tests**)
- Skills: `.cursor/skills/` (dev workflow, release, grok CLI checks)

## Grok CLI in this repo

GrokBuild stays close to the CLI. Do not reimplement CLI features (ACP, MCP, skills, permissions, plan mode) in the app unless the UI truly needs a thin wrapper.

When changing app behavior that touches the CLI:

1. Prefer existing services: `GrokProcess`, `GrokCLIService`, `ChatStore`, `UpdateChecker`.
2. Feature subsystems have their own services: `AgentBrowserService` (browser tools), `ComputerUseService` (desktop automation via bundled `agent-desktop`), `CustomModelStore` (OpenAI-compatible models in `~/.grok/config.toml`).
3. Keep workspace/session state in `WorkspaceStore` and `SessionLayoutStore`.
4. Post status via `.grokStatusChanged` when auth or process state changes.
5. Bundled grok skills live in `GrokBuild/Resources/Skills/` (`grokbuild-browser-control`, `grokbuild-computer-use`, `grokbuild-desktop`, `grokbuild-grok-web`) and are copied into the app bundle at build time.

## Code style

- Minimize diff scope; match surrounding Swift/SwiftUI conventions.
- AppKit panels (About, Updates) share `AboutStyle` metrics.
- Version strings: `VERSION` file, surfaced through `AppVersion`.
- Build with `make run` or `swift build`; do not require an Xcode project.

## Documentation, tests & Computer Use (required)

Every code change must ship with **updated documentation**, **tests**, and **Computer Use verification** in the same session — not as a follow-up.

1. **Tests** — run `make test`; add or extend `Tests/GrokBuildTests/` for new or changed behavior.
2. **Computer Use** — required for **every** code change (not only view files). `make run` to repackage/relaunch, then drive the running app via **`user-grokbuild-computer-use` MCP** (default), `agent-desktop` directly, or Orca's `computer-use` CLI. Reach the state your change affects and confirm it in the live UI (e.g. restored transcripts, settings, tab switches).
3. **ARCHITECTURE.md** — update for new services, persistence keys, notifications, subsystems, or flows (canonical app map).
4. **README.md** — update for user-visible features or install/requirements changes.
5. **BUILDING.md** / **scripts/README.md** — update for build, release, packaging, or script changes.
6. **Skills / rules** — update `.cursor/skills/` or `.cursor/rules/` when workflows or integration contracts change.
7. **Bundled skills** — update `GrokBuild/Resources/Skills/*/SKILL.md` when agent-facing skill behavior changes.

See `.cursor/rules/docs-and-tests.mdc` for the full checklist.
