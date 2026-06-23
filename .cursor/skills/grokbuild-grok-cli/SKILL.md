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
UpdateChecker.checkAppRelease()
UpdateChecker.checkGrokCLI()
```

## Auth & status bar

- `GrokProcess.needsAuthentication` drives login banner and menu header.
- Post `.grokStatusChanged` with `status` and `authenticated` keys.
- Menu: "GrokBuild connected to grok cli" when authenticated.

## Permission settings

Stored in `UserDefaults` via `GrokSettingsKeys` — `allowRules`, `denyRules`, `permissionMode`, etc. Passed to `GrokLaunchOptions` in `ChatStore`.

## Bundled skill

Browser automation skill ships at `GrokBuild/Resources/Skills/grokbuild-browser-control/SKILL.md`. Installed to `~/.grok/skills/` by `BrowserSkillInstaller` when browser tools are enabled.

## Workspace instructions

Per-project `AGENTS.md` in workspace roots is surfaced in the sidebar; this repo's root `AGENTS.md` applies when GrokBuild desktop is the workspace.
