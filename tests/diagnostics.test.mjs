import test from "node:test";
import assert from "node:assert/strict";
import { diagnosticMessages } from "../web/diagnostics.mjs";
import { I18n } from "../web/locale.mjs";

test("condition markers select translated content without suppressing unknown raw output", () => {
  const diagnostics = { ready: { en: "Ready replicas must equal 1.", pl: "Gotowe repliki muszą być równe 1." } };
  const found = diagnosticMessages("ready: ✗ [DQ:ready]\nunknown probe failure", diagnostics);
  const locale = new I18n({ en: {}, pl: {} }, ["pl"]);
  assert.equal(found.length, 1);
  assert.equal(locale.content(found[0], "pl").text, "Gotowe repliki muszą być równe 1.");
  assert.deepEqual(diagnosticMessages("unknown [DQ:missing]", diagnostics), []);
});
