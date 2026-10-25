import { storageGet, storageSet, sidebarKey, readCollapsed, saveCollapsed, installNavigationIcons } from "./navigation.mjs";
import { renderDiagrams } from "./diagrams.mjs";
import { referenceParts } from "./reference.mjs";
import { attemptState, canRun, filterLevels, narrative } from "./play.mjs";
import { keySequence } from "./controls.mjs";
import { scoreBreakdown } from "./score-preview.mjs";
import { loadI18n, languageControls } from "./vendor/locale.js";
const $ = (id) => document.getElementById(id),
  base = new URL("./", location.href),
  apiPath = new URL("api/", base);
let state,
  term,
  fit,
  socket,
  terminalRun,
  ctrl = false,
  alt = false,
  busy = false;
let terminalObserver;
let terminals = [],
  activeTerminal,
  nextTerminal = 1;
const closingTerminals = new Set();
let readingTranslation = false,
  preview,
  usersData;
const tracks = ["Kubernetes", "Ansible", "OpenTofu", "Platform", "Boss"];
const filters = { mode: "normal", path: "Kubernetes", track: "", difficulty: "", status: "", search: "" };
const shownAnswers = new Set();
let updateInfo = null, updateRequest = false, buildSignature, layoutUser, tooltipItem;
let themeMode = storageGet("dq-theme") ?? "system";
installNavigationIcons();
let routing = true;
let guidesData, guideData, labData, selectedLab, selectedProfile;
let terminalKind = "quest",
  terminalEndpoint = "terminal";
let interviewData, interviewSignature;
const i18n = await loadI18n(base);
const browserLanguage = i18n.language;
const t = (key, values) => i18n.t(key, values);
let preferencesUser, lastCheck;
const el = (tag, text, cls) => {
  const n = document.createElement(tag);
  if (text !== undefined) n.textContent = text;
  if (cls) n.className = cls;
  return n;
};
function block(
  value,
  parent,
  language = readingTranslation && i18n.translation !== "none" ? i18n.translation : i18n.language,
) {
  if (!value) return;
  const content = i18n.content(value, language);
  const p = el("div", undefined, "markdown");
  p.lang = content.language;
  p.innerHTML = window.DQMarkdown.renderMarkdown(content.text);
  if (content.language !== language) p.append(el("small", t("language.fallback"), "muted"));
  parent.append(p);
}
function translationControls() {
  document.querySelector("footer").textContent = [t("footer.caption"), i18n.translationNotice(readingTranslation)].filter(Boolean).join(" · ");
  for (const id of ["bay-translate", "preview-translate", "interview-translate"]) {
    const button = $(id);
    button.hidden = i18n.translation === "none" || i18n.translation === i18n.language;
    button.textContent = t(readingTranslation ? "language.main" : "language.translate", {
      language: i18n.languageName(
        readingTranslation ? i18n.language : i18n.translation === "none" ? i18n.language : i18n.translation,
      ),
    });
    button.setAttribute("aria-pressed", String(readingTranslation));
    button.onclick = () => {
      readingTranslation = !readingTranslation;
      translationControls();
      if (preview) renderPreview();
      if (state) renderQuest();
      if (interviewData) renderInterview();
    };
  }
}
function applyLanguage() {
  i18n.document();
  document.title = t("app.title");
  languageControls(i18n, $("language-settings"), async (field, value) => {
    const primary = field === "primary" ? value : i18n.language;
    const translation = field === "translation" ? value : i18n.translation;
    try {
      if (state) await api("preferences", { primary, translation });
      i18n.setLanguages(primary, translation);
      readingTranslation = false;
      if (state) state.preferences = { primary, translation };
      storageSet("dq-primary-language", primary);
      storageSet("dq-translation-language", translation);
      applyLanguage();
      if (state) {
        renderMap();
        renderQuest();
        if (preview) renderPreview();
      }
    } catch (error) {
      notify(error.message);
    }
  });
  translationControls();
  for (const [id, all] of [
    ["play-track", false],
    ["filter-track", true],
  ]) {
    const select = $(id),
      value = select.value;
    select.replaceChildren();
    if (all) {
      const option = el("option", t("map.all"));
      option.value = "";
      select.append(option);
    }
    for (const track of tracks) {
      const option = el("option", t("track." + track));
      option.value = track;
      select.append(option);
    }
    if (id === "play-track") {
      const option = el("option", t("nav.interview"));
      option.value = "interview";
      select.append(option);
    }
    select.value = value || (all ? "" : filters.path);
  }
  theme(themeMode);
  for (const tab of terminals) {
    tab.button.textContent = t("terminal.tab", { number: tab.id });
    tab.label.querySelector(".close-terminal").setAttribute("aria-label", t("terminal.close", { number: tab.id }));
  }
  updateTerminalButton();
  if (interviewData) renderInterview();
  if (usersData) renderUsers();
  if (guidesData) renderGuides();
  if (guideData && !$("guide-reader").hidden) renderGuide();
  if (labData) renderLabs();
  renderBuildInfo();
  renderSidebar();
}
function notify(text) {
  $("notice").textContent = text;
}
async function api(name, data) {
  const options = { headers: {} };
  if (data !== undefined) {
    options.method = "POST";
    options.headers["Content-Type"] = "application/json";
    options.headers["X-CSRF-Token"] = state?.csrf ?? "";
    options.body = JSON.stringify(data);
  }
  const response = await fetch(new URL(name, apiPath), options);
  let result;
  try {
    result = await response.json();
  } catch {
    throw Error(t("error.response"));
  }
  if (!response.ok) {
    const error = Error(t(result.error?.key ?? "error.request", result.error?.values ?? {}));
    error.status = response.status;
    throw error;
  }
  return result;
}
async function action(fn) {
  if (busy) return;
  busy = true;
  try {
    notify(t("notice.preparing"));
    await fn();
    notify("");
    await refresh();
    return true;
  } catch (e) {
    notify(e.message);
    return false;
  } finally {
    busy = false;
  }
}
function closeNavigation() {
  document.body.classList.remove("navigation-open");
  $("nav-toggle").setAttribute("aria-expanded", "false");
}
$("nav-toggle").onclick = () => {
  const expanded = document.body.classList.toggle("navigation-open");
  $("nav-toggle").setAttribute("aria-expanded", String(expanded));
};
$("nav-backdrop").onclick = closeNavigation;
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && document.body.classList.contains("navigation-open")) {
    closeNavigation();
    $("nav-toggle").focus();
  }
});
function screen(id) {
  closeNavigation();
  window.scrollTo(0, 0);
  for (const link of document.querySelectorAll("[data-screen]")) {
    if (link.dataset.screen === (id === "preview" ? "map" : id)) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  }
  for (const item of ["login", "map", "bay", "interview", "preview", "profile", "guides", "labs"])
    $(item).hidden = item !== id;
  document.body.classList.toggle("quest-active", id === "bay");
  if (id === "bay" && state) renderQuest();
  if (id === "labs") renderLabs();
  if (id === "bay" || id === "labs") setTimeout(() => fit?.fit(), 100);
  if (!routing && id !== "login") {
    const path = { guides: "guides", labs: "labs", interview: "interview", profile: "profile" }[id] ?? "";
    const url = new URL(path, base);
    if (id === "guides" && !$("guide-reader").hidden && guideData)
      url.hash = "guide=" + encodeURIComponent(guideData.id);
    if (id === "labs" && selectedLab) url.hash = "lab=" + selectedLab;
    if (id === "bay") url.hash = "quest";
    if (id === "preview") url.hash = "briefing=" + preview.quest.id;
    if (url.href !== location.href) history.pushState(null, "", url);
  }
}
function theme(mode) {
  themeMode = mode;
  storageSet("dq-theme", mode);
  document.documentElement.dataset.theme =
    mode === "system" ? (matchMedia("(prefers-color-scheme:dark)").matches ? "dark" : "light") : mode;
  $("theme").querySelector(".nav-label").textContent = t("theme." + mode);
  $("theme").setAttribute("aria-label", t("theme." + mode));
}
theme(themeMode);
$("theme").onclick = () =>
  theme(["system", "dark", "light"][(["system", "dark", "light"].indexOf(themeMode) + 1) % 3]);
