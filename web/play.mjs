// Map filtering is presentation only. The server authorizes every Run independently.
export function canRun(level, state, mode, track) {
  if (!level.implemented) return false;
  if (mode === "free") return true;
  if (mode === "track") return (state.track_opened?.[track] ?? []).includes(level.id);
  return level.opened;
}
export function filterLevels(levels, progress, filters, content) {
  const done = new Map(progress.map((p) => [p.level, p]));
  const query = filters.search.trim().toLocaleLowerCase();
  return levels.filter((level) => {
    const track = filters.mode === "track" ? filters.path : filters.track;
    if (track && level.track !== track && !(track === "Boss" && level.boss)) return false;
    if (filters.difficulty && level.difficulty !== filters.difficulty) return false;
    const result = done.get(level.id);
    if (filters.status === "new" && (result || filters.attempted?.includes(level.id))) return false;
    if (filters.status === "passed" && !result) return false;
    if (filters.status === "hinted" && !(result?.hints > 0)) return false;
    return (
      !query ||
      [content(level.skill), content(level.story), level.track, String(level.id)]
        .join(" ")
        .toLocaleLowerCase()
        .includes(query)
    );
  });
}
export function narrative(value, objectives = []) {
  const label = /^(?:Initial success criteria|Success criteria|Цели первого этапа|Результат проверки):\s*/;
  return Object.fromEntries(
    Object.entries(value ?? {}).map(([language, text]) => {
      const goals = objectives.map((goal) => (goal[language] ?? goal.en ?? "").trim()).filter(Boolean);
      const paragraphs = text
        .split(/\n\s*\n/)
        .map((paragraph) => {
          let rest = paragraph.trim().replace(label, ""),
            matched = false;
          for (const goal of goals) {
            if (rest.startsWith(goal) && (!rest[goal.length] || /[\s;,]/.test(rest[goal.length]))) {
              rest = rest
                .slice(goal.length)
                .replace(/^\s*;\s*/, "")
                .trimStart();
              matched = true;
            }
          }
          // A criteria label alone is not evidence that the whole paragraph repeats.
          return matched ? rest : paragraph;
        })
        .filter((paragraph) => paragraph.trim());
      return [language, paragraphs.join("\n\n")];
    }),
  );
}
// The persisted attempt status is authoritative, including after a page reload.
export function attemptState(run) {
  const active = run?.status === "active";
  return {
    active: active && !run.preparing,
    preparing: active && !!run.preparing,
    finished: !!run && !active,
    showStop: active && !run.preparing,
    showTerminal: active && !run.preparing,
    showReplay: !!run && !active,
  };
}

// Only compare with the previous revealed hint, so a link can reappear after a different one.
export function showHintGuide(hints, index) {
  return index === 0 || hints[index].url !== hints[index - 1].url;
}
