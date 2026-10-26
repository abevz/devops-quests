import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { I18n } from "../web/locale.mjs";

const root = new URL("../", import.meta.url);
const languages = readdirSync(new URL("locales/", root));
const messages = Object.fromEntries(
  languages.map((lang) => [lang, JSON.parse(readFileSync(new URL(`locales/${lang}/ui.json`, root)))]),
);
const html = readFileSync(new URL("web/index.html", root), "utf8");
const contentKeys = [...html.matchAll(/data-i18n-content="([^"]+)"/g)].map((m) => m[1]);

test("reading-area labels exist in every locale and render in the translation language", () => {
  assert.deepEqual([...new Set(contentKeys)].sort(), [
    "facts.title",
    "preview.resources",
    "preview.stages",
    "quest.need_hint",
    "quest.objectives",
    "quest.story",
    "scoring.best_rule",
  ]);
  for (const lang of languages)
    for (const key of contentKeys) assert.ok(Object.hasOwn(messages[lang], key), `${lang}: ${key}`);
  const i18n = new I18n(messages, ["pl"], "ru");
  assert.equal(i18n.t("preview.stages", {}, "ru"), messages.ru["preview.stages"]);
  assert.equal(i18n.t("preview.stages"), messages.pl["preview.stages"]);
});

test("the main-language button is fully localized", () => {
  for (const lang of languages.filter((lang) => lang !== "en"))
    assert.doesNotMatch(messages[lang]["language.main"].replace(/\{[^}]*\}/g, ""), /\blanguage\b/, lang);
});

test("reading-area strings in app.js use the content language", () => {
  const app = readFileSync(new URL("web/app.js", root), "utf8");
  for (const key of [
    "preview.stage",
    "preview.estimate",
    "preview.exam_time",
    "dependency.",
    "facts.",
    "scoring.formula",
    "scoring.best",
    "scoring.no_best",
    "hint.briefing_rule",
    "preview.ready",
    "guide.full",
    "guide.full_lab",
  ])
    assert.ok(app.includes(`"${key}`), key);
  for (const key of ["preview.stage", "dependency.", "facts.network", "guide.full", "guide.full_lab"])
    assert.doesNotMatch(app, new RegExp(`\\bt\\("${key.replace(".", "\\.")}`), key);
  assert.match(app, /\$\("preview-score"\)\.textContent = tc\(/);
  assert.match(app, /\$\("preview-time"\)\.textContent = tc\(/);
  assert.match(app, /\$\("preview-hint-policy"\)\.textContent = tc\(/);
  assert.match(app, /i18n\.content\(guideData\.titles, language\)/);
});
