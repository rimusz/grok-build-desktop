import assert from "node:assert/strict";
import { test } from "node:test";
import {
  BRIDGE_PROTOCOLS,
  buildPromptFromResponsesBody,
  completedResponseObject,
  createResponsesStream,
  flattenResponsesInput,
  formatSseEvent,
  healthPayload,
  isChatCompletionsPath,
  isResponsesPath,
  normalizeApiPath
} from "./cursor-bridge-protocol.mjs";

test("normalizes /v1 prefixes and trailing slashes", () => {
  assert.equal(normalizeApiPath("/v1/responses"), "/responses");
  assert.equal(normalizeApiPath("/v1/responses/"), "/responses");
  assert.equal(normalizeApiPath("/v1/chat/completions"), "/chat/completions");
  assert.equal(normalizeApiPath("/health"), "/health");
});

test("routes chat completions and responses paths", () => {
  assert.equal(isResponsesPath("/responses"), true);
  assert.equal(isChatCompletionsPath("/chat/completions"), true);
  assert.equal(isResponsesPath("/chat/completions"), false);
});

test("health advertises both protocols", () => {
  const payload = healthPayload("/tmp");
  assert.equal(payload.ok, true);
  assert.deepEqual(payload.protocols, BRIDGE_PROTOCOLS);
  assert.ok(payload.protocols.includes("responses"));
});

test("flattens Responses input strings and message arrays", () => {
  assert.deepEqual(flattenResponsesInput("hello"), [{ role: "user", content: "hello" }]);
  assert.deepEqual(
    flattenResponsesInput([
      { role: "user", content: "hi" },
      { type: "input_text", text: "again" }
    ]),
    [
      { role: "user", content: "hi" },
      { role: "user", content: "again" }
    ]
  );
});

test("builds a prompt from a Responses body", () => {
  const prompt = buildPromptFromResponsesBody({
    instructions: "Be brief.",
    input: "say hi"
  });
  assert.match(prompt, /SYSTEM: Be brief/);
  assert.match(prompt, /USER: say hi/);
  assert.match(prompt, /ASSISTANT:$/);
});

test("completed Responses object carries output_text and usage", () => {
  const payload = completedResponseObject({
    id: "resp_1",
    model: "grok-4.6",
    text: "Hi",
    usage: { prompt_tokens: 4, completion_tokens: 1, total_tokens: 5 },
    created: 1,
    itemId: "msg_1"
  });
  assert.equal(payload.object, "response");
  assert.equal(payload.status, "completed");
  assert.equal(payload.output[0].content[0].text, "Hi");
  assert.equal(payload.usage.input_tokens, 4);
  assert.equal(payload.usage.output_tokens, 1);
});

test("streaming Responses events include output_text deltas", () => {
  const stream = createResponsesStream({
    id: "resp_1",
    model: "grok-4.6",
    created: 1,
    itemId: "msg_1"
  });
  const prelude = stream.prelude();
  assert.equal(prelude[0].event, "response.created");
  const delta = stream.delta("Hi");
  assert.equal(delta.data.type, "response.output_text.delta");
  assert.equal(delta.data.delta, "Hi");
  const finale = stream.finale("Hi", { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 });
  assert.equal(finale.at(-1).event, "response.completed");
  assert.match(formatSseEvent(delta), /^event: response\.output_text\.delta\ndata: /);
});
