// Imported only by the Guide page. Code remains the fallback and source of truth.
let library;
let sequence = 0;
let pending = Promise.resolve();

export function diagramSource(source) {
  if (
    source.length > 80000 ||
    /%%\s*\{|^\s*---/m.test(source) ||
    /<\/?[a-z!][^>]*>/i.test(source.replace(/<br\s*\/?\s*>/gi, ""))
  )
    throw new Error("Unsupported diagram markup");
  return source.replace(/<br\s*\/?\s*>/gi, "<br/>");
}

export function diagramConfig(colors, dark) {
  return {
    startOnLoad: false,
    securityLevel: "strict",
    htmlLabels: false,
    suppressErrorRendering: true,
    maxTextSize: 80000,
    maxEdges: 500,
    theme: "base",
    fontFamily: "system-ui, sans-serif",
    themeVariables: {
      darkMode: dark,
      background: colors.bg,
      primaryColor: colors.panel,
      primaryTextColor: colors.fg,
      primaryBorderColor: colors.aqua,
      secondaryColor: colors.surface,
      tertiaryColor: colors.bg,
      lineColor: colors.aqua,
      textColor: colors.fg,
      mainBkg: colors.panel,
      nodeTextColor: colors.fg,
      edgeLabelBackground: colors.surface,
      actorBkg: colors.panel,
      actorBorder: colors.aqua,
      actorTextColor: colors.fg,
      actorLineColor: colors.aqua,
      signalColor: colors.fg,
      signalTextColor: colors.fg,
      labelBoxBkgColor: colors.surface,
      labelBoxBorderColor: colors.aqua,
      labelTextColor: colors.fg,
      noteBkgColor: colors.surface,
      noteTextColor: colors.fg,
      noteBorderColor: colors.aqua,
    },
    secure: [
      "securityLevel",
      "startOnLoad",
      "htmlLabels",
      "suppressErrorRendering",
      "theme",
      "themeVariables",
      "dompurifyConfig",
    ],
  };
}

function safeSvg(source) {
  const parsed = new DOMParser().parseFromString(source, "image/svg+xml");
  if (parsed.querySelector("parsererror")) throw new Error("Invalid diagram SVG");
  const svg = parsed.documentElement;
  if (svg.localName !== "svg") throw new Error("Missing diagram SVG");
  for (const element of [svg, ...svg.querySelectorAll("*")]) {
    if (
      element.namespaceURI !== "http://www.w3.org/2000/svg" ||
      /^(script|foreignObject|image|a|iframe|object|embed)$/i.test(element.localName)
    )
      throw new Error("Active diagram markup");
    const values = [...element.attributes].map((attribute) => {
      if (/^on/i.test(attribute.name)) throw new Error("Diagram event handler");
      if (/^(?:xlink:)?href$/i.test(attribute.name) && !/^#[\w-]+$/.test(attribute.value))
        throw new Error("External diagram reference");
      return attribute.value;
    });
    if (element.localName === "style") values.push(element.textContent);
    for (const value of values) {
      if (/@import|javascript:|\\/i.test(value)) throw new Error("Unsafe diagram style");
      for (const match of value.matchAll(/url\(([^)]*)\)/gi))
        if (!/^\s*["']?#[\w-]+["']?\s*$/.test(match[1])) throw new Error("External diagram resource");
    }
  }
  svg.setAttribute("role", "img");
  svg.setAttribute("aria-label", "diagram");
  return document.importNode(svg, true);
}

async function draw(container) {
  const codes = [...container.querySelectorAll("code.language-mermaid")];
  if (!codes.length) return;
  library ??= import("./vendor/mermaid.js").then((module) => module.default);
  const mermaid = await library;
  const style = getComputedStyle(document.documentElement);
  const colors = Object.fromEntries(
    ["bg", "panel", "surface", "fg", "aqua"].map((key) => [key, style.getPropertyValue("--" + key).trim()]),
  );
  mermaid.initialize(diagramConfig(colors, document.documentElement.dataset.theme === "dark"));
  for (const code of codes) {
    const figure = code.closest("figure");
    const pre = code.closest("pre");
    if (!figure?.isConnected || !pre) continue;
    figure.querySelector(".diagram-render")?.remove();
    pre.hidden = false;
    figure.dataset.diagram = "fallback";
    try {
      const source = diagramSource(code.textContent);
      const { svg } = await mermaid.render("dq-diagram-" + ++sequence, source);
      const drawing = document.createElement("div");
      drawing.className = "diagram-render";
      drawing.append(safeSvg(svg));
      if (!figure.isConnected) continue;
      figure.insertBefore(drawing, pre);
      pre.hidden = true;
      figure.dataset.diagram = "rendered";
    } catch {
      // Keep the escaped, highlighted code and the existing "diagram" caption.
    }
  }
}

export function renderDiagrams(container) {
  pending = pending
    .catch(() => {})
    .then(() => draw(container))
    .catch(() => {});
  return pending;
}
