---
name: grokbuild-grok-cli
description: Works with grok CLI integration in GrokBuild — auth state, version checks, session resume, permission settings, and bundled browser skill. Use when changing GrokProcess, GrokCLIService, UpdateChecker, or grok-related settings UI.
---

# Grok CLI in GrokBuild

## Boundaries

GrokBuild is a UI shell. Core agent behavior (ACP, MCP, skills, plan mode, subagents) stays in the `grok` CLI.

## Key APIs

```swift
// One-shot commands
try await GrokCLIService().run(["--version"])
await GrokCLIService.versionDisplayLine()

// Long-running agent
GrokProcess — grok agent … stdio, ACP events

// Updates
UpdateChecker.checkAppRelease()   // notarized GitHub releases only
UpdateChecker.checkGrokCLI()      // grok update --check --json
```

## Auth & status bar

- `GrokProcess.needsAuthentication` drives login banner and menu header.
- Post `.grokStatusChanged` with `status` and `authenticated` keys.
- Menu: "GrokBuild connected to grok cli" when authenticated.

## Permission settings

Stored in `UserDefaults` via `GrokSettingsKeys` — `allowRules`, `denyRules`, `permissionMode`, `selectedAgent`, etc. Passed to `GrokLaunchOptions` in `ChatStore`.

## Session agent (`--agent`)

- `grokbuild.selectedAgent` (Settings → **Agents**) → `GrokAgentProfiles.launchArgument(for:)` → `GrokLaunchOptions.agent` → `grok --agent`.
- `""` = grok default (no flag); `"grokbuild-web"` = bundled `Resources/Agents/grokbuild-web.md`; any other value = discovered agent name.
- Discover agents via `GrokCLIService.listAgents(cwd:)` (parses `agents` from `grok inspect --json`). Keep this thin — grok owns agents/personas.

## Browser backend

`BrowserBackendID` in `BrowserSettings.swift`:
- `grok-native` — grok's built-in `browser_tab` / `browser_network_details`; no MCP injected. `browserMCPConfig` returns nil; `nativeBrowserEnvOverrides` pins `CHROME_PATH` via `GrokLaunchOptions.envOverrides`. Version-gated by `GrokCapabilities.supportsNativeBrowserTools` (+ per-account `grok_build_access_gate`).
- `agent-browser` — bundled `agent-browser` CLI as an stdio MCP server (`grokbuild-browser`); managed/external Chromium over CDP.

## Bundled skills

Skills ship under `GrokBuild/Resources/Skills/` and install to `~/.grok/skills/` when features are enabled:
- `grokbuild-browser-control` — `BrowserSkillInstaller`
- `grokbuild-grok-web` — `BrowserSkillInstaller` (installed alongside browser-control when browser tools enabled; drives grok.com web features like Imagine/skills/connectors via browser tools)
- `grokbuild-computer-use` — `ComputerUseSkillInstaller`
- `grokbuild-desktop` — bundled only (GrokBuild self-hints)

Browser **quick presets** (`BrowserPreset` in `BrowserSettings.swift`) apply runtime/session-name/CDP settings for common targets (e.g. `.grokCom`).

## After changing CLI integration

Same session, before finishing:

1. **`make test`** — extend `UpdateCheckerTests`, integration tests, or service tests as appropriate.
2. **`ARCHITECTURE.md`** — GrokProcess/ACP flow, persistence keys, notifications, feature subsystem table.
3. **`README.md`** — if user-visible CLI/settings behavior changed.
4. **This skill** + `grok-cli-integration.mdc` — if APIs or update-check behavior changed.
5. **Bundled skill `SKILL.md`** — if install path, tools, or agent instructions changed.

## Workspace instructions

Per-project `AGENTS.md` in workspace roots is surfaced in the sidebar; this repo's root `AGENTS.md` applies when GrokBuild desktop is the workspace.
