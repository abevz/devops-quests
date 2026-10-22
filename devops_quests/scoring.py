"""The score policy is shared with clients as data, never copied into UI text."""

import json
from pathlib import Path

POLICY = json.loads(Path(__file__).with_name("scoring.json").read_text())


def breakdown(seconds, hints, resets):
    time = int(max(0, seconds) / POLICY["seconds_per_point"]) * POLICY["time_penalty"]
    hint = hints * POLICY["hint_penalty"]
    reset = resets * POLICY["reset_penalty"]
    raw = POLICY["base"] - time - hint - reset
    return {
        "base": POLICY["base"],
        "time": time,
        "hints": hint,
        "resets": reset,
        "floor_adjustment": max(0, POLICY["minimum"] - raw),
        "score": max(POLICY["minimum"], raw),
    }
