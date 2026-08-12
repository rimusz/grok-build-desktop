/**
 * Resolve the Cursor SDK API key for the managed GrokBuild bridge.
 *
 * Grok's custom-model client often sends the xAI session JWT (or the placeholder
 * `local`) as `Authorization: Bearer …` even when config.toml has
 * `api_key = "local"`. The real Cursor user key is injected into the bridge
 * process as `CURSOR_API_KEY` — prefer that unless the client sends a `crsr_` key.
 */
export function resolveCursorApiKey({ authorizationHeader = "", envApiKey = "" } = {}) {
  const match = /^Bearer\s+(.+)$/i.exec(String(authorizationHeader || ""));
  const token = (match?.[1] || "").trim();
  if (token.startsWith("crsr_")) return token;
  return String(envApiKey || "").trim();
}
