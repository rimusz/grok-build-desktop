---
name: grokbuild-browser-control
description: Guides GrokBuild browser automation through agent-browser MCP tools. Use when the user asks to open websites, inspect pages, click/type in a browser, use managed internal Chrome, attach to existing Chrome/Chromium, or debug browser-control setup.
---

# GrokBuild Browser Control

## Default Choice

Prefer the managed browser runtime unless the user explicitly asks to use an existing browser.

- Managed runtime means `agent-browser install` provides a separate automation Chrome/Chromium runtime.
- Existing Chrome means the user starts a Chromium-based browser with remote debugging and provides a CDP URL.
- Do not require a CDP URL for the managed runtime.

## Browser Tool Workflow

When the user asks to use a browser:

1. Use `browser_open_url` to navigate.
2. Use `browser_snapshot` to inspect page content and refs.
3. Use `browser_click_ref` and `browser_type_ref` for interactions by ref.
4. Use `browser_wait_for_load` after navigation or actions that change the page.
5. Use `browser_screenshot` when visual evidence is useful.
6. Use `browser_eval_js` only when snapshot/ref tools are insufficient.

Keep results concise. Summarize what changed or what was found; do not dump full DOM content.

## Managed Runtime

Use this path for normal browser tasks:

- Assume the browser is controlled through the app-managed MCP server.
- If the user wants to see the browser, tell them to enable `Show browser window while agents work` in Settings -> Browser, then Apply and Restart Grok.
- If browser tools are unavailable, ask the user to check Settings -> Browser for agent-browser readiness and browser tools enablement.

## Existing Chromium Browser

Use this only when the user asks to control their own browser instance or has configured a CDP URL.

Any Chromium-based browser can work if it exposes Chrome DevTools Protocol:

- Chrome
- Chromium
- Brave
- Edge
- Arc

The browser should be launched with remote debugging and a separate user data directory, for example:

```sh
/path/to/browser --remote-debugging-port=9222 --user-data-dir=/tmp/grokbuild-browser
```

Then use this CDP URL in Settings -> Browser -> Existing Chrome:

```text
http://127.0.0.1:9222
```

## Safety

- Do not automate passwords, MFA, account consent, payment, or destructive account actions without explicit user confirmation.
- Prefer a separate browser profile/user data directory.
- If a page is logged into a sensitive account, tell the user before interacting with private data.

## Quick Test Prompts

Good first tests:

```text
Open https://example.com in the browser and tell me the page title.
```

```text
Open https://news.ycombinator.com, take a snapshot, and summarize the first 5 links.
```

