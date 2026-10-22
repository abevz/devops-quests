// Split only real third-level headings. Code and quoted callouts stay intact.
export function referenceParts(text) {
  const parts = [{ title: "", text: "" }];
  let fence = null;
  for (const line of text.split("\n")) {
    const marker = /^(?:> ?)*\s*(`{3,}|~{3,})/.exec(line);
    if (marker) {
      if (!fence) fence = marker[1][0];
      else if (fence === marker[1][0]) fence = null;
    }
    const heading = !fence && /^### ([^#].*)$/.exec(line);
    if (heading) parts.push({ title: heading[1], text: "" });
    else parts.at(-1).text += line + "\n";
  }
  return parts.filter((part) => part.title || part.text.trim());
}