matchMedia("(prefers-color-scheme:dark)").addEventListener("change", () => {
  if (themeMode === "system") theme("system");
});
$("login-form").onsubmit = (e) => {
  e.preventDefault();
  action(async () => {
    await api("login", Object.fromEntries(new FormData(e.target)));
    e.target.reset();
    await refresh();
    await route();
  });
};
$("logout").onclick = () =>
  action(async () => {
    await api("logout", {});
    state = null;
    updateInfo = null;
    renderBuildInfo();
    renderSidebar();
    preferencesUser = null;
    interviewData = interviewSignature = usersData = preview = guidesData = guideData = labData = selectedLab = null;
    readingTranslation = false;
    $("user-list").replaceChildren();
    for (const id of ["password-form", "user-form", "reset-password-form"]) $(id).reset();
    $("profile-tab").hidden = true;
    i18n.setLanguages(browserLanguage, "none");
    applyLanguage();
    disposeTerminals();
    $("active-workspace").hidden = true;
    screen("login");
  });
function navigate(link, callback) {
  $(link).onclick = async (event) => {
    event.preventDefault();
    if (!state) return screen("login");
    try {
      await callback();
    } catch (error) {
      notify(error.message);
    }
  };
}
navigate("interview-nav", async () => {
  await loadInterview();
  screen("interview");
});
navigate("guides-nav", async () => {
  guideData = null;
  $("guide-reader").hidden = true;
  $("guide-catalog").hidden = false;
  await loadGuides();
  screen("guides");
});
navigate("map-tab", () => screen("map"));
navigate("quest-tab", () => screen("bay"));
navigate("active-workspace", async () => {
  if (state?.run?.status === "active") screen("bay");
  else {
    await loadLabs();
    selectedLab = state?.labs.find((lab) => lab.slot)?.id;
    screen("labs");
  }
});
navigate("labs-nav", async () => {
  await loadLabs();
  screen("labs");
});
navigate("profile-tab", showProfile);
async function loadGuides() {
  guidesData = (await api("guides")).groups;
  renderGuides();
}
function renderGuides() {
  const query = $("guide-search").value.trim().toLocaleLowerCase();
  $("guide-groups").replaceChildren();
  let count = 0;
  for (const group of guidesData ?? []) {
    const items = group.items.filter((item) =>
      Object.values(item.titles).some((title) => title.toLocaleLowerCase().includes(query)),
    );
    if (!items.length) continue;
    const section = el("section", undefined, "card"),
      list = el("ul", undefined, "guide-topic-list");
    section.append(el("h2", t("guide.source." + group.id)));
    for (const item of items) {
      const row = el("li"),
        link = el("a", i18n.content(item.titles).text);
      link.href = new URL("guide/" + encodeURIComponent(item.id), base);
      link.onclick = (event) => {
        event.preventDefault();
        void openGuide(item.id).catch((error) => notify(error.message));
      };
      row.append(link);
      list.append(row);
      count++;
    }
    section.append(list);
    $("guide-groups").append(section);
  }
  if (!count) $("guide-groups").append(el("p", t("guide.no_results")));
}
$("guide-search").oninput = renderGuides;
async function route() {
  if (!state) return;
  routing = true;
  try {
    const fragment = new URLSearchParams(location.hash.slice(1));
    const path = location.pathname.slice(base.pathname.length);
    if (fragment.has("guide")) await openGuide(fragment.get("guide"));
    else if (fragment.has("briefing")) await openBriefing(Number(fragment.get("briefing")));
    else if (location.hash === "#quest") screen("bay");
    else if (path === "labs" || fragment.has("lab")) {
      selectedLab = state.labs.find((lab) => lab.id === fragment.get("lab"))?.id;
      await loadLabs();
      screen("labs");
    } else if (path === "guides") {
      guideData = null;
      $("guide-reader").hidden = true;
      $("guide-catalog").hidden = false;
      await loadGuides();
      screen("guides");
    } else if (path === "interview") {
      await loadInterview();
      screen("interview");
    } else if (path === "profile") await showProfile();
    else screen("map");
  } catch (error) {
    notify(error.message);
  } finally {
    routing = false;
  }
}
addEventListener("popstate", () => void route());
$("scoring-nav").onclick = () => {
  if (!state) return screen("login");
  $("scoring-content").replaceChildren();
  for (const key of [
    "scoring.formula",
    "scoring.best_rule",
    "scoring.hinted",
    "scoring.briefing_rule",
    "scoring.exam",
    "scoring.achievements",
  ])
    $("scoring-content").append(el("p", t(key, { ...state.scoring, minutes: state.scoring.fast_seconds / 60 })));
  $("scoring-modal").showModal();
};
$("profile-back").onclick = $("preview-back").onclick = () => screen("map");
async function showProfile() {
  if (!state) return screen("login");
  if (state.user.admin) {
    usersData = (await api("users")).users;
    renderUsers();
  }
  $("admin").hidden = !state.user.admin;
  screen("profile");
}
function renderUsers() {
  $("user-list").replaceChildren();
  for (const user of usersData ?? []) {
    const row = el("section", undefined, "account-row");
    row.append(
      el("strong", user.name),
      el("span", t(user.admin ? "users.admin" : "users.player")),
      el("span", t(user.enabled ? "users.enabled" : "users.disabled")),
    );
    const reset = el("button", t("users.reset"));
    reset.onclick = () => {
      $("reset-password-form").reset();
      $("reset-password-form").elements.user_id.value = user.id;
      $("reset-password-title").textContent = t("users.reset_for", { name: user.name });
      $("reset-password-form").hidden = false;
      $("reset-password-form").elements.password.focus();
    };
    const enabled = el("button", t(user.enabled ? "users.disable" : "users.enable"));
    enabled.onclick = async () => {
      if (user.enabled && !confirm(t("users.disable_confirm", { name: user.name }))) return;
      if (await action(() => api("users/enabled", { user_id: user.id, enabled: !user.enabled }))) {
        if (state) await showProfile();
      }
    };
    row.append(reset, enabled);
    $("user-list").append(row);
  }
}
$("user-form").onsubmit = async (e) => {
  e.preventDefault();
  if (await action(() => api("users", Object.fromEntries(new FormData(e.target))))) {
    e.target.reset();
    await showProfile();
    notify(t("users.saved"));
  }
};
$("password-form").onsubmit = async (e) => {
  e.preventDefault();
  if (await action(() => api("password", Object.fromEntries(new FormData(e.target))))) {
    e.target.reset();
    notify(t("profile.password_saved"));
  }
};
$("reset-password-form").onsubmit = async (e) => {
  e.preventDefault();
  const data = Object.fromEntries(new FormData(e.target));
  data.user_id = Number(data.user_id);
  if (await action(() => api("users/reset", data))) {
    e.target.reset();
    e.target.hidden = true;
    notify(t("users.saved"));
  }
};
$("cancel-password-reset").onclick = () => {
  $("reset-password-form").reset();
  $("reset-password-form").hidden = true;
};
async function openBriefing(number, mode = filters.mode, track = filters.path) {
  try {
    preview = {
      quest: await api("briefing/" + number),
      mode,
      track,
      minutes: Number($("exam-minutes").value),
    };
    readingTranslation = false;
    translationControls();
    renderPreview();
    screen("preview");
  } catch (error) {
    notify(error.message);
  }
}
function renderPreview() {
  if (!preview) return;
  const q = preview.quest;
  $("preview-title").replaceChildren(el("span", "#" + q.id));
  block(q.title, $("preview-title"));
  $("preview-mode").textContent = t("mode." + preview.mode) + (preview.mode === "track" ? " · " + preview.track : "");
  $("preview-story").replaceChildren();
  block(narrative(q.brief, q.stages[0].objectives), $("preview-story"));
  $("preview-stages").replaceChildren();
  q.stages.forEach((stage, index) => {
    const section = el("section");
    section.append(el("h3", t("preview.stage", { number: index + 1 })));
    block(narrative(stage.brief, stage.objectives), section);
    const list = el("ul");
    for (const goal of stage.objectives) {
      const li = el("li");
      block(goal, li);
      list.append(li);
    }
    section.append(list);
    $("preview-stages").append(section);
  });
  $("preview-time").textContent = t(preview.mode === "exam" ? "preview.exam_time" : "preview.estimate", {
    minutes: preview.minutes,
    min: q.estimated_minutes[0],
    max: q.estimated_minutes[1],
  });
  $("preview-dependencies").replaceChildren(
    ...["workstation", ...q.dependencies].map((name) => el("li", t("dependency." + name))),
  );
  renderFacts(q.facts, $("preview-facts"));
  $("preview-score").textContent = t("scoring.formula", state.scoring);
  $("preview-best").textContent = q.best
    ? t("scoring.best", { score: q.best.score, seconds: Math.floor(q.best.seconds), hints: q.best.hints })
    : t("scoring.no_best");
  const access = q.hint_access;
  $("preview-hint-policy").textContent = t(
    access.completed ? "hint.completed_free" : access.count ? "hint.pending" : "hint.briefing_rule",
    { count: access.count, penalty: access.count * state.scoring.hint_penalty },
  );
  $("preview-hint").hidden = access.completed || preview.mode === "exam";
  $("preview-hint").disabled = busy || access.count >= access.total || state.run?.status === "active";
  renderHints(q.hints, $("preview-hints"));
  const level = state.levels.find((item) => item.id === q.id);
  const eligible =
    preview.mode === "exam"
      ? state.progress.some((p) => p.level === q.id)
      : canRun(level, state, preview.mode, preview.track);
  const active = state.run?.status === "active";
  $("preview-run").disabled = !eligible || active || busy;
  $("preview-availability").textContent = t(
    active
      ? "preview.active"
      : eligible
        ? "preview.ready"
        : preview.mode === "exam"
          ? "preview.exam_locked"
          : "preview.locked",
  );
}
$("preview-run").onclick = () =>
  action(async () => {
    await api("start", {
      level: preview.quest.id,
      mode: preview.mode,
      track: preview.mode === "track" ? preview.track : undefined,
      minutes: preview.minutes,
    });
    preview = null;
    await refresh();
    screen("bay");
  });
