import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { I18n } from "../web/locale.mjs";
import { scoreBreakdown } from "../web/score-preview.mjs";

const policy = JSON.parse(readFileSync(new URL("../devops_quests/scoring.json", import.meta.url)));

test("score preview counts completed time steps, hint/reset penalties and the floor", () => {
  const initial = scoreBreakdown(policy, 0, 1, 1);
  assert.equal(initial.score, policy.base - policy.hint_penalty - policy.reset_penalty);
  assert.equal(scoreBreakdown(policy, policy.seconds_per_point - 0.001, 1, 1).score, initial.score);
  assert.equal(scoreBreakdown(policy, policy.seconds_per_point, 1, 1).score, initial.score - policy.time_penalty);
  assert.equal(scoreBreakdown(policy, 100000, 3, 10).score, policy.minimum);
});

test("EN/RU formulas render policy parameters rather than copied numeric constants", () => {
  const messages = Object.fromEntries(
    ["en", "ru"].map((language) => [
      language,
      JSON.parse(readFileSync(new URL(`../locales/${language}/ui.json`, import.meta.url))),
    ]),
  );
  const changed = {
    ...policy,
    base: 2345,
    seconds_per_point: 7,
    time_penalty: 2,
    hint_penalty: 81,
    reset_penalty: 91,
    minimum: 43,
  };
  for (const language of ["en", "ru"]) {
    const i18n = new I18n(messages, [language]);
    const text = i18n.t("scoring.formula", changed);
    for (const key of ["base", "seconds_per_point", "time_penalty", "hint_penalty", "reset_penalty", "minimum"])
      assert.ok(text.includes(i18n.number(changed[key])), `${language}: ${key}`);
    assert.ok(!text.includes(i18n.number(policy.base)));
    assert.ok(!text.includes(i18n.number(policy.minimum)));
  }
});
