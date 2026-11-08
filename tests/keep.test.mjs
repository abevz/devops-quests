import test from "node:test";
import assert from "node:assert/strict";
import { objectiveGroups, renderWhenChanged } from "../web/play.mjs";

const stage = { objectives: [{ en: "Repair" }, { en: "Retain existing data" }, { en: "Deliver" }], keep: [false, true, false] };
test("keep is neutral while preserved, red on failure, and keeps its original check index", () => {
  assert.equal(objectiveGroups(stage).keep[0].status, "kept");
  const initial = objectiveGroups(stage, [false, true, false]);
  assert.deepEqual(initial.goals.map((x) => [x.index, x.status]), [[0, "pending"], [2, "pending"]]);
  assert.equal(initial.keep[0].status, "kept");
  const failure = { objective: 1, detail: "Missing [DQ:data]", reason: "checks.cause.unsatisfied" };
  const broken = objectiveGroups(stage, [true, false, false], [failure]);
  assert.equal(broken.keep[0].status, "violated");
  assert.deepEqual(broken.keep[0].failure, failure);
  assert.deepEqual(broken.goals.map((x) => x.status), ["complete", "pending"]);
  assert.equal(objectiveGroups({ objectives: stage.objectives }, [true, true, true]).keep.length, 0);
});
test("unchanged polling and unrelated keep changes preserve the goal region", () => {
  const node = { dataset: {}, cleared: 0, replaceChildren() { this.cleared++; } };
  const render = () => {};
  const first = objectiveGroups(stage, [false, true, false]);
  assert.equal(renderWhenChanged(node, [45, 0, first.goals], render), true);
  assert.equal(renderWhenChanged(node, [45, 0, objectiveGroups(stage, [false, true, false]).goals], render), false);
  assert.equal(renderWhenChanged(node, [45, 0, objectiveGroups(stage, [false, false, false]).goals], render), false);
  assert.equal(node.cleared, 1);
});