$("preview-hint").onclick = async () => {
  if (busy || !preview) return;
  const access = preview.quest.hint_access;
  if (!access.count) {
    const dialog = $("hint-confirm");
    if (dialog.open) return;
    $("hint-confirm-message").textContent = t("hint.confirm", { count: 1, penalty: state.scoring.hint_penalty });
    dialog.returnValue = "cancel";
    const confirmed = new Promise((resolve) =>
      dialog.addEventListener("close", () => resolve(dialog.returnValue === "confirm"), { once: true }),
    );
    dialog.showModal();
    if (!(await confirmed)) return;
  }
  if (!preview) return;
  await action(async () => {
    preview.quest = await api("briefing/" + preview.quest.id + "/hint", { confirmed: true });
    renderPreview();
  });
  if (preview) renderPreview();
};
function renderHints(hints, node) {
  node.replaceChildren();
  for (const hint of hints) {
    const box = el("div", undefined, "hint");
    block(hint.text, box);
    const link = el("a", t("guide.link", { heading: i18n.content(hint.label).text }));
    link.href = new URL(hint.url, base);
    link.target = "_blank";
    link.rel = "noopener";
    box.append(link);
    node.append(box);
  }
}
$("exam-random").onclick = () => {
  const done = state.progress;
  if (done.length) openBriefing(done[Math.floor(Math.random() * done.length)].level, "exam");
};
$("stop").onclick = async () => {
  if (!confirm(t("quest.stop_confirm"))) return;
  if (await action(() => api("stop", {}))) {
    disposeTerminals();
    screen("bay");
  }
};
for (const [id, key] of [
  ["play-mode", "mode"],
  ["play-track", "path"],
  ["filter-track", "track"],
  ["filter-difficulty", "difficulty"],
  ["filter-status", "status"],
  ["filter-search", "search"],
]) {
  $(id).addEventListener(id === "filter-search" ? "input" : "change", async () => {
    if (id === "play-track" && $(id).value === "interview") {
      await loadInterview();
      screen("interview");
      return;
    }
    filters[key] = $(id).value;
    renderMap();
  });
}
$("check").onclick = () =>
  action(async () => {
    const result = await api("check", {});
    lastCheck = { run: result.id, ...result.check_result };
  });
