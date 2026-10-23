import test from "node:test";
import assert from "node:assert/strict";
import { readCollapsed, saveCollapsed, sidebarKey } from "../web/navigation.mjs";

test("sidebar state is scoped to account and installation base", () => {
  const values = new Map(),
    access = () => ({ getItem: (k) => values.get(k), setItem: (k, v) => values.set(k, v) });
  const key = sidebarKey("/", "demo");
  assert.equal(readCollapsed(key, access), false);
  assert.equal(saveCollapsed(key, true, access), true);
  assert.equal(readCollapsed(key, access), true);
  assert.equal(readCollapsed(sidebarKey("/", "other"), access), false);
  assert.equal(readCollapsed(sidebarKey("/devops/", "demo"), access), false);
  assert.equal(saveCollapsed(key, false, access), false);
  assert.equal(readCollapsed(key, access), false);
});
test("blocked localStorage access falls back to expanded without throwing", () => {
  const blocked = () => {
    throw new Error("Storage blocked");
  };
  assert.equal(readCollapsed("layout", blocked), false);
  assert.equal(saveCollapsed("layout", true, blocked), false);
});
