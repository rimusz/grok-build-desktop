#!/usr/bin/env node
/**
 * Minimal OpenAI-compatible /v1 bridge for GrokBuild.
 *
 * Uses @cursor/sdk with CURSOR_API_KEY. Speaks GET /v1/models and
 * POST /v1/chat/completions so grok's [model.*] base_url can point at localhost.
 * Inference-only helper: keep workspace scratch + ask-style instructions.
 */
import { Agent, Cursor } from "@cursor/sdk";
import crypto from "node:crypto";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { mkdir } from "node:fs/promises";
import { resolveCursorApiKey } from "./cursor-bridge-auth.mjs";

const host = process.env.CURSOR_BRIDGE_HOST || "127.0.0.1";
const port = parseInt(process.env.CURSOR_BRIDGE_PORT || "18787", 10);
const defaultModel = process.env.CURSOR_BRIDGE_MODEL || "composer-2.5";
const workspaceCwd = path.resolve(
  process.env.CURSOR_BRIDGE_CWD ||
    path.join(os.homedir(), "Library", "Application Support", "GrokBuild", "cursor-bridge-workspace")
);

await mkdir(workspaceCwd, { recursive: true });
process.chdir(workspaceCwd);

let modelCache = null;

const server = http.createServer((request, response) => {
  handleRequest(request, response).catch((error) => {
    if (!response.headersSent) {
      writeJson(response, openAiError(error), statusFromError(error));
    } else {
      response.end();
    }
  });
});

server.listen(port, host, () => {
  console.log(`GrokBuild Cursor bridge listening on http://${host}:${port}/v1`);
  console.log(`Workspace: ${workspaceCwd}`);
});

process.on("SIGINT", () => closeAndExit(0));
process.on("SIGTERM", () => closeAndExit(0));

async function handleRequest(request, response) {
  const url = new URL(request.url || "/", `http://${request.headers.host || `${host}:${port}`}`);
  const apiPath = normalizeApiPath(url.pathname);

  if (request.method === "OPTIONS") {
    writeCors(response, 204);
    response.end();
    return;
  }

  if (request.method === "GET" && (apiPath === "/health" || apiPath === "/")) {
    writeJson(response, { ok: true, service: "grokbuild-cursor-bridge", cwd: workspaceCwd });
    return;
  }

  if (request.method === "GET" && apiPath === "/models") {
    writeJson(response, await modelList(getApiKey(request)));
    return;
  }

  if (request.method === "POST" && apiPath === "/chat/completions") {
    await handleChatCompletions(request, response);
    return;
  }

  writeJson(response, openAiError(new HttpError("Not found", 404, "not_found")), 404);
}

function normalizeApiPath(pathname) {
  if (pathname.startsWith("/v1/")) return pathname.slice("/v1".length);
  if (pathname === "/v1") return "/";
  return pathname;
}

async function handleChatCompletions(request, response) {
  const body = await readJsonBody(request);
  const apiKey = getApiKey(request);
  if (!apiKey) {
    writeJson(response, openAiError(new HttpError("Missing CURSOR_API_KEY", 401, "unauthorized")), 401);
    return;
  }

  const model = normalizeModel(body.model);
  const prompt = buildChatPrompt(body.messages);
  const stream = body.stream === true;
  const created = nowSeconds();
  const completionId = `chatcmpl_${randomId()}`;

  if (stream) {
    writeSseHeaders(response);
    writeSseChunk(response, {
      id: completionId,
      object: "chat.completion.chunk",
      created,
      model,
      choices: [{ index: 0, delta: { role: "assistant" }, finish_reason: null }]
    });

    try {
      const { text, usage } = await runAgent({ apiKey, model, prompt, onDelta: (delta) => {
        writeSseChunk(response, {
          id: completionId,
          object: "chat.completion.chunk",
          created,
          model,
          choices: [{ index: 0, delta: { content: delta }, finish_reason: null }]
        });
      } });
      writeSseChunk(response, {
        id: completionId,
        object: "chat.completion.chunk",
        created,
        model,
        choices: [{ index: 0, delta: {}, finish_reason: "stop" }]
      });
      // grok's OpenAI provider is streaming; without a usage chunk ACP never
      // sees last-turn input / cache / output.
      writeSseChunk(response, {
        id: completionId,
        object: "chat.completion.chunk",
        created,
        model,
        choices: [],
        usage
      });
      response.write("data: [DONE]\n\n");
      if (!text) {
        // Keep OpenAI clients happy even if the SDK returned empty text.
      }
    } catch (error) {
      writeSseChunk(response, {
        id: completionId,
        object: "chat.completion.chunk",
        created,
        model,
        choices: [{
          index: 0,
          delta: { content: `\n[bridge error] ${friendlyBridgeError(error)}` },
          finish_reason: "stop"
        }]
      });
      response.write("data: [DONE]\n\n");
    } finally {
      response.end();
    }
    return;
  }

  const { text, usage } = await runAgent({ apiKey, model, prompt });
  writeJson(response, {
    id: completionId,
    object: "chat.completion",
    created,
    model,
    choices: [
      {
        index: 0,
        message: { role: "assistant", content: text || "Done." },
        finish_reason: "stop"
      }
    ],
    usage
  });
}

