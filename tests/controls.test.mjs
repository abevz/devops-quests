import test from "node:test";
import assert from "node:assert/strict";
import { keySequence } from "../web/controls.mjs";
test("touch terminal sticky modifiers and escape keys", () => {
  assert.equal(keySequence("c", true), "\x03");
  assert.equal(keySequence("c", false, true), "\x1bc");
  assert.equal(keySequence("Tab"), "\t");
  assert.equal(keySequence("Left"), "\x1b[D");
  assert.equal(keySequence("|"), "|");
  assert.equal(keySequence("Insert"), "\x1b[2~");
  assert.equal(keySequence("Delete"), "\x1b[3~");
  assert.equal(keySequence("Home"), "\x1b[H");
  assert.equal(keySequence("End"), "\x1b[F");
  assert.equal(keySequence("Backspace"), "\x7f");
  assert.equal(keySequence("Left", false, false, true), "\x1bOD");
  assert.equal(keySequence("Up", false, false, true), "\x1bOA");
  assert.equal(keySequence("Home", false, false, true), "\x1bOH");
  assert.equal(keySequence("End", false, false, true), "\x1bOF");
});
