import test from "node:test";
import assert from "node:assert/strict";
import { checkFeedback, conditionKeys, showProbeReason } from "../web/diagnostics.mjs";
import { I18n } from "../web/locale.mjs";

test("condition markers select translated content without suppressing unknown raw output", () => {
  const diagnostics = { ready: { en: "Ready replicas must equal 1.", pl: "Gotowe repliki muszą być równe 1." } };
  const found = conditionKeys({ detail: "ready: ✗ [DQ:ready]\nunknown probe failure" }, diagnostics);
  const locale = new I18n({ en: {}, pl: {} }, ["pl"]);
  assert.equal(found.length, 1);
  assert.equal(locale.content(diagnostics[found[0]], "pl").text, "Gotowe repliki muszą być równe 1.");
  assert.deepEqual(conditionKeys({ detail: "unknown [DQ:missing]" }, diagnostics), []);
});

test("the condition summary and repair order reflect only the current failures", () => {
  const markers = ["service", "dns", "udp", "tcp", "http"];
  const messages = Object.fromEntries(markers.map(key => [key, { en: key }]));
  const dependencies = { dns: ["service"], udp: ["dns"], tcp: ["dns"], http: ["udp", "tcp"] };
  const observations = [
    { objective: 0, diagnostic_keys: [] },
    { objective: 1, diagnostic_keys: ["service", "service"] },
    { objective: 2, diagnostic_keys: ["udp", "tcp", "unknown"] },
    { objective: 3, diagnostic_keys: ["dns"] },
    { objective: 4, diagnostic_keys: ["http"] },
  ];
  const result = checkFeedback(observations, messages, dependencies);
  assert.equal(result.count, 6);
  assert.deepEqual(result.groups.map(group => group.failure.objective), [1, 3, 2, 4, 0]);
  assert.deepEqual([...result.start], ["service"]);
  assert.deepEqual([...result.waiting], ["udp", "tcp", "dns", "http"]);
  const laterObservations = observations.filter(item => item.objective !== 1 && item.objective !== 3);
  const later = checkFeedback(laterObservations, messages, dependencies);
  assert.deepEqual([...later.start], ["udp", "tcp"]);
  assert.deepEqual([...later.waiting], ["http"]);
});

test("specific probe reasons remain visible with or without a known marker", () => {
  assert.equal(showProbeReason("checks.cause.timeout", true, true), true);
  assert.equal(showProbeReason("checks.cause.denied", true, false), true);
  assert.equal(showProbeReason("checks.cause.no_detail", false, true), true);
  assert.equal(showProbeReason("checks.cause.unsatisfied", false, true), false);
  assert.equal(showProbeReason("checks.cause.unsatisfied", true, true), false);
  assert.equal(showProbeReason("checks.cause.unsatisfied", true, false), false);
  assert.equal(showProbeReason("checks.cause.unsatisfied", false, false), true);
});
