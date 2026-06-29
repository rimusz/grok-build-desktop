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

Stored in `UserDefaults` via `GrokSettingsKeys` — `allowRules`, `denyRules`, `permissionMode`, etc. Passed to `GrokLaunchOptions` in `ChatStore`.

## Bundled skills

Skills ship under `GrokBuild/Resources/Skills/` and install to `~/.grok/skills/` when features are enabled:
- `grokbuild-browser-control` — `BrowserSkillInstaller`
- `grokbuild-computer-use` — `ComputerUseSkillInstaller`
- `grokbuild-desktop` — bundled only (GrokBuild self-hints)

## After changing CLI integration

Same session, before finishing:

1. **`make test`** — extend `UpdateCheckerTests`, integration tests, or service tests as appropriate.
2. **`ARCHITECTURE.md`** — GrokProcess/ACP flow, persistence keys, notifications, feature subsystem table.
3. **`README.md`** — if user-visible CLI/settings behavior changed.
4. **This skill** + `grok-cli-integration.mdc` — if APIs or update-check behavior changed.
5. **Bundled skill `SKILL.md`** — if install path, tools, or agent instructions changed.

## Workspace instructions

Per-project `AGENTS.md` in workspace roots is surfaced in the sidebar; this repo's root `AGENTS.md` applies when GrokBuild desktop is the workspace.
