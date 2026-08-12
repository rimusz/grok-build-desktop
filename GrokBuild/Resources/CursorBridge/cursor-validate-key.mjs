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
  const message =
    (error && typeof error === "object" && "message" in error && String(error.message)) ||
    String(error);
  console.error(message || "Cursor API key was rejected.");
  process.exit(1);
}
