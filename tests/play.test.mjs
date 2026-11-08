import test from "node:test";
import assert from "node:assert/strict";
import {
  attemptState,
  canRun,
  filterLevels,
  narrative,
  renderWhenChanged,
  trackForLevel,
} from "../web/play.mjs";
const levels = [
  {
    id: 1,
    track: "Kubernetes",
    difficulty: "basics",
    skill: { en: "Service routing" },
    story: { en: "Repair a station" },
    implemented: true,
    opened: true,
  },
  {
    id: 2,
    track: "Ansible",
    difficulty: "basics",
    skill: { en: "SSH configuration" },
    story: { en: "Host setup" },
    implemented: true,
    opened: false,
  },
  {
    id: 10,
    track: "Boss",
    boss: true,
    difficulty: "medium",
    skill: { en: "Composite" },
    story: { en: "All systems" },
    implemented: true,
    opened: false,
  },
];
const state = { track_opened: { Ansible: [2] } };
test("campaign, track and free eligibility remain distinct", () => {
  assert.equal(canRun(levels[1], state, "normal"), false);
  assert.equal(canRun(levels[1], state, "track", "Ansible"), true);
  assert.equal(canRun(levels[2], state, "free"), true);
  assert.equal(canRun({ ...levels[2], implemented: false }, state, "free"), false);
});
test("briefing By track follows the quest path instead of a stale map selection", () => {
  const quest = { id: 3, track: "OpenTofu", implemented: true };
  const selectedTrack = trackForLevel(quest, "Kubernetes");
  assert.equal(selectedTrack, "OpenTofu");
  assert.equal(canRun(quest, { track_opened: { OpenTofu: [3] } }, "track", selectedTrack), true);
  assert.equal(canRun(quest, { track_opened: { Kubernetes: [3] } }, "track", selectedTrack), false);
  assert.equal(trackForLevel({ track: "Boss", boss: true }, "Boss"), "Boss");
});
test("map combines track, difficulty, completion/hints and title/topic search", () => {
  const filters = { mode: "free", track: "", difficulty: "", status: "", search: "" };
  const progress = [
    { level: 1, hints: 0 },
    { level: 2, hints: 2 },
  ];
  const select = (extra) => filterLevels(levels, progress, { ...filters, ...extra }, (x) => x.en).map((l) => l.id);
  assert.deepEqual(select({ status: "new" }), [10]);
  assert.deepEqual(select({ status: "new", attempted: [10] }), []);
  assert.deepEqual(select({ status: "hinted" }), [2]);
  assert.deepEqual(select({ track: "Ansible", difficulty: "basics", search: "HOST" }), [2]);
  assert.deepEqual(select({ mode: "track", path: "Boss" }), [10]);
  assert.deepEqual(select({ search: "missing" }), []);
});
test("brief narrative removes duplicate goals, preserving unique clauses and unknown criteria", () => {
  const goal = {
    en: "fleet.txt contains the complete sorted inventory on localhost.",
    ru: "fleet.txt содержит полный отсортированный inventory на localhost.",
  };
  const value = {
    en:
      "Inputs: rollout.yml\n\nInitial success criteria: " +
      goal.en +
      " Repair the single supplied copy task; delegate it to localhost with run_once.",
    ru:
      "Файлы: rollout.yml\n\nЦели первого этапа: " +
      goal.ru +
      " Исправьте единственную выданную copy-задачу: delegate_to localhost и run_once.",
  };
  const result = narrative(value, [goal]);
  assert.equal(
    result.en,
    "Inputs: rollout.yml\n\nRepair the single supplied copy task; delegate it to localhost with run_once.",
  );
  assert.equal(
    result.ru,
    "Файлы: rollout.yml\n\nИсправьте единственную выданную copy-задачу: delegate_to localhost и run_once.",
  );
  assert.deepEqual(narrative({ en: goal.en + "\n\nSuccess criteria: " + goal.en }, [goal]), { en: "" });
  assert.deepEqual(narrative({ en: "Success criteria: unique guidance" }, [goal]), {
    en: "Success criteria: unique guidance",
  });
});
test("finished attempts never expose live controls, including after reload", () => {
  for (const status of ["passed", "abandoned", "expired", "setup_failed", "idle"]) {
    const run = JSON.parse(JSON.stringify({ id: "attempt", status }));
    assert.deepEqual(attemptState(run), {
      active: false,
      preparing: false,
      finished: true,
      showStop: false,
      showTerminal: false,
      showReplay: true,
    });
  }
  assert.equal(attemptState(null).showReplay, false);
  assert.equal(attemptState(null).showTerminal, false);
  assert.equal(attemptState({ status: "active", preparing: true }).showStop, false);
  assert.equal(attemptState({ status: "active" }).showStop, true);
  assert.equal(attemptState({ status: "active" }).showTerminal, true);
});

test("polling keeps unchanged regions intact so text selection survives", () => {
  const node = { dataset: {}, cleared: 0, rendered: 0, replaceChildren() { this.cleared += 1; } };
  const render = (target) => { target.rendered += 1; };
  assert.equal(renderWhenChanged(node, ["en", 45, "brief"], render), true);
  assert.equal(renderWhenChanged(node, ["en", 45, "brief"], render), false);
  assert.equal(renderWhenChanged(node, ["en", 45, "brief"], render), false);
  assert.equal(node.cleared, 1);
  assert.equal(node.rendered, 1);
  assert.equal(renderWhenChanged(node, ["ru", 45, "brief"], render), true);
  assert.equal(renderWhenChanged(node, ["ru", 45, "brief v2"], render), true);
  assert.equal(node.rendered, 3);
});