$("reset").onclick = () => action(() => api("reset", {}));
$("hint").onclick = () => action(() => api("hint", {}));
function renderQuestions(questions, parent) {
  for (const question of questions) {
    const card = el("section", undefined, "interview-question");
    block(question.prompt, card);
    const points = el("ul");
    for (const point of question.points ?? []) {
      const li = el("li");
      block(point, li);
      points.append(li);
    }
    if (question.points?.length) {
      const button = el("button", t(shownAnswers.has(question.id) ? "interview.hide" : "interview.points"));
      points.hidden = !shownAnswers.has(question.id);
      button.setAttribute("aria-expanded", String(!points.hidden));
      button.onclick = () => {
        points.hidden = !points.hidden;
        if (points.hidden) shownAnswers.delete(question.id);
        else shownAnswers.add(question.id);
        button.textContent = t(points.hidden ? "interview.points" : "interview.hide");
        button.setAttribute("aria-expanded", String(!points.hidden));
      };
      card.append(button, points);
    }
    parent.append(card);
  }
}
function renderInterview() {
  for (const [name, key] of [
    ["completed", "interview-completed"],
    ["theory", "interview-theory"],
  ]) {
    const host = $(key);
    host.replaceChildren();
    const groups = interviewData?.[name] ?? [];
    if (!groups.length && name === "completed") host.append(el("p", t("interview.empty")));
    for (const group of groups) {
      const card = el("article", undefined, "card interview-topic");
      block(group.title, card);
      card.append(el("small", t("interview.source", group.book), "muted"));
      renderQuestions(group.questions, card);
      host.append(card);
    }
  }
}
async function loadInterview() {
  const signature = state.user.name + ":" + state.progress.map((p) => p.level).join(",");
  if (signature !== interviewSignature) {
    interviewData = await api("interview");
    interviewSignature = signature;
  }
  renderInterview();
}
function renderMap() {
  document.querySelector('[data-i18n="map.subtitle"]').textContent = t("map.subtitle", {
    count: state.levels.filter((x) => x.implemented).length,
    bands: 4,
  });
  const done = new Map(state.progress.map((p) => [p.level, p]));
  $("stats").replaceChildren(
    el("strong", t("level.count", { done: done.size, total: state.levels.filter((x) => x.implemented).length })),
    el("small", t("level.points", { count: state.progress.reduce((n, p) => n + p.score, 0) })),
  );
  $("path-control").hidden = filters.mode !== "track";
  $("track-filter-control").hidden = filters.mode === "track";
  $("mode-help").textContent = t("mode.help." + filters.mode);
  const visible = filterLevels(
    state.levels,
    state.progress,
    { ...filters, attempted: state.attempted_levels },
    (value) => i18n.content(value).text,
  );
  $("filter-count").textContent = t("map.matches", { count: visible.length });
  $("levels").replaceChildren();
  if (!visible.length) $("levels").append(el("p", t("map.empty")));
  for (const band of ["basics", "medium", "complex", "expert"]) {
    const group = visible.filter((l) => l.difficulty === band);
    if (!group.length) continue;
    const section = el("section", undefined, "band");
    section.append(el("h2", t("difficulty." + band)));
    const grid = el("div", undefined, "level-grid");
    for (const level of group) {
      const eligible = canRun(level, state, filters.mode, filters.path);
      const card = el(
        "article",
        undefined,
        "card level" + (!level.implemented ? " planned" : "") + (done.has(level.id) ? " done" : ""),
      );
      card.dataset.level = level.id;
      const meta = el("div", undefined, "meta");
      meta.append(
        el("span", "#" + String(level.id).padStart(2, "0") + " · " + level.track),
        el(
          "span",
          done.has(level.id)
            ? t("level.score", { score: done.get(level.id).score })
            : level.boss
              ? t("level.boss")
              : "",
        ),
      );
      const title = el("h3");
      block(level.skill, title, i18n.language);
      card.append(meta, title);
      block(level.story, card, i18n.language);
      card.append(el("small", t(eligible ? "level.eligible" : "level.preview_only")));
      const buttons = el("div", undefined, "launches"),
        open = el("button", t(level.implemented ? "level.open" : "level.coming"));
      open.disabled = !level.implemented;
      open.onclick = () => openBriefing(level.id);
      buttons.append(open);
      if (done.has(level.id)) {
        const exam = el("button", t("exam.action"));
        exam.onclick = () => openBriefing(level.id, "exam");
        buttons.append(exam);
      }
      card.append(buttons);
      grid.append(card);
    }
    section.append(grid);
    $("levels").append(section);
  }
  $("exams").replaceChildren(
    ...state.exams.map((r) =>
      el(
        "p",
        t("exam.row", {
          level: r.level,
          status: t("status." + r.status),
          score: r.score,
          date: i18n.date(r.started * 1000),
        }),
      ),
    ),
  );
  $("attempt-history").replaceChildren(
    ...state.history.map((run) =>
      el(
        "p",
        t("hint.history_row", {
          level: run.level,
          mode: t("mode." + run.mode),
          status: t("status." + run.status),
          score: run.score,
          hint: run.hints ? t("hint.used", { count: run.hints }) : t("achievement.no_hints"),
          date: i18n.date(run.started * 1000),
        }),
      ),
    ),
  );
  $("exam-random").disabled = !done.size || state.run?.status === "active";
  const examUnavailable = !done.size ? "preview.exam_locked" : state.run?.status === "active" ? "preview.active" : "";
  $("exam-availability").textContent = examUnavailable ? t(examUnavailable) : "";
  $("exam-availability").hidden = !examUnavailable;
  $("admin").hidden = !state.user.admin;
}
function renderQuest() {
  const r = state.run,
    q = state.quest;
  const view = attemptState(r);
  $("bay-summary").hidden = view.active || view.preparing;
  $("bay-grid").hidden = !view.active && !view.preparing;
  $("bay-title").hidden = !r || !q;
  $("stop").hidden = !view.showStop;
  $("bay-replay").hidden = !view.showReplay;
  $("bay-last-attempt").hidden = !view.finished;
  $("bay-finished-message").hidden = !view.finished;
  $("bay-breakdown").hidden = !r?.score_details;
  $("bay-last-attempt").textContent = view.finished
    ? t("quest.last_attempt", { level: r.level, status: t("status." + r.status), score: r.score })
    : "";
  const finishedMessage = view.finished
    ? t("quest.attempt_finished", { status: t("status." + r.status) })
    : "";
  if ($("bay-finished-message").textContent !== finishedMessage)
    $("bay-finished-message").textContent = finishedMessage;
  $("bay-breakdown").textContent = r?.score_details ? t("scoring.breakdown", r.score_details) : "";
  $("bay-replay").onclick = () => openBriefing(r.level, r.mode, r.route || q.track);
  for (const id of ["check", "reset", "stop"]) $(id).disabled = !view.active;
  if (!view.active) {
    $("topology").replaceChildren();
    if (terminalKind === "quest") disposeTerminals();
  }
  if (terminalKind === "quest") $("shared-terminal").hidden = !view.showTerminal;
  $("debrief").hidden = r?.status !== "passed";
  if (!r || !q) return;
  const active = view.active;
  $("hint-status").hidden = !r.hints;
  $("hint-status").textContent = t("hint.used", { count: r.hints });
  $("quest-tag").textContent = t("quest.tag", {
    track: q.track,
    difficulty: t("difficulty." + q.difficulty),
    mode: t("mode." + r.mode),
  });
  $("quest-title").replaceChildren(el("span", "#" + i18n.number(q.id)));
  block(q.title, $("quest-title"));
  $("brief").replaceChildren();
  block(narrative(q.brief, q.stages[0].objectives), $("brief"));
  $("stage").replaceChildren();
  block(narrative(q.stages[r.stage].brief, q.stages[r.stage].objectives), $("stage"));
  $("objectives").replaceChildren();
  q.stages[r.stage].objectives.forEach((g, i) => {
    const item = el("li", undefined, r.goals[i] ? "ok" : "");
    item.append(el("span", r.goals[i] ? "✓ " : "○ "));
    const wrap = el("span");
    block(g, wrap);
    item.append(wrap);
    $("objectives").append(item);
  });
  for (const id of ["check", "reset", "stop"]) $(id).disabled = !active;
  $("hint-box").hidden = r.mode === "exam" || !active;
  $("hint").disabled = r.hints >= state.scoring.hint_limit;
  renderHints(q.hints, $("hints"));
  $("events").replaceChildren();
  for (const event of r.events) {
    if (
      event.message?.key === "npc.confirmed" ||
      JSON.stringify(event.text) === JSON.stringify(q.stages[r.stage].brief)
    )
      continue;
    const box = el("div", undefined, "event");
    box.append(el("strong", event.who.startsWith("npc.") ? t(event.who) : event.who));
    if (event.message) {
      block(
        Object.fromEntries(
          i18n.languages.map((lang) => [
            lang,
            i18n.t(
              event.message.key,
              Object.fromEntries(
                Object.entries(event.message.values ?? {}).map(([k, v]) => [k, i18n.content(v, lang).text]),
              ),
              lang,
            ),
          ]),
        ),
        box,
      );
    } else block(event.text, box);
    $("events").append(box);
  }
  $("debrief").hidden = r.status !== "passed";
  if (q.debrief) {
    $("debrief").replaceChildren(el("h3", t("quest.closed", { score: r.score })));
    const earned = [
      !r.hints ? t("achievement.no_hints") : null,
      !r.resets ? t("achievement.no_reset") : null,
      r.ended - r.started < state.scoring.fast_seconds
        ? t("achievement.fast", { minutes: state.scoring.fast_seconds / 60 })
        : null,
    ].filter(Boolean);
    for (const name of earned) $("debrief").append(el("span", name, "badge"));
    const details = r.score_details;
    if (details) {
      if (details.floor_adjustment)
        $("debrief").append(
          el("p", t("scoring.floor", { minimum: state.scoring.minimum, adjustment: details.floor_adjustment })),
        );
      $("debrief").append(
        el(
          "p",
          t(
            r.mode === "exam"
              ? "scoring.exam"
              : !details.previous_known
                ? "scoring.previous_unknown"
                : details.previous
                  ? details.improved
                    ? "scoring.improved"
                    : "scoring.kept"
                  : "scoring.first",
            { previous: details.previous?.score ?? 0, score: r.score },
          ),
        ),
      );
    }
    block(q.debrief, $("debrief"));
    for (const guide of q.guides) {
      const a = el("a", t("guide.link", { heading: i18n.content(guide.label).text }));
      a.href = guide.url;
      a.target = "_blank";
      a.rel = "noopener";
      $("debrief").append(a, el("br"));
    }
    for (const phrase of q.phrases) block(phrase, $("debrief"));
    if (q.questions?.length) $("debrief").append(el("h3", t("quest.interview")));
    renderQuestions(q.questions ?? [], $("debrief"));
    $("debrief").append(el("h3", t("trace.title")), el("pre", r.commands.join("\n") || t("trace.empty"), "commands"));
  }
  if (active) {
    if (!$("bay").hidden) connectTerminal(r);
  } else if (terminalKind === "quest") {
    disposeTerminals();
  }
  renderFacts(q.facts);
  renderCheckFeedback(r, q);
  tick();
}
$("bay-back").onclick = () => screen("map");
function renderFacts(facts, node = $("bay-facts")) {
  node.replaceChildren(
    el("p", t("facts.network")),
    el("p", t("facts.directory")),
    el("p", t("facts.images")),
    el("p", t("facts.scope")),
  );
  for (const [key, values] of Object.entries(facts ?? {})) {
    if (!values.length) continue;
    node.append(el("strong", t("facts." + key)), el("pre", values.join("\n")));
  }
}
function renderCheckFeedback(run, quest) {
  const node = $("check-feedback");
  node.replaceChildren();
  if (!lastCheck || lastCheck.run !== run.id) return;
  const result = lastCheck;
  if (result.status !== "failed") {
    if (result.status) node.append(el("p", t("checks." + result.status)));
    return;
  }
  node.append(el("strong", t("checks.failed", { count: result.remaining.length })));
  for (const item of result.remaining) {
    const wrap = el("div", undefined, "check-failure");
    block(quest.stages[result.stage].objectives[item.objective], wrap);
    wrap.append(el("p", t("checks.reason", { code: item.code })));
    wrap.append(el("p", t(item.reason ?? "checks.cause.unsatisfied")));
    if (item.detail) {
      const diagnostic = el("details");
      diagnostic.append(el("summary", t("checks.diagnostic")), el("pre", item.detail));
      wrap.append(diagnostic);
    }
    node.append(wrap);
  }
}
function tick() {
  const r = state?.run;
  if (!r) return;
  const seconds = Math.max(
    0,
    Math.floor(
      r.status === "active"
        ? r.deadline
          ? r.deadline - Date.now() / 1000
          : Date.now() / 1000 - r.started
        : (r.ended ?? Date.now() / 1000) - r.started,
    ),
  );
  const duration =
    i18n.number(Math.floor(seconds / 60), { useGrouping: false }) +
    ":" +
    i18n.number(seconds % 60, { minimumIntegerDigits: 2, useGrouping: false });
  $("clock").textContent =
    r.status === "active"
      ? t(r.deadline ? "clock.remaining" : "clock.elapsed", { duration })
      : t("clock.ended", { status: t("status." + r.status), duration });
  const elapsed = Math.max(0, (r.status === "active" ? Date.now() / 1000 : (r.ended ?? Date.now() / 1000)) - r.started);
  $("live-score").textContent = r.preparing
    ? t("scoring.preparing")
    : t(r.status === "active" ? "scoring.current" : "quest.final_score", {
        score: r.status === "active" ? scoreBreakdown(state.scoring, elapsed, r.hints, r.resets).score : r.score,
      });
}
function connectTerminal(r, kind = "quest") {
  const destination = $(kind === "lab" ? "lab-workbench" : "bay-workbench");
  if ($("shared-terminal").parentElement !== destination) destination.append($("shared-terminal"));
  $("shared-terminal").hidden = false;
  if (terminalRun === r.id && terminalKind === kind) return;
  disposeTerminals();
  terminalRun = r.id;
  terminalKind = kind;
  terminalEndpoint = kind === "lab" ? "labs/" + r.id + "/terminal" : "terminal";
  newTerminal();
}
function disposeTerminals() {
  terminalObserver?.disconnect();
  for (const tab of terminals) {
    tab.socket.close();
    tab.term.dispose();
  }
  terminals = [];
  closingTerminals.clear();
  activeTerminal = term = fit = socket = terminalRun = null;
  $("terminal").replaceChildren();
  $("terminal-tabs").replaceChildren();
  $("new-terminal").disabled = false;
}
function selectTerminal(tab) {
  activeTerminal = tab;
  ({ term, fit, socket } = tab);
  ctrl = alt = false;
  arm();
  for (const item of terminals) {
    item.view.hidden = item !== tab;
    item.button.setAttribute("aria-selected", String(item === tab));
    item.view.setAttribute("aria-hidden", String(item !== tab));
  }
  requestAnimationFrame(() => {
    if (activeTerminal === tab) {
      tab.fit.fit();
      tab.term.focus();
    }
  });
}
function closeTerminal(tab) {
  const index = terminals.indexOf(tab);
  if (index < 0) return;
  terminals.splice(index, 1);
  if (tab.socket.readyState === 1) {
    closingTerminals.add(tab);
    tab.socket.send(JSON.stringify({ type: "close" }));
  } else tab.socket.close();
  tab.term.dispose();
  tab.view.remove();
  tab.label.remove();
  updateTerminalButton();
  if (activeTerminal === tab) {
    if (terminals.length) selectTerminal(terminals[Math.min(index, terminals.length - 1)]);
    else {
      activeTerminal = term = fit = socket = null;
    }
  }
}
function updateTerminalButton() {
  $("new-terminal").disabled = terminals.length + closingTerminals.size >= 3;
  $("new-terminal").textContent = closingTerminals.size ? t("terminal.closing") : t("terminal.new");
}
function newTerminal() {
  if (!terminalRun || terminals.length + closingTerminals.size >= 3) return;
  const tab = { id: nextTerminal++ };
  tab.view = el("div", undefined, "terminal-view");
  tab.view.setAttribute("role", "tabpanel");
  tab.view.id = "terminal-view-" + tab.id;
  tab.label = el("div", undefined, "terminal-tab");
  tab.button = el("button", t("terminal.tab", { number: tab.id }));
  tab.button.setAttribute("role", "tab");
  tab.button.setAttribute("aria-controls", tab.view.id);
  tab.button.onclick = () => selectTerminal(tab);
  const close = el("button", "×", "close-terminal");
  close.disabled = true;
  close.setAttribute("aria-label", t("terminal.close", { number: tab.id }));
  close.onclick = () => closeTerminal(tab);
  tab.label.append(tab.button, close);
  $("terminal-tabs").append(tab.label);
  $("terminal").append(tab.view);
  tab.term = new window.DQTerminal.Terminal({
    cursorBlink: true,
    fontFamily: '"DejaVu Sans Mono", monospace',
    fontSize: 13,
    scrollback: 2000,
    theme: {
      background: "#282828",
      foreground: "#d4be98",
      cursor: "#a9b665",
      selectionBackground: "#504945",
      black: "#32302f",
      red: "#ea6962",
      green: "#a9b665",
      yellow: "#d8a657",
      blue: "#7daea3",
      magenta: "#d3869b",
      cyan: "#89b482",
      white: "#d4be98",
    },
  });
  tab.fit = new window.DQTerminal.FitAddon();
  tab.term.loadAddon(tab.fit);
  tab.term.open(tab.view);
  const url = new URL(terminalEndpoint, apiPath);
  url.protocol = location.protocol === "https:" ? "wss:" : "ws:";
  tab.socket = new WebSocket(url);
  tab.socket.binaryType = "arraybuffer";
  const sendToTab = (data) => {
    if (tab.socket.readyState === 1) tab.socket.send(JSON.stringify(data));
  };
  tab.socket.onopen = () => {
    close.disabled = false;
    if (activeTerminal === tab) tab.fit.fit();
    sendToTab({ type: "resize", cols: tab.term.cols, rows: tab.term.rows });
  };
  tab.socket.onmessage = (e) => {
    const bytes = new Uint8Array(e.data);
    if (terminals.includes(tab)) tab.term.write(bytes, () => sendToTab({ type: "ack", bytes: bytes.length }));
  };
  tab.socket.onclose = () => {
    close.disabled = false;
    closingTerminals.delete(tab);
    updateTerminalButton();
    if (terminals.includes(tab)) {
      tab.term.write("\r\n\x1b[90m" + t("terminal.disconnected") + "\x1b[0m\r\n");
      tab.button.classList.add("disconnected");
    }
  };
  tab.term.onData((data) => {
    if (activeTerminal !== tab) return;
    if (ctrl || alt) {
      data = keySequence(data, ctrl, alt);
      ctrl = alt = false;
      arm();
    }
    sendToTab({ type: "input", data });
  });
  tab.term.onResize((size) => sendToTab({ type: "resize", ...size }));
  terminals.push(tab);
  selectTerminal(tab);
  updateTerminalButton();
  if (!terminalObserver) {
    terminalObserver = new ResizeObserver(() => {
      try {
        fit?.fit();
      } catch {}
    });
  }
  terminalObserver.observe($("terminal"));
}
$("new-terminal").onclick = newTerminal;
function send(data) {
  if (socket?.readyState === 1) socket.send(JSON.stringify(data));
}
function arm() {
  document.querySelector("[data-key=Ctrl]").classList.toggle("armed", ctrl);
  document.querySelector("[data-key=Alt]").classList.toggle("armed", alt);
}
for (const key of document.querySelectorAll("[data-key]")) {
  key.onpointerdown = (e) => e.preventDefault();
  key.onclick = () => {
    const name = key.dataset.key;
    if (name === "Ctrl") ctrl = !ctrl;
    else if (name === "Alt") alt = !alt;
    else {
      send({ type: "input", data: keySequence(name, ctrl, alt, term?.modes.applicationCursorKeysMode) });
      ctrl = alt = false;
    }
    arm();
    term?.focus();
  };
}
$("fullscreen").onclick = async () => {
  try {
    if (document.fullscreenElement) await document.exitFullscreen();
    else await $("terminal").parentElement.requestFullscreen();
    setTimeout(() => fit?.fit(), 100);
  } catch (e) {
    notify(e.message);
  }
};
async function topology() {
  if (
    $("bay").hidden ||
    !$("topology").closest("details").open ||
    busy ||
    state?.run?.status !== "active" ||
    state.run.preparing
  )
    return;
  try {
    const runId = state.run.id;
    const data = await api("topology");
    if (state?.run?.id !== runId || state.run.status !== "active" || state.run.preparing) return;
    const svg = $("topology");
    svg.replaceChildren();
    const nodes = data.nodes.slice(0, 12),
      columns = Math.min(4, Math.max(1, nodes.length)),
      width = 650 / columns;
    svg.setAttribute("viewBox", `0 0 650 ${Math.ceil(nodes.length / columns) * 90 + 12}`);
    for (const [i, node] of nodes.entries()) {
      const g = document.createElementNS("http://www.w3.org/2000/svg", "g");
      const good = ["Running", "Succeeded", "Synced", "Healthy", "Bound"].includes(node.state);
      for (const [tag, attrs, text] of [
        [
          "rect",
          {
            x: (i % columns) * width + 3,
            y: Math.floor(i / columns) * 90 + 15,
            width: width - 6,
            height: 72,
            rx: 9,
            class: good ? "running" : "bad",
          },
        ],
        [
          "text",
          { x: (i % columns) * width + width / 2, y: Math.floor(i / columns) * 90 + 44, "text-anchor": "middle" },
          node.name.slice(0, 17),
        ],
        [
          "text",
          { x: (i % columns) * width + width / 2, y: Math.floor(i / columns) * 90 + 67, "text-anchor": "middle" },
          node.state.slice(0, 18),
        ],
      ]) {
        const n = document.createElementNS(svg.namespaceURI, tag);
        for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v);
        if (text) n.textContent = text;
        g.append(n);
      }
      svg.append(g);
    }
  } catch {}
}
async function refresh() {
  try {
    state = await api("state");
    renderBuildInfo();
    renderSidebar();
    void refreshUpdateNotice();
    $("logout").hidden = false;
    const activeLab = state.labs?.find((lab) => lab.slot);
    $("active-workspace").hidden = state.run?.status !== "active" && !activeLab;
    $("active-workspace").textContent = t(activeLab ? "nav.active_lab" : "nav.active_bay");
    if (terminalKind === "lab" && !state.labs?.some((lab) => lab.id === terminalRun && lab.status === "running"))
      disposeTerminals();
    if (labData) renderLabs();
    $("profile-tab").hidden = false;
    const primary = state.preferences.primary ?? browserLanguage,
      translation = state.preferences.translation ?? "none";
    if (preferencesUser !== state.user.name || primary !== i18n.language || translation !== i18n.translation) {
      preferencesUser = state.user.name;
      i18n.setLanguages(primary, translation);
      applyLanguage();
    }
    renderMap();
    renderQuest();
    if (preview) renderPreview();
  } catch (e) {
    if (!state || e.status === 401) {
      state = null;
      updateInfo = null;
      renderBuildInfo();
      renderSidebar();
      usersData = null;
      readingTranslation = false;
      $("user-list").replaceChildren();
      preferencesUser = null;
      disposeTerminals();
      $("admin").hidden = true;
      $("profile-tab").hidden = true;
      $("password-form").reset();
      $("user-form").reset();
      $("reset-password-form").reset();
      screen("login");
      $("logout").hidden = true;
      $("active-workspace").hidden = true;
    } else notify(e.message);
  }
}
function buildLabel() {
  const build = state?.build;
  if (!build) return "";
  return build.version === "dev" && build.commit === "dev" ? "dev" : `${build.version} · ${build.commit}`;
}
function renderBuildInfo() {
  const label = buildLabel(),
    adminUpdate = state?.user.admin ? updateInfo : null;
  const signature = JSON.stringify([label, adminUpdate, Boolean(state?.user.admin), i18n.language]);
  if (signature === buildSignature) return;
  buildSignature = signature;
  $("sidebar-build-info").hidden = $("profile-build-info").hidden = !label;
  $("sidebar-build").textContent = $("profile-build").textContent = label;
  for (const id of ["sidebar-update", "profile-update"]) {
    const container = $(id);
    container.replaceChildren();
    container.hidden = !adminUpdate;
    if (!adminUpdate) continue;
    const notes = el("a", t("update.available", { version: adminUpdate.version }), "update-link");
    notes.href = adminUpdate.release_url;
    notes.target = "_blank";
    notes.rel = "noopener noreferrer";
    notes.setAttribute("aria-label", t("update.release_notes", { version: adminUpdate.version }));
    container.append(notes);
    if (adminUpdate.command) {
      const command = el("code", adminUpdate.command),
        copy = el("button", t("update.copy"));
      copy.type = "button";
      copy.onclick = async () => {
        try {
          await navigator.clipboard.writeText(adminUpdate.command);
          notify(t("update.copied"));
        } catch {
          notify(t("update.copy_failed"));
        }
      };
      container.append(command, copy);
    }
    if (adminUpdate.documentation_url) {
      const docs = el("a", t("update.instructions"));
      docs.href = adminUpdate.documentation_url;
      docs.target = "_blank";
      docs.rel = "noopener noreferrer";
      container.append(docs);
    }
  }
  renderSidebar();
}
async function refreshUpdateNotice() {
  if (!state?.user.admin) {
    updateInfo = null;
    renderBuildInfo();
    return;
  }
  if (updateRequest) return;
  updateRequest = true;
  const user = state.user.name;
  try {
    const data = await api("updates");
    if (state?.user.admin && state.user.name === user) updateInfo = data.update;
  } catch {
    updateInfo = null;
  } finally {
    updateRequest = false;
    renderBuildInfo();
  }
}
function hideNavigationTooltip() {
  $("navigation-tooltip").hidden = true;
  tooltipItem?.removeAttribute("aria-describedby");
  tooltipItem = null;
}
function renderSidebar() {
  const user = state?.user.name ?? null;
  if (user !== layoutUser) {
    layoutUser = user;
    document.body.classList.toggle(
      "sidebar-collapsed",
      Boolean(user && readCollapsed(sidebarKey(base.pathname, user))),
    );
  }
  const collapsed = document.body.classList.contains("sidebar-collapsed");
  $("sidebar-collapse").hidden = !user;
  $("sidebar-collapse").setAttribute("aria-expanded", String(!collapsed));
  $("sidebar-collapse").setAttribute("aria-label", t(collapsed ? "nav.expand" : "nav.collapse"));
  for (const item of document.querySelectorAll("[data-nav-icon]")) {
    const label = item.querySelector(".nav-label")?.textContent ?? item.getAttribute("aria-label");
    item.dataset.navTooltip = label;
    if (item.querySelector(".nav-label")) item.setAttribute("aria-label", label);
  }
  const brand = document.querySelector(".brand"),
    version = buildLabel();
  brand.dataset.navTooltip = version ? `${t("build.version")}: ${version}` : t("app.title");
  if (state?.user.admin && updateInfo)
    brand.dataset.navTooltip += `; ${t("update.available", { version: updateInfo.version })}`;
  brand.classList.toggle("update-available", Boolean(state?.user.admin && updateInfo));
  if (tooltipItem) {
    if (collapsed && matchMedia("(min-width: 901px)").matches) showNavigationTooltip(tooltipItem);
    else hideNavigationTooltip();
  }
}
$("sidebar-collapse").onclick = () => {
  if (!state) return;
  const next = saveCollapsed(
    sidebarKey(base.pathname, state.user.name),
    !document.body.classList.contains("sidebar-collapsed"),
  );
  document.body.classList.toggle("sidebar-collapsed", next);
  renderSidebar();
  requestAnimationFrame(() => {
    try {
      fit?.fit();
    } catch {}
  });
};
function showNavigationTooltip(item) {
  if (
    !document.body.classList.contains("sidebar-collapsed") ||
    !matchMedia("(min-width: 901px)").matches ||
    !item?.dataset.navTooltip
  )
    return;
  hideNavigationTooltip();
  tooltipItem = item;
  const tooltip = $("navigation-tooltip"),
    rect = item.getBoundingClientRect();
  tooltip.textContent = item.dataset.navTooltip;
  tooltip.style.left = `${rect.right + 8}px`;
  tooltip.style.top = `${Math.max(8, Math.min(innerHeight - 52, rect.top))}px`;
  tooltip.hidden = false;
  item.setAttribute("aria-describedby", tooltip.id);
}
for (const event of ["pointerover", "focusin"])
  document.addEventListener(event, (e) => showNavigationTooltip(e.target.closest("[data-nav-icon], .brand")));
