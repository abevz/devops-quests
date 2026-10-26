import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { I18n } from "../web/locale.mjs";
const read = (name) => JSON.parse(readFileSync(new URL(`../locales/es/${name}.json`, import.meta.url)));

test("Spanish machine translation has native disclosure and locale-specific plural forms", () => {
  const i18n = new I18n({ es: read("ui"), en: {} }, ["es-ES"], "none", { es: read("metadata") });
  assert.equal(i18n.language, "es");
  assert.equal(i18n.translationLabel(), "traducción automática");
  for (const [count, expected] of [[1, "1 punto"], [2, "2 puntos"], [5, "5 puntos"], [22, "22 puntos"], [1.5, "1,5 puntos"]])
    assert.equal(i18n.t("level.points", { count }), expected);
  i18n.setLanguages("en", "es");
  assert.equal(i18n.translationNotice(), "");
  assert.equal(i18n.translationNotice(true), "traducción automática");
});
