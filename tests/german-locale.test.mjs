import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { I18n } from "../web/locale.mjs";
const read = (name) => JSON.parse(readFileSync(new URL(`../locales/de/${name}.json`, import.meta.url)));

test("German machine translation has native disclosure and locale-specific plural forms", () => {
  const i18n = new I18n({ de: read("ui"), en: {} }, ["de-DE"], "none", { de: read("metadata") });
  assert.equal(i18n.language, "de");
  assert.equal(i18n.translationLabel(), "maschinelle Übersetzung");
  for (const [count, expected] of [[1, "1 Punkt"], [2, "2 Punkte"], [5, "5 Punkte"], [22, "22 Punkte"], [1.5, "1,5 Punkte"]])
    assert.equal(i18n.t("level.points", { count }), expected);
  i18n.setLanguages("en", "de");
  assert.equal(i18n.translationNotice(), "");
  assert.equal(i18n.translationNotice(true), "maschinelle Übersetzung");
});
