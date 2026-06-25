---
name: grokbuild-computer-use
description: Guides GrokBuild desktop automation through Computer Use MCP tools. Use when the user asks to inspect or control native macOS apps, menus, dialogs, forms, Safari, Finder, or system UI through agent-desktop.
---

# GrokBuild Computer Use

## Default Choice

Use Computer Use for native desktop UI, system dialogs, app menus, Finder, Safari, and workflows that are not reachable through Browser Control.

If both Browser Control and Computer Use are available:

- Prefer `browser_*` tools for websites in a Chromium browser.
- Prefer `computer_*` tools for macOS apps, Safari, system UI, and cross-app workflows.

## Safe Workflow

When the user asks to use the computer:

1. Start with `computer_snapshot`.
2. Use refs from the snapshot for `computer_click`, `computer_type`, `computer_get`, and `computer_wait`.
3. Use `computer_screenshot` only when visual evidence is needed or the accessibility tree is insufficient.
4. If the UI is dense, request a skeleton snapshot, then drill down with the root ref.
5. If a ref is stale or ambiguous, re-run `computer_snapshot` and retry with the new ref.

Do not guess coordinates when a snapshot ref is available.

## Permissions

Computer Use depends on macOS permissions:

- Accessibility is required for snapshots and app actions.
- Screen Recording is required for screenshots.

If tools report missing permissions, ask the user to open Settings -> Computer Use and grant the requested macOS permission.

## Safety

- Ask before destructive UI actions, account changes, payment actions, or sending messages externally.
- Do not automate passwords, MFA prompts, passkeys, or consent dialogs without explicit user instruction.
- Prefer step-by-step actions over long autonomous loops.
- If an action is blocked by policy, explain the local setting that blocked it.

## Useful First Tests

```text
List open apps using Computer Use and tell me which app is focused.
```

```text
Take a Computer Use snapshot of Finder and summarize the visible controls.
```
