import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { I18n, chooseLanguage } from "../web/locale.mjs";
const en = JSON.parse(readFileSync(new URL("../locales/en/ui.json", import.meta.url)));
const ru = JSON.parse(readFileSync(new URL("../locales/ru/ui.json", import.meta.url)));
test("browser matching, ICU plurals, interpolation and English fallbacks", () => {
  const i18n = new I18n({ en, ru, pl: { "nav.map": "Mapa" } }, ["pl-PL"]);
  assert.equal(i18n.language, "pl");
  assert.equal(i18n.t("nav.map"), "Mapa");
  assert.equal(i18n.t("terminal.new"), en["terminal.new"]);
  assert.deepEqual(i18n.content({ en: "source", ru: "перевод" }), { text: "source", language: "en" });
  assert.equal(chooseLanguage(["fr-FR", "ru-RU"], ["en", "ru"]), "ru");
  i18n.setLanguages("ru", "en");
  assert.equal(i18n.t("level.points", { count: 1 }), "1 балл");
  assert.equal(i18n.t("level.points", { count: 2 }), "2 балла");
  assert.equal(i18n.t("level.points", { count: 5 }), "5 баллов");
  assert.equal(i18n.t("terminal.tab", { number: 2 }), "Терминал 2");
  assert.notEqual(i18n.number(12345.6), new I18n({ en }).number(12345.6));
  assert.notEqual(i18n.date(0), new I18n({ en }).date(0));
  assert.throws(() => i18n.t("missing.key"), /Missing message/);
});

test("all language messages use valid ICU with identical argument contracts", async () => {
  const { IntlMessageFormat } = await import("intl-messageformat");
  function argumentsIn(ast, names = new Set()) {
    for (const node of ast) {
      if (node.type !== 0 && node.type !== 7) names.add(node.value);
      if (node.options) for (const option of Object.values(node.options)) argumentsIn(option.value, names);
      if (node.children) argumentsIn(node.children, names);
    }
    return [...names].sort();
  }
  assert.deepEqual(Object.keys(en).sort(), Object.keys(ru).sort());
  for (const key of Object.keys(en))
    assert.deepEqual(
      argumentsIn(new IntlMessageFormat(en[key], "en", undefined, { ignoreTag: true }).getAst()),
      argumentsIn(new IntlMessageFormat(ru[key], "ru", undefined, { ignoreTag: true }).getAst()),
      key,
    );
});

test("explicit no-translation survives primary-language changes", () => {
  const i18n = new I18n({ en, ru }, ["en"], "none");
  assert.equal(i18n.translation, "none");
  i18n.setLanguages("ru", "none");
  assert.equal(i18n.translation, "none");
  assert.equal(i18n.language, "ru");
});

test("Hindi browser never silently defaults to Russian; explicit translation remains selected", () => {
  const first = new I18n({ en, ru }, ["hi-IN"]);
  assert.equal(first.language, "en");
  assert.equal(first.translation, "none");
  const explicit = new I18n({ en, ru }, ["hi-IN"], "ru");
  assert.equal(explicit.translation, "ru");
  const withHindi = new I18n({ en, ru, hi: { "nav.map": "नक्शा" } }, ["hi-IN"], "en");
  assert.equal(withHindi.language, "hi");
  assert.equal(withHindi.t("nav.map"), "नक्शा");
  assert.equal(withHindi.translation, "en");
});
