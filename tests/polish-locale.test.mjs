import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { I18n } from "../web/locale.mjs";
const read = (name) => JSON.parse(readFileSync(new URL(`../locales/pl/${name}.json`, import.meta.url)));

test("Polish machine translation selects the native label and all Polish plural categories", () => {
  const i18n = new I18n({ pl: read("ui"), en: {} }, ["pl-PL"], "none", { pl: read("metadata") });
  assert.equal(i18n.language, "pl");
  assert.equal(i18n.translationLabel(), "tłumaczenie maszynowe");
  for (const [count, expected] of [[1, "1 punkt"], [2, "2 punkty"], [5, "5 punktów"], [12, "12 punktów"], [22, "22 punkty"], [1.5, "1,5 punktu"]])
    assert.equal(i18n.t("level.points", { count }), expected);
  assert.equal(i18n.t("map.matches", { count: 22 }), "22 pasujące zadania");
  assert.equal(i18n.t("checks.failed", { count: 5 }), "5 celów nie zostało osiągniętych.");
});
