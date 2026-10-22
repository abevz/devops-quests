// The policy is provided by the server from devops_quests/scoring.json.
export function scoreBreakdown(policy, seconds, hints, resets) {
  const time = Math.floor(Math.max(0, seconds) / policy.seconds_per_point) * policy.time_penalty;
  const hint = hints * policy.hint_penalty;
  const reset = resets * policy.reset_penalty;
  const raw = policy.base - time - hint - reset;
  return {
    base: policy.base,
    time,
    hints: hint,
    resets: reset,
    floor_adjustment: Math.max(0, policy.minimum - raw),
    score: Math.max(policy.minimum, raw),
  };
}
