import test from "node:test";
import assert from "node:assert/strict";
import { renderMarkdown } from "../web/markdown.mjs";

test("headings, tables, emphasis, code and quotes are rendered", () => {
  const html = renderMarkdown(
    "## Guide\n\n**Bold** *italic* `inline`\n\n| a | b |\n|---|---|\n|1|2|\n\n> quote\n\n- one\n- two\n\n```bash\necho hello\n```\n",
  );
  for (const tag of ["h2", "strong", "em", "code", "table", "blockquote", "ul"])
    assert.ok(html.includes(`<${tag}`), tag);
  assert.ok(html.includes('class="hljs'));
});

test("callouts, collapsed questions, wiki links and diagrams", () => {
  const html = renderMarkdown(
    "> [!note] Read this\n> body **bold**\n\n> [!question]- Predict\n> hidden answer\n\n[[Guide#Section|Label]] [[Absent|Plain]]\n\n```mermaid\ngraph TD; A-->B\n```",
    { wiki: { "Guide#Section": "/devops/guide/known" } },
  );
  assert.match(html, /callout-note/);
  assert.match(html, /<details class="callout callout-question"><summary>Predict<\/summary>/);
  assert.ok(!html.includes("details open"));
  assert.match(html, /href="\/devops\/guide\/known">Label<\/a>/);
  assert.ok(html.includes("Plain") && !html.includes("[["));
  assert.ok(html.includes("diagram") && html.includes("graph TD"));
});

test("raw HTML and dangerous URL schemes never become executable", () => {
  const input =
    "<script>alert(1)</script>\n<img src=x onerror=alert(1)>\n\n[x](javascript:alert%281%29) [y](data:text/html,hi) [z](file:///etc/passwd) [p](//evil.invalid) [o](obsidian://open)\n\n[good](https://example.com) [internal](/devops/guide/foo)\n\n> [!note] <img src=x onerror=alert(1)>\n> [[X|<script>bad</script>]]";
  const html = renderMarkdown(input);
  assert.ok(!/<(?:script|img|iframe|svg)\b/i.test(html));
  assert.ok(!/href="(?:javascript:|data:|file:|\/\/|obsidian:)/i.test(html));
  assert.ok(html.includes('href="https://example.com"') && html.includes('href="/devops/guide/foo"'));
});

test("bash/yaml/hcl/go highlight locally and code stays literal", () => {
  for (const [language, source] of Object.entries({
    bash: 'echo "<script>"',
    yaml: "key: true",
    hcl: 'resource "local_file" "example" { content = "ok" }',
    go: "package main\nfunc main() {}",
  })) {
    const html = renderMarkdown("```" + language + "\n" + source + "\n```");
    assert.ok(html.includes("hljs-"), language);
    assert.ok(!html.includes("<script>"));
  }
  assert.ok(renderMarkdown("`[[File|literal]]`").includes("[[File|literal]]"));
});