async function runAgent({ apiKey, model, prompt, onDelta }) {
  const agent = await Agent.create({
    apiKey,
    model: { id: model },
    name: "GrokBuild Cursor bridge",
    local: { cwd: workspaceCwd }
  });

  try {
    const run = await agent.send(prompt, {
      model: { id: model },
      idempotencyKey: crypto.randomUUID()
    });
    let text = "";
    const stream = typeof run.stream === "function" ? run.stream() : run.stream;
    for await (const event of stream) {
      if (event?.type === "assistant") {
        for (const block of event.message?.content ?? []) {
          if (block?.type === "text" && block.text) {
            text += block.text;
            onDelta?.(block.text);
          }
        }
      }
    }
    const result = await run.wait();
    if (!text && result?.result) {
      text = String(result.result);
      onDelta?.(text);
    }
    if (result?.status === "error") {
      throw new HttpError("Cursor SDK run failed", 502, "cursor_sdk_error");
    }
    const cleaned = stripFinalMarker(text);
    return { text: cleaned, usage: openaiUsageFromSdk(result, prompt, cleaned) };
  } finally {
    try {
      await agent[Symbol.asyncDispose]?.();
    } catch {
      // Ignore dispose failures on short-lived agents.
    }
  }
}

function buildChatPrompt(messages) {
  const lines = [
    "You are answering through a local OpenAI-compatible bridge used by GrokBuild / grok.",
    "Treat this as chat inference: reply with the answer text only.",
    "Do not edit files, run shell commands, or call IDE tools unless the user explicitly asks you to change the workspace.",
    `Scratch workspace (ignore unless asked): ${workspaceCwd}`,
    "",
    "Conversation:"
  ];
  const list = Array.isArray(messages) ? messages : [];
  for (const message of list) {
    if (!message || typeof message !== "object") continue;
    const role = typeof message.role === "string" ? message.role.toUpperCase() : "USER";
    lines.push(`${role}: ${stringifyContent(message.content)}`);
  }
  lines.push("", "ASSISTANT:");
  return lines.join("\n");
}

async function modelList(apiKey) {
  const now = Date.now();
  if (modelCache && modelCache.expiresAt > now) return modelCache.value;

  if (!apiKey) {
    throw new HttpError("Missing CURSOR_API_KEY", 401, "unauthorized");
  }

  try {
    const sdkModels = await Cursor.models.list({ apiKey });
    const models = (sdkModels?.length ? sdkModels : fallbackModels())
      .map((model) =>
        typeof model === "string"
          ? { id: model, object: "model", created: 1779148800, owned_by: "cursor" }
          : {
              id: model.id,
              object: "model",
              created: 1779148800,
              owned_by: "cursor"
            }
      )
      .filter((model) => !isExcludedCatalogID(model.id));
    const value = { object: "list", data: models };
    modelCache = { value, expiresAt: now + 10 * 60 * 1000 };
    return value;
  } catch (error) {
    const normalized = normalizeError(error);
    const status =
      /unauthor|forbidden|invalid.*key|api.?key|401|403/i.test(normalized.message)
        ? 401
        : statusFromError(error);
    throw new HttpError(
      status === 401
        ? "Cursor API key was rejected. Check the key in Settings → Models."
        : normalized.message,
      status,
      status === 401 ? "unauthorized" : normalized.code || "cursor_sdk_error"
    );
  }
}

function fallbackModels() {
  return [
    { id: "composer-2.5", object: "model", created: 1779148800, owned_by: "cursor" },
    { id: "composer-2.5-fast", object: "model", created: 1779148800, owned_by: "cursor" },
    { id: "gpt-5.5", object: "model", created: 1779148800, owned_by: "cursor" },
    { id: "gpt-5.3-codex", object: "model", created: 1779148800, owned_by: "cursor" }
  ];
}

/** Routing aliases — not real models users should add in GrokBuild. */
function isExcludedCatalogID(id) {
  const key = String(id || "")
    .trim()
    .toLowerCase();
  return key === "default" || key === "auto" || key === "auto-smart";
}

