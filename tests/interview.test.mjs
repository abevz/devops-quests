import test from "node:test";
import assert from "node:assert/strict";
import { filterInterview, interviewTopics } from "../web/interview.mjs";

const question = (id, prompt, point) => ({
  id,
  prompt: { en: prompt, ru: "Как работает очередь?" },
  points: [{ en: point, ru: "Задержка" }],
});
const bank = {
  quests: [
    {
      level: 1, difficulty: "basics", topic: "Kubernetes", completed: true,
      questions: [
        question("one", "How does the node work?", "Check the image digest"),
        question("two", "What does the registry store?", "An image manifest"),
      ],
    },
    {
      level: 2, difficulty: "basics", topic: "Ansible", completed: false,
      questions: [question("three", "How do handlers run?", "Notification queues")],
    },
    {
      level: 3, difficulty: "expert", topic: "Kubernetes", completed: false,
      questions: [question("four", "How does admission work?", "Compare policy outcomes")],
    },
  ],
  theory: [{
    id: "recovery", title: { en: "Recovery" },
    questions: [question("five", "How does a failover work?", "Recovery time")],
  }],
};
const filter = (values = {}, language = "en") => filterInterview(
  bank,
  { query: "", topic: "", status: "", ...values },
  (value) => value[language] ?? value.en,
  language,
);

test("the catalog counts every question by difficulty, track, quest and theory", () => {
  const result = filter();
  assert.equal(result.count, 5);
  assert.deepEqual(result.bands.map(({ difficulty, count }) => [difficulty, count]), [
    ["basics", 3], ["expert", 1],
  ]);
  assert.deepEqual(result.bands[0].topics.map(({ track, count }) => [track, count]), [
    ["Kubernetes", 2], ["Ansible", 1],
  ]);
  assert.equal(result.bands[0].topics[0].quests[0].questions.length, 2);
  assert.equal(result.theoryCount, 1);
  assert.deepEqual(interviewTopics(bank).map(({ id }) => id), [
    "quest:Kubernetes", "quest:Ansible", "theory:recovery",
  ]);
});

test("search finds prompt and key-point text in the reading language and recalculates counts", () => {
  const result = filter({ query: "  NODE   digest  " });
  assert.equal(result.count, 1);
  assert.equal(result.bands[0].count, 1);
  assert.equal(result.bands[0].topics[0].count, 1);
  assert.equal(result.bands[0].topics[0].quests[0].questions[0].id, "one");
  assert.equal(filter({ query: "КАК задержка" }, "ru").count, 5);
  assert.equal(filter({ query: "digest" }, "ru").count, 0);
  assert.equal(filter({ query: "manifest handlers" }).count, 0);
  assert.equal(filter({ query: "recovery time" }).theoryCount, 1);
});

test("topic and status filters compose without treating theory as incomplete", () => {
  assert.equal(filter({ topic: "quest:Kubernetes" }).count, 3);
  assert.equal(filter({ topic: "theory:recovery" }).count, 1);
  const completed = filter({ status: "completed" });
  assert.equal(completed.count, 2);
  assert.equal(completed.bands[0].topics[0].quests[0].completed, true);
  assert.equal(filter({ status: "incomplete" }).count, 2);
  assert.equal(filter({ status: "theory" }).count, 1);
  assert.equal(filter({ topic: "theory:recovery", status: "incomplete" }).count, 0);
  assert.equal(filter({ topic: "quest:Kubernetes", status: "incomplete", query: "policy" }).count, 1);
  assert.equal(filter({ topic: "quest:Ansible", status: "completed", query: "handlers" }).count, 0);
});
