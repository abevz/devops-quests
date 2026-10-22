// HTML is disabled at the parser, URLs use an explicit allowlist, and generated
// attributes/titles are escaped. No raw HTML or third-party plugin HTML is used.
import MarkdownIt from "markdown-it";
import hljs from "highlight.js/lib/core";
import bash from "highlight.js/lib/languages/bash";
import yaml from "highlight.js/lib/languages/yaml";
import go from "highlight.js/lib/languages/go";
import terraform from "./third-party/terraform/terraform.js";

for (const [name, syntax] of Object.entries({ bash, yaml, go, hcl: terraform.definer }))
  hljs.registerLanguage(name, syntax);
const md = new MarkdownIt({ html: false, linkify: false, typographer: false });
const escape = md.utils.escapeHtml;
md.validateLink = (url) =>
  /^https?:\/\//i.test(url) || (/^(?:\/[^/]|\.{1,2}\/|#|[\p{L}\p{N}_-])/u.test(url) && !/[\\:\x00-\x20]/.test(url));
// Remote images are unnecessary in excerpts and can leak browsing metadata.
md.renderer.rules.image = (tokens, index) => escape(tokens[index].content);
md.renderer.rules.fence = (tokens, index) => {
  const token = tokens[index];
  let language = token.info.trim().split(/\s+/)[0].toLowerCase();
  language =
    { sh: "bash", shell: "bash", yml: "yaml", terraform: "hcl", tf: "hcl", golang: "go" }[language] ?? language;
  const highlighted = hljs.getLanguage(language)
    ? hljs.highlight(token.content, { language, ignoreIllegals: true }).value
    : escape(token.content);
  const caption = language === "mermaid" ? "<figcaption>diagram</figcaption>" : "";
  return `<figure class="code-block">${caption}<pre><code class="hljs language-${escape(language)}">${highlighted}</code></pre></figure>\n`;
};

md.inline.ruler.before("link", "wiki", (state, silent) => {
  if (state.src.slice(state.pos, state.pos + 2) !== "[[") return false;
  const match = /^\[\[([^\]\n]+)\]\]/.exec(state.src.slice(state.pos));
  if (!match) return false;
  if (!silent) {
    const [target, ...labels] = match[1].split("|");
    const text = labels.join("|") || target;
    const href = state.env.wiki?.[target];
    if (href && md.validateLink(href) && !state.linkLevel) {
      const open = state.push("link_open", "a", 1);
      open.attrSet("href", href);
      const label = state.push("text", "", 0);
      label.content = text;
      state.push("link_close", "a", -1);
    } else {
      const token = state.push("text", "", 0);
      token.content = text;
    }
  }
  state.pos += match[0].length;
  return true;
});

md.core.ruler.after("inline", "callouts", (state) => {
  const stack = [];
  for (let i = 0; i < state.tokens.length; i++) {
    const token = state.tokens[i];
    if (token.type === "blockquote_open") {
      const inline = state.tokens[i + 2];
      const match =
        inline?.type === "inline" && /^\[!([\w-]+)\]([+-])?(?:[ \t]+([^\n]*))?(?:\n|$)/.exec(inline.content);
      if (!match) {
        stack.push(null);
        continue;
      }
      const kind = match[1].toLowerCase();
      const collapsible = Boolean(match[2]);
      const title = match[3] || kind[0].toUpperCase() + kind.slice(1);
      const open = collapsible
        ? `<details class="callout callout-${escape(kind)}"${match[2] === "+" ? " open" : ""}><summary>${escape(title)}</summary>\n`
        : `<aside class="callout callout-${escape(kind)}"><div class="callout-title">${escape(title)}</div>\n`;
      token.type = "html_block";
      token.content = open;
      inline.content = inline.content.slice(match[0].length);
      inline.children = [];
      md.inline.parse(inline.content, md, state.env, inline.children);
      stack.push(collapsible ? "details" : "aside");
    } else if (token.type === "blockquote_close") {
      const tag = stack.pop();
      if (tag) {
        token.type = "html_block";
        token.content = `</${tag}>\n`;
      }
    }
  }
});

export function renderMarkdown(text, options = {}) {
  return md.render(String(text ?? ""), { wiki: options.wiki ?? {} });
}
