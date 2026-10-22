import test from "node:test";
import assert from "node:assert/strict";
import { referenceParts } from "../web/reference.mjs";

test("long reference separates questions without splitting code or callouts", () => {
  const parts = referenceParts(
    "Intro\n### First question\n```sh\n### shell comment\n```\n> [!question]- Answer\n> ### Quoted heading\n### Second question\nText",
  );
  assert.deepEqual(
    parts.map((part) => part.title),
    ["", "First question", "Second question"],
  );
  assert.match(parts[1].text, /### shell comment/);
  assert.match(parts[1].text, /> ### Quoted heading/);
});
