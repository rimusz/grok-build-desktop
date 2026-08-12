import assert from "node:assert/strict";
import { resolveCursorApiKey } from "./cursor-bridge-auth.mjs";
import { test } from "node:test";

test("prefers CURSOR_API_KEY over grok session JWT and local placeholder", () => {
  const env = "crsr_env_key_for_tests_0123456789abcdef";
  assert.equal(
    resolveCursorApiKey({ authorizationHeader: "Bearer eyJhbGciOi.jwt", envApiKey: env }),
    env
  );
  assert.equal(
    resolveCursorApiKey({ authorizationHeader: "Bearer local", envApiKey: env }),
    env
  );
  assert.equal(
    resolveCursorApiKey({ authorizationHeader: "Bearer dummy", envApiKey: env }),
    env
  );
  assert.equal(resolveCursorApiKey({ authorizationHeader: "", envApiKey: env }), env);
});

test("accepts an explicit Cursor user API key from Authorization", () => {
  const headerKey = "crsr_from_header_0123456789abcdef0123";
  const env = "crsr_env_key_for_tests_0123456789abcdef";
  assert.equal(
    resolveCursorApiKey({ authorizationHeader: `Bearer ${headerKey}`, envApiKey: env }),
    headerKey
  );
});

test("returns empty when neither source has a usable key", () => {
  assert.equal(resolveCursorApiKey({ authorizationHeader: "Bearer eyJ.jwt", envApiKey: "" }), "");
  assert.equal(resolveCursorApiKey({}), "");
});
