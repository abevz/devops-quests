import test from "node:test";
import assert from "node:assert/strict";
import { diagramConfig, diagramSource } from "../web/diagrams.mjs";

test("diagram labels allow line breaks but reject active markup and config overrides", () => {
  const source = 'flowchart TD\nA["one<br/>two"] --> B["ok"]';
  assert.equal(diagramSource(source), source);
  for (const label of ["<img src=x onerror=alert(1)>", "<script>alert(1)</script>", "<br onclick=alert(1)>"])
    assert.throws(() => diagramSource(`flowchart TD\nA["${label}"]`));
  assert.throws(() => diagramSource('%%{init: {"securityLevel":"loose"}}%%\nflowchart TD\nA-->B'));
  assert.throws(() => diagramSource("---\nconfig:\n  securityLevel: loose\n---\nflowchart TD\nA-->B"));
});

test("both themes retain strict SVG-only rendering and use the game palette", () => {
  const colors = { bg: "#282828", panel: "#3c3836", surface: "#32302f", fg: "#d4be98", aqua: "#89b482" };
  for (const dark of [false, true]) {
    const config = diagramConfig(colors, dark);
    assert.equal(config.securityLevel, "strict");
    assert.equal(config.htmlLabels, false);
    assert.equal(config.startOnLoad, false);
    assert.equal(config.themeVariables.primaryTextColor, colors.fg);
    assert.equal(config.themeVariables.darkMode, dark);
    assert.ok(config.secure.includes("htmlLabels"));
  }
});