function getApiKey(request) {
  return resolveCursorApiKey({
    authorizationHeader: request.headers.authorization || "",
    envApiKey: process.env.CURSOR_API_KEY || ""
  });
}

function normalizeModel(model) {
  if (typeof model !== "string" || !model.trim()) return defaultModel;
  if (model === "default" || model === "auto") return defaultModel;
  return model.trim();
}

async function readJsonBody(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  const raw = Buffer.concat(chunks).toString("utf8");
  if (!raw.trim()) return {};
  try {
    return JSON.parse(raw);
  } catch {
    throw new HttpError("Invalid JSON request body", 400, "invalid_json");
  }
}

function writeJson(response, payload, status = 200) {
  writeCors(response, status, { "Content-Type": "application/json; charset=utf-8" });
  response.end(JSON.stringify(payload));
}

function writeCors(response, status, headers = {}) {
  response.writeHead(status, {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, content-type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    ...headers
  });
}

function writeSseHeaders(response) {
  writeCors(response, 200, {
    "Content-Type": "text/event-stream; charset=utf-8",
    "Cache-Control": "no-cache, no-transform",
    Connection: "keep-alive"
  });
}

function writeSseChunk(response, payload) {
  response.write(`data: ${JSON.stringify(payload)}\n\n`);
}

function openAiError(error) {
  const normalized = normalizeError(error);
  return {
    error: {
      message: normalized.message,
      type: "cursor_bridge_error",
      code: normalized.code || "cursor_bridge_error"
    }
  };
}

function normalizeError(error) {
  if (error instanceof HttpError) return { message: error.message, code: error.code };
  if (error && typeof error === "object" && "message" in error) {
    return { message: String(error.message), code: "cursor_bridge_error" };
  }
  return { message: String(error || "Cursor bridge request failed"), code: "cursor_bridge_error" };
}

/** User-facing copy for streamed failures (avoid raw SDK jargon when we can). */
function friendlyBridgeError(error) {
  const message = normalizeError(error).message;
  if (/invalid user api key|unauthorized|forbidden|api.?key/i.test(message)) {
    return "Cursor API key was rejected. Re-paste the key in Settings → Models → Cursor.";
  }
  return message;
}

function statusFromError(error) {
  return error instanceof HttpError ? error.status : 502;
}

class HttpError extends Error {
  constructor(message, status, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

function stringifyContent(value) {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) {
    return value
      .map((part) => {
        if (typeof part === "string") return part;
        if (part && typeof part === "object") {
          if (typeof part.text === "string") return part.text;
          if (part.type === "text" && typeof part.text === "string") return part.text;
        }
        return "";
      })
      .filter(Boolean)
      .join("\n");
  }
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function stripFinalMarker(text) {
  return String(text || "")
    .replace(/<\s*[|｜]\s*final\s*[|｜]\s*>/g, "")
    .trim();
}

function openaiUsageFromSdk(result, prompt, text) {
  const src = result && typeof result === "object" ? result : {};
  const raw = src.usage || src.tokenUsage || src.tokens || {};
  const details = raw.prompt_tokens_details || raw.promptTokensDetails || {};
  const cached =
    firstNumber(
      raw.cachedReadTokens,
      raw.cacheReadInputTokens,
      raw.cache_read_input_tokens,
      raw.cached_tokens,
      details.cached_tokens,
      details.cachedTokens
    ) ?? 0;
  const promptTokens =
    firstNumber(raw.prompt_tokens, raw.inputTokens, raw.input_tokens) ??
    approximateTokens(prompt);
  const completionTokens =
    firstNumber(raw.completion_tokens, raw.outputTokens, raw.output_tokens) ??
    approximateTokens(text);
  const usage = {
    prompt_tokens: promptTokens,
    completion_tokens: completionTokens,
    total_tokens: promptTokens + completionTokens
  };
  if (cached > 0) {
    usage.prompt_tokens_details = { cached_tokens: cached };
  }
  return usage;
}

function firstNumber(...values) {
  for (const value of values) {
    if (typeof value === "number" && Number.isFinite(value)) return Math.max(0, Math.round(value));
  }
  return null;
}

function approximateTokens(text) {
  return Math.max(0, Math.ceil(String(text || "").length / 4));
}

function nowSeconds() {
  return Math.floor(Date.now() / 1000);
}

function randomId() {
  return crypto.randomUUID().replaceAll("-", "");
}

function closeAndExit(code) {
  server.close(() => process.exit(code));
  setTimeout(() => process.exit(code), 1000).unref();
}
