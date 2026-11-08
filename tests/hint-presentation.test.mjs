import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { briefingHintView } from "../web/play.mjs";
import { I18n } from "../web/locale.mjs";

const access = Object.freeze({ completed: false, count: 0, total: 3 });
test("pre-run hints keep their pending-transfer guards and explicit cost presentation", () => {
  assert.deepEqual(briefingHintView(access, "normal"), {
    titleKey: "hint.prerun_title",
    showCost: true,
    showReveal: true,
    revealDisabled: false,
  });
  assert.equal(briefingHintView({ ...access, count: 2 }, "free").revealDisabled, false);
  assert.equal(briefingHintView({ ...access, count: 3 }, "free").revealDisabled, true);
  assert.equal(briefingHintView(access, "free", true).revealDisabled, true);
  assert.equal(briefingHintView(access, "free", false, true).revealDisabled, true);
});
test("completion makes the hint ladder a free debrief, without a reveal action or cost", () => {
  for (const mode of ["normal", "free", "exam"]) {
    const view = briefingHintView({ completed: true, count: 3, total: 3 }, mode);
    assert.equal(view.titleKey, "hint.review_title");
    assert.equal(view.showCost, false);
    assert.equal(view.showReveal, false);
  }
});
test("exam preview cannot offer paid hint revelation", () => {
  const view = briefingHintView(access, "exam");
  assert.equal(view.showReveal, false);
  assert.equal(view.showCost, false);
});
test("all five locales name the pre-run and debrief phases and format the policy cost", () => {
  const languages = ["en", "pl", "es", "de", "ru"];
  const messages = Object.fromEntries(
    languages.map((lang) => [lang, JSON.parse(readFileSync(new URL(`../locales/${lang}/ui.json`, import.meta.url)))]),
  );
  const i18n = new I18n(messages, ["en"], "en");
  for (const lang of languages) {
    for (const key of ["hint.prerun_title", "hint.review_title", "quest.debrief"])
      assert.ok(messages[lang][key]?.trim(), `${lang}: ${key}`);
    const cost = i18n.t("hint.prerun_cost", { penalty: 137 }, lang);
    assert.ok(cost.includes(new Intl.NumberFormat(lang).format(137)), `${lang}: dynamic penalty`);
    assert.doesNotMatch(cost, /\{penalty/);
  }
});
