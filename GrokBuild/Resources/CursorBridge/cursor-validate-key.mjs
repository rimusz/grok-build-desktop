#!/usr/bin/env node
/**
 * Validates CURSOR_API_KEY against the Cursor SDK before GrokBuild starts the bridge.
 * Exit 0 = ok, 1 = rejected/invalid, 2 = missing key / setup error.
 */
import { Cursor } from "@cursor/sdk";

const apiKey = (process.env.CURSOR_API_KEY || "").trim();
if (!apiKey) {
  console.error("Missing CURSOR_API_KEY");
  process.exit(2);
}

try {
  const models = await Cursor.models.list({ apiKey });
  if (!Array.isArray(models)) {
    console.error("Cursor API key was rejected (unexpected models response).");
    process.exit(1);
  }
  process.exit(0);
} catch (error) {
  console.error(describeError(error) || "Cursor API key was rejected.");
  process.exit(1);
}

function describeError(error) {
  const parts = [];
  let current = error;
  for (let depth = 0; current && depth < 4; depth += 1) {
    const message =
      current && typeof current === "object" && "message" in current
        ? String(current.message).trim()
        : String(current).trim();
    if (message && !parts.includes(message)) parts.push(message);
    const code = current && typeof current === "object" ? current.code : undefined;
    if (typeof code === "string" && code && !parts.includes(code)) parts.push(code);
    current = current && typeof current === "object" ? current.cause : undefined;
  }
  return parts.join(": ");
}
