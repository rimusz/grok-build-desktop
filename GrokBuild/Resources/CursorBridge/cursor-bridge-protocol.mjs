/**
 * Pure OpenAI wire helpers for the GrokBuild Cursor sidecar.
 *
 * grok 1.0.x talks to custom grok-4.6 endpoints over POST /v1/responses
 * (not only /v1/chat/completions). Keep path + payload mapping here so
 * the HTTP server and unit tests share one implementation.
 */

export const BRIDGE_PROTOCOLS = ["chat.completions", "responses"];

export function normalizeApiPath(pathname) {
  let path = String(pathname || "/");
  if (path.length > 1 && path.endsWith("/")) path = path.slice(0, -1);
  if (path.startsWith("/v1/")) return path.slice("/v1".length);
  if (path === "/v1") return "/";
  return path;
}

export function isChatCompletionsPath(apiPath) {
  return apiPath === "/chat/completions";
}

export function isResponsesPath(apiPath) {
  return apiPath === "/responses";
}

export function healthPayload(cwd) {
  return {
    ok: true,
    service: "grokbuild-cursor-bridge",
    cwd,
    protocols: BRIDGE_PROTOCOLS
  };
}

export function buildChatPrompt(messages, workspaceCwd = "") {
  const lines = [
    "You are answering through a local OpenAI-compatible bridge used by GrokBuild / grok.",
    "Treat this as chat inference: reply with the answer text only.",
    "Do not edit files, run shell commands, or call IDE tools unless the user explicitly asks you to change the workspace."
  ];
  if (workspaceCwd) {
    lines.push(`Scratch workspace (ignore unless asked): ${workspaceCwd}`);
  }
  lines.push("", "Conversation:");
  const list = Array.isArray(messages) ? messages : [];
  for (const message of list) {
    if (!message || typeof message !== "object") continue;
    const role = typeof message.role === "string" ? message.role.toUpperCase() : "USER";
    lines.push(`${role}: ${stringifyContent(message.content)}`);
  }
  lines.push("", "ASSISTANT:");
  return lines.join("\n");
}

export function buildPromptFromResponsesBody(body = {}, workspaceCwd = "") {
  const messages = [];
  const instructions = typeof body.instructions === "string" ? body.instructions.trim() : "";
  if (instructions) messages.push({ role: "system", content: instructions });
  messages.push(...flattenResponsesInput(body.input));
  if (messages.length === 0 && Array.isArray(body.messages)) {
    messages.push(...body.messages);
  }
  return buildChatPrompt(messages, workspaceCwd);
}

export function flattenResponsesInput(input) {
  if (typeof input === "string") {
    const trimmed = input.trim();
    return trimmed ? [{ role: "user", content: trimmed }] : [];
  }
  if (!Array.isArray(input)) return [];
  const messages = [];
  for (const item of input) {
    if (typeof item === "string") {
      if (item.trim()) messages.push({ role: "user", content: item });
      continue;
    }
    if (!item || typeof item !== "object") continue;
    if (item.type === "input_text" && typeof item.text === "string") {
      messages.push({ role: "user", content: item.text });
      continue;
    }
    const role = typeof item.role === "string" ? item.role : "user";
    const content = stringifyContent(item.content ?? item.text ?? item);
    if (content) messages.push({ role, content });
  }
  return messages;
}

export function stringifyContent(value) {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) {
    return value
      .map((part) => {
        if (typeof part === "string") return part;
        if (part && typeof part === "object") {
          if (typeof part.text === "string") return part.text;
          if (part.type === "input_text" && typeof part.text === "string") return part.text;
          if (part.type === "output_text" && typeof part.text === "string") return part.text;
        }
        return "";
      })
      .filter(Boolean)
      .join("\n");
  }
  if (value && typeof value === "object" && typeof value.text === "string") return value.text;
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

export function responsesUsageFromOpenAI(usage = {}) {
  const inputTokens = usage.prompt_tokens ?? 0;
  const outputTokens = usage.completion_tokens ?? 0;
  const result = {
    input_tokens: inputTokens,
    output_tokens: outputTokens,
    total_tokens: usage.total_tokens ?? inputTokens + outputTokens
  };
  const cached = usage.prompt_tokens_details?.cached_tokens;
  if (typeof cached === "number" && cached > 0) {
    result.input_tokens_details = { cached_tokens: cached };
  }
  return result;
}

export function completedResponseObject({ id, model, text, usage, created, itemId }) {
  const messageId = itemId || `msg_${id}`;
  const outputText = text || "Done.";
  return {
    id,
    object: "response",
    created_at: created,
    status: "completed",
    model,
    output: [
      {
        id: messageId,
        type: "message",
        status: "completed",
        role: "assistant",
        content: [{ type: "output_text", text: outputText }]
      }
    ],
    usage: responsesUsageFromOpenAI(usage)
  };
}

export function createResponsesStream({ id, model, created, itemId }) {
  let sequence = 0;
  const nextSeq = () => {
    sequence += 1;
    return sequence;
  };
  const messageId = itemId || `msg_${id}`;

  function inProgressResponse(status, extra = {}) {
    return {
      id,
      object: "response",
      created_at: created,
      status,
      model,
      output: extra.output || [],
      ...extra.rest
    };
  }

  return {
    prelude() {
      return [
        namedEvent("response.created", {
          type: "response.created",
          sequence_number: nextSeq(),
          response: inProgressResponse("in_progress")
        }),
        namedEvent("response.in_progress", {
          type: "response.in_progress",
          sequence_number: nextSeq(),
          response: inProgressResponse("in_progress")
        }),
        namedEvent("response.output_item.added", {
          type: "response.output_item.added",
          sequence_number: nextSeq(),
          output_index: 0,
          item: {
            id: messageId,
            type: "message",
            status: "in_progress",
            role: "assistant",
            content: []
          }
        }),
        namedEvent("response.content_part.added", {
          type: "response.content_part.added",
          sequence_number: nextSeq(),
          item_id: messageId,
          output_index: 0,
          content_index: 0,
          part: { type: "output_text", text: "" }
        })
      ];
    },
    delta(text) {
      return namedEvent("response.output_text.delta", {
        type: "response.output_text.delta",
        sequence_number: nextSeq(),
        item_id: messageId,
        output_index: 0,
        content_index: 0,
        delta: text
      });
    },
    finale(text, usage) {
      const outputText = text || "Done.";
      const completed = completedResponseObject({
        id,
        model,
        text: outputText,
        usage,
        created,
        itemId: messageId
      });
      return [
        namedEvent("response.output_text.done", {
          type: "response.output_text.done",
          sequence_number: nextSeq(),
          item_id: messageId,
          output_index: 0,
          content_index: 0,
          text: outputText
        }),
        namedEvent("response.content_part.done", {
          type: "response.content_part.done",
          sequence_number: nextSeq(),
          item_id: messageId,
          output_index: 0,
          content_index: 0,
          part: { type: "output_text", text: outputText }
        }),
        namedEvent("response.output_item.done", {
          type: "response.output_item.done",
          sequence_number: nextSeq(),
          output_index: 0,
          item: completed.output[0]
        }),
        namedEvent("response.completed", {
          type: "response.completed",
          sequence_number: nextSeq(),
          response: completed
        })
      ];
    }
  };
}

export function formatSseEvent({ event, data }) {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
}

function namedEvent(event, data) {
  return { event, data };
}
