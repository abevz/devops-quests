import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { I18n, chooseLanguage, languageControls, loadI18n } from "../web/locale.mjs";
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
  for (const language of readdirSync(new URL("../locales/", import.meta.url))) {
    const messages = JSON.parse(readFileSync(new URL(`../locales/${language}/ui.json`, import.meta.url)));
    assert.deepEqual(Object.keys(en).sort(), Object.keys(messages).sort(), language);
    for (const key of Object.keys(en))
      assert.deepEqual(
        argumentsIn(new IntlMessageFormat(en[key], "en", undefined, { ignoreTag: true }).getAst()),
        argumentsIn(new IntlMessageFormat(messages[key], language, undefined, { ignoreTag: true }).getAst()),
        `${language}: ${key}`,
      );
  }
});

test("catalog metadata labels machine languages in both selectors and survives switching", async (t) => {
  const metadata = { pl: { translation: "machine", translation_label: "tłumaczenie maszynowe" } };
  t.mock.method(globalThis, "fetch", async () => ({ ok: true, json: async () => ({ messages: { en, ru, pl: en }, metadata }) }));
  const i18n = await loadI18n(new URL("http://localhost/"), ["en"]);
  assert.equal(i18n.translationLabel(), "");
  assert.match(i18n.languageName("pl"), /\(tłumaczenie maszynowe\)$/);
  const node = () => ({ children: [], append(...children) { this.children.push(...children); }, replaceChildren() { this.children = []; } });
  const previousDocument = globalThis.document;
  globalThis.document = { createElement: node };
  t.after(() => { if (previousDocument === undefined) delete globalThis.document; else globalThis.document = previousDocument; });
  const host = node();
  languageControls(i18n, host, () => {});
  for (const label of host.children) {
    const options = label.children[0].children;
    assert.match(options.find((option) => option.value === "pl").textContent, /tłumaczenie maszynowe/);
    assert.doesNotMatch(options.find((option) => option.value === "en").textContent, /tłumaczenie/);
  }
  i18n.setLanguages("pl", "en");
  assert.equal(i18n.translationLabel(), "tłumaczenie maszynowe");
  assert.equal(i18n.translationNotice(), "tłumaczenie maszynowe");
  assert.equal(i18n.translationNotice(true), "tłumaczenie maszynowe");
  i18n.setLanguages("en", "pl");
  assert.equal(i18n.translationNotice(), "");
  assert.equal(i18n.translationNotice(true), "tłumaczenie maszynowe");
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
