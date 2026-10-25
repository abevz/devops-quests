import { IntlMessageFormat } from "intl-messageformat";

export function chooseLanguage(preferred, available) {
  for (const item of Array.isArray(preferred) ? preferred : [preferred]) {
    if (!item) continue;
    const match = available.find((lang) => lang.toLowerCase() === item.toLowerCase());
    if (match) return match;
    const base = item.split("-")[0].toLowerCase();
    if (available.includes(base)) return base;
  }
  return "en";
}
export class I18n {
  constructor(messages, preferred = ["en"], translation, metadata = {}) {
    this.messages = messages;
    this.metadata = metadata;
    this.languages = Object.keys(messages);
    this.cache = new Map();
    this.setLanguages(chooseLanguage(preferred, this.languages), translation);
  }
  setLanguages(primary, translation) {
    this.language = chooseLanguage(primary, this.languages);
    this.translation =
      translation == null || translation === "none" ? "none" : chooseLanguage(translation, this.languages);
  }
  t(key, values = {}, language = this.language) {
    const source = Object.hasOwn(this.messages[language] ?? {}, key) ? language : "en";
    const message = this.messages[source]?.[key];
    if (typeof message !== "string") throw Error(`Missing message: ${key}`);
    const id = source + ":" + key;
    if (!this.cache.has(id)) this.cache.set(id, new IntlMessageFormat(message, source, undefined, { ignoreTag: true }));
    return String(this.cache.get(id).format(values));
  }
  content(value, language = this.language) {
    if (typeof value === "string") return { text: value, language: "en" }; // Historical run events.
    const source = value?.[language] ? language : "en";
    return { text: value?.[source] ?? "", language: source };
  }
  number(value, options = {}) {
    return new Intl.NumberFormat(this.language, options).format(value);
  }
  date(value) {
    return new Intl.DateTimeFormat(this.language, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
  }
  languageName(language) {
    const name = new Intl.DisplayNames([this.language], { type: "language" }).of(language);
    const label = this.translationLabel(language);
    return label ? `${name} (${label})` : name;
  }
  translationLabel(language = this.language) {
    const metadata = this.metadata[language];
    return metadata?.translation === "machine" ? metadata.translation_label : "";
  }
  translationNotice(showTranslation = false) {
    return [...new Set([
      this.translationLabel(),
      showTranslation && this.translation !== "none" ? this.translationLabel(this.translation) : "",
    ])].filter(Boolean).join(" · ");
  }
  document(root = document) {
    root.documentElement.lang = this.language;
    for (const node of root.querySelectorAll("[data-i18n]"))
      node.textContent = this.t(node.dataset.i18n, JSON.parse(node.dataset.i18nValues ?? "{}"));
    for (const node of root.querySelectorAll("[data-i18n-aria]"))
      node.setAttribute("aria-label", this.t(node.dataset.i18nAria));
  }
}
export async function loadI18n(base, preferred = navigator.languages) {
  const response = await fetch(new URL("api/locales", base));
  if (!response.ok) throw Error(`Language catalog HTTP ${response.status}`);
  const { messages, metadata } = await response.json();
  return new I18n(messages, preferred, undefined, metadata);
}
export function languageControls(i18n, host, onchange) {
  host.replaceChildren();
  for (const [field, key] of [
    ["primary", "language.primary"],
    ["translation", "language.translation"],
  ]) {
    const label = document.createElement("label");
    label.textContent = i18n.t(key);
    const select = document.createElement("select");
    select.id = "language-" + field;
    if (field === "translation") {
      const option = document.createElement("option");
      option.value = "none";
      option.textContent = i18n.t("language.none");
      select.append(option);
    }
    for (const lang of i18n.languages) {
      const option = document.createElement("option");
      option.value = lang;
      option.textContent = i18n.languageName(lang);
      select.append(option);
    }
    select.value = field === "primary" ? i18n.language : i18n.translation;
    select.onchange = () => onchange(field, select.value);
    label.append(select);
    host.append(label);
  }
}
