import test from "node:test";
import assert from "node:assert/strict";
import { showHintGuide } from "../web/play.mjs";

test("only consecutive revealed hints with the same guide suppress the repeated link", () => {
  const hints = ["guide/a", "guide/a", "guide/b", "guide/a", "guide/a#part"].map((url) => ({ url }));
  assert.deepEqual(hints.map((_, index) => showHintGuide(hints, index)), [true, false, true, true, true]);
  assert.equal(showHintGuide(hints.slice(0, 1), 0), true);
});

test("a snippet has no link and distinct sections in one guide remain visible", () => {
  const hints = [
    {},
    { url: "guides#guide=terraform-3&section=notice-state" },
    { url: "guides#guide=terraform-3&section=notice-plan" },
  ];
  assert.deepEqual(hints.map((_, index) => showHintGuide(hints, index)), [false, true, true]);
  assert.equal(showHintGuide([hints[1], hints[0]], 1), false);
});
