// Present known conditions in the order of their active prerequisites.
export function conditionKeys(failure, messages = {}) {
  const candidates = failure.diagnostic_keys ??
    [...(failure.detail ?? "").matchAll(/\[DQ:([a-z0-9_]+)\]/g)].map(match => match[1]);
  return [...new Set(candidates.filter(key => Object.hasOwn(messages, key)))];
}

export function showProbeReason(reason, hasKnownConditions, finalCheck) {
  return reason !== "checks.cause.unsatisfied" || (!finalCheck && !hasKnownConditions);
}

export function checkFeedback(failures, messages, dependencies = {}) {
  const groups = failures.map(failure => ({ failure, keys: conditionKeys(failure, messages) }));
  const active = new Set(groups.flatMap(group => group.keys));
  const graph = new Map(Object.entries(dependencies));

  function preceding(key) {
    const seen = new Set([key]);
    const todo = [...(graph.get(key) ?? [])];
    for (const parent of todo) {
      if (seen.has(parent)) continue;
      seen.add(parent);
      todo.push(...(graph.get(parent) ?? []));
    }
    seen.delete(key);
    return [...seen].filter(parent => active.has(parent));
  }

  const prerequisites = new Map([...active].map(key => [key, preceding(key)]));
  const needed = new Set([...prerequisites.values()].flat());
  const start = new Set([...needed].filter(key => prerequisites.get(key).length === 0));
  const priority = key => start.has(key) ? 0 :
    prerequisites.get(key).length || Number.MAX_SAFE_INTEGER;
  const count = groups.reduce((total, group) => total + Math.max(group.keys.length, 1), 0);
  for (const group of groups) {
    group.keys.sort((left, right) => priority(left) - priority(right));
  }
  groups.sort((left, right) =>
    Math.min(Number.MAX_SAFE_INTEGER, ...left.keys.map(priority)) -
    Math.min(Number.MAX_SAFE_INTEGER, ...right.keys.map(priority))
  );
  return {
    count,
    groups,
    start,
    waiting: new Set([...active].filter(key => prerequisites.get(key).length > 0)),
  };
}