for (const event of ["pointerout", "focusout"])
  document.addEventListener(event, (e) => {
    if (!tooltipItem?.contains(e.relatedTarget)) hideNavigationTooltip();
  });
window.addEventListener("resize", hideNavigationTooltip);
applyLanguage();
await refresh();
await route();
setInterval(() => {
  if (state && !busy) refresh();
}, 2500);
setInterval(topology, 2500);
setInterval(tick, 1000);

async function loadLabs() {
  if (!guidesData) await loadGuides();
  labData = await api("labs");
  renderLabs();
}
function renderLabs() {
  if (!labData || !state) return;
  const saved = state.labs ?? labData.saved;
  const list = $("lab-profiles");
  list.replaceChildren();
  for (const profile of labData.profiles) {
    const lab = saved.find((item) => item.profile === profile.id);
    const card = el("article", undefined, "card");
    if (profile.id === selectedProfile) card.classList.add("selected-lab");
    card.append(el("h2", i18n.content(profile.title).text), el("p", i18n.content(profile.description).text));
    if (lab) card.append(el("p", t("lab.status." + lab.status), "badge"));
    const button = el("button", t(lab ? "lab.open" : "lab.create"));
    button.onclick = () => {
      selectedProfile = profile.id;
      if (lab) {
        selectedLab = lab.id;
        screen("labs");
      } else void labOperation(() => api("labs", { profile: profile.id }));
    };
    card.append(button);
    list.append(card);
  }
  const lab = saved.find((item) => item.id === selectedLab);
  $("lab-profiles").hidden = Boolean(lab);
  $("lab-workspace").hidden = !lab;
  if (!lab) return;
  const profile = labData.profiles.find((item) => item.id === lab.profile);
  $("lab-title").textContent = i18n.content(profile.title).text;
  $("lab-status").textContent = t("lab.status." + lab.status);
  $("lab-error").textContent = lab.error ? t(lab.error) : "";
  const actions = $("lab-actions");
  actions.replaceChildren();
  const working = ["preparing", "stopping", "deleting"].includes(lab.status);
  for (const name of [lab.status === "running" ? "stop" : "start", "reset", "delete"]) {
    const button = el("button", t("lab." + name));
    button.disabled = working;
    if (name === "delete" || name === "reset") button.className = "danger";
    button.onclick = () => {
      if ((name === "reset" || name === "delete") && !confirm(t("lab.confirm." + name))) return;
      void labOperation(() => api("labs/" + lab.id, { action: name, confirmation: lab.id }));
    };
    actions.append(button);
  }
  $("lab-help").replaceChildren(el("h3", t("lab.files")), el("p", t("lab.files_help")));
  $("lab-help").append(el("pre", "cd ~/lab\nls examples"));
  for (const group of guidesData ?? [])
    for (const item of group.items) {
      if (item.profile !== lab.profile) continue;
      const link = el("a", i18n.content(item.titles).text);
      link.href = new URL("guide/" + item.id, base);
      link.onclick = (event) => {
        event.preventDefault();
        void openGuide(item.id);
      };
      $("lab-help").append(link, el("br"));
    }
  $("lab-workbench").hidden = lab.status !== "running";
  if (!$("labs").hidden && lab.status === "running") connectTerminal(lab, "lab");
}
async function labOperation(callback) {
  try {
    const lab = await callback();
    selectedLab = lab.id;
    await refresh();
    if (lab.status === "deleted") selectedLab = null;
    screen("labs");
  } catch (error) {
    notify(error.message);
  }
}
async function openGuide(name) {
  guideData = await api("guide/" + encodeURIComponent(name));
  notify("");
  renderGuide();
  screen("guides");
}
function updateGuideExpansion() {
  const disclosures = [...$("guide-reader").querySelectorAll("details")];
  const expanded = disclosures.length > 0 && disclosures.every((item) => item.open);
  $("guide-expand-all").textContent = t(expanded ? "guide.collapse_all" : "guide.expand_all");
  $("guide-expand-all").setAttribute("aria-expanded", String(expanded));
}
$("guide-reader").addEventListener("toggle", updateGuideExpansion, true);
function renderGuide() {
  if (!guideData) return;
  $("guide-reader").hidden = false;
  $("guide-catalog").hidden = true;
  $("guide-heading").textContent = i18n.content(guideData.titles).text;
  const language = readingTranslation && i18n.translation !== "none" ? i18n.translation : i18n.language;
  const content = i18n.content(guideData.content, language);
  $("guide-lesson").innerHTML = window.DQMarkdown.renderMarkdown(content.text, { wiki: guideData.wiki });
  $("guide-lesson").lang = content.language;
  void renderDiagrams($("guide-lesson"));
  $("guide-warning").textContent = guideData.lesson_stale ? t("language.stale") : "";
  $("guide-lab").hidden = !guideData.profile;
  $("guide-lab").onclick = async () => {
    await loadLabs();
    await loadGuides();
    selectedProfile = guideData.profile;
    selectedLab = state.labs.find((lab) => lab.profile === selectedProfile)?.id;
    screen("labs");
  };
  const translate = $("guide-translate");
  translate.hidden = i18n.translation === "none" || i18n.translation === i18n.language;
  translate.textContent = t(readingTranslation ? "language.main" : "language.translate", {
    language: i18n.languageName(i18n.translation === "none" ? i18n.language : i18n.translation),
  });
  translate.onclick = () => {
    readingTranslation = !readingTranslation;
    translationControls();
    renderGuide();
  };
  $("guide-reference").replaceChildren();
  let loadReference = () => {};
  const reference = i18n.content(guideData.reference, language);
  if (reference.text) {
    const details = el("details", undefined, "card");
    details.append(el("summary", t("guide.full")));
    if (Object.keys(guideData.additional ?? {}).length) {
      details.append(el("p", i18n.content(guideData.additional, language).text, "callout"));
    }
    if (guideData.full_example) {
      details.append(el("p", t("guide.full_lab")));
      details.append(
        el(
          "pre",
          "cd ~/lab/examples/" +
            guideData.full_example +
            "\nbash run.sh\nbash check.sh\n# Cleanup after observing the result:\nbash cleanup.sh",
        ),
      );
    }
    const article = el("article", undefined, "markdown");
    article.lang = reference.language;
    details.append(article);
    loadReference = () => {
      if (!article.dataset.loaded) {
        for (const part of referenceParts(reference.text)) {
          const body = el("div");
          body.innerHTML = window.DQMarkdown.renderMarkdown(part.text, { wiki: guideData.wiki });
          if (part.title) {
            const section = el("details", undefined, "reference-topic");
            section.append(el("summary", part.title), body);
            section.ontoggle = () => {
              if (section.open) void renderDiagrams(body);
            };
            article.append(section);
          } else article.append(body);
        }
        article.dataset.loaded = "true";
      }
      updateGuideExpansion();
    };
    details.ontoggle = () => {
      if (details.open) loadReference();
    };
    $("guide-reference").append(details);
  }
  $("guide-expand-all").onclick = () => {
    const reader = $("guide-reader");
    const open = ![...reader.querySelectorAll("details")].every((item) => item.open);
    if (open) loadReference();
    for (const item of reader.querySelectorAll("details")) item.open = open;
    updateGuideExpansion();
    if (open) void renderDiagrams(reader);
  };
  updateGuideExpansion();
  $("guide-used-levels").replaceChildren();
  for (const level of guideData.used_in) {
    const row = el("li"),
      link = el("a", t("guide.level", { level: level.id, title: i18n.content(level.title).text }));
    link.href = "#briefing=" + level.id;
    link.onclick = (event) => {
      event.preventDefault();
      void openBriefing(level.id);
    };
    row.append(link);
    $("guide-used-levels").append(row);
  }
}
$("guide-list-back").onclick = () => {
  guideData = null;
  $("guide-reader").hidden = true;
  $("guide-catalog").hidden = false;
  void loadGuides();
  screen("guides");
};
$("guide-lesson").addEventListener("click", followGuide);
$("guide-reference").addEventListener("click", followGuide);
function followGuide(event) {
  const link = event.target.closest("a");
  if (!link) return;
  const url = new URL(link.href, location.href);
  const prefix = new URL("guide/", base);
  if (url.origin === prefix.origin && url.pathname.startsWith(prefix.pathname)) {
    event.preventDefault();
    void openGuide(decodeURIComponent(url.pathname.slice(prefix.pathname.length)));
  }
}

$("lab-list-back").onclick = () => {
  selectedLab = null;
  screen("labs");
};
