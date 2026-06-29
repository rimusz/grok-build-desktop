---
name: grokbuild-grok-web
description: Drives grok.com web through Browser Control tools — chat, Imagine, skills, and connectors — then continues the task locally. Use when the user asks to use grok.com features that the grok CLI does not expose (Imagine, web-only skills/connectors), or to combine a grok.com web answer with local Computer Use/file work.
---

# GrokBuild grok.com Web

## When to use

Use this skill to reach **grok.com web features the `grok` CLI does not expose**:

- **Imagine** (image generation)
- **Web-only skills and connectors**
- Models or modes only available in the grok.com UI

For ordinary chat with grok, prefer the native GrokBuild session (the CLI already talks to grok via API). Driving the web UI for plain chat is wasteful. Use this skill only when you need something the web surface provides.

## Prerequisites

- Browser Tools enabled in Settings → Browser (see `grokbuild-browser-control`).
- A Chromium browser reachable by `agent-browser`:
  - **Managed runtime** — log into grok.com once in the managed browser profile.
  - **Existing Chrome** — point GrokBuild at a Chromium instance you start with remote debugging, using a separate profile so you can log into grok.com there.
- The agent must be logged into grok.com in the driven browser before automating it. Ask the user to log in if needed; do not automate the login, password, or MFA.

## Safe Workflow

1. `browser_open_url` → `https://grok.com`.
2. `browser_wait_for_load`, then `browser_snapshot` to read the current surface and get refs.
3. Find the composer textarea via the snapshot and `browser_type_ref` your prompt.
4. `browser_click_ref` the send button. `browser_wait_for_load` / wait for the response to appear.
5. `browser_snapshot` again to read the response. Re-snapshot whenever the page changes — grok.com is a dynamic SPA and refs shift between turns.
6. For **Imagine**: navigate to the Imagine surface, type the prompt, trigger generate, then `browser_screenshot` to capture the result.
7. For **skills/connectors**: snapshot the relevant UI, use refs to trigger them, then read the result.

Do not guess refs. Re-snapshot when anything looks stale.

## Combining with local work

This skill pairs with `grokbuild-computer-use` and local file/git tools. Typical orchestration:

- Ask grok.com web for something only it can do (e.g. generate an image with Imagine).
- Read/screenshot the result with `browser_*` tools.
- Continue locally: save the file, open it in Finder, edit code, run `git`, or drive a Mac app with `computer_*` tools.

Example: "Use Imagine on grok.com to make a hero image, save it to `~/Downloads/hero.png`, then open Finder there."

## Safety

- Do not automate login, passwords, MFA, passkeys, or account consent dialogs. Ask the user.
- You are acting as the logged-in user on grok.com. Confirm before posting, sending, deleting, or changing account settings.
- Prefer a separate browser profile so the automation account is isolated from the user's daily browser.
- Keep loops short: one action, observe, decide. Re-snapshot between steps.

## Useful First Tests

```text
Open grok.com in the browser, take a snapshot, and tell me whether it shows the chat composer or a login screen.
```

```text
On grok.com, ask "what is the capital of France", wait for the reply, and summarize it.
```
