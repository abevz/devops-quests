"""Quest transitions are driven by real sandbox checks, not editor text."""

import asyncio
import json
import logging
import random
import re

from .scoring import POLICY


class Engine:
    def __init__(self, store, catalog, runtime, max_bays=1):
        self.store, self.catalog, self.runtime = store, catalog, runtime
        self.max_bays = max_bays
        self.locks = {}
        self.start_lock = asyncio.Lock()
        self.preparing = set()
        self.aliases = json.loads((catalog.root / "images/aliases.json").read_text())

    def lock(self, run):
        return self.locks.setdefault(run["id"], asyncio.Lock())

    async def start(self, user, number=None, mode="normal", minutes=15, track=None):
        async with self.start_lock:
            return await self._start(user, number, mode, minutes, track)

    async def _start(self, user, number, mode, minutes, track):
        if (
            not isinstance(mode, str)
            or mode not in {"normal", "exam", "track", "free"}
            or not isinstance(minutes, int)
            or isinstance(minutes, bool)
            or not 1 <= minutes <= 120
            or (
                number is not None
                and (not isinstance(number, int) or isinstance(number, bool))
            )
        ):
            raise ValueError("error.invalid_exam")
        completed = {row["level"] for row in self.store.progress(user)}
        campaign = self.store.completions(user, "campaign")
        if mode == "exam":
            allowed = completed
        elif mode == "free":
            allowed = set(self.catalog.quests)
        elif mode == "track":
            if not isinstance(track, str):
                raise ValueError("error.track")
            qualified = campaign | self.store.completions(user, "track:" + track)
            allowed = self.catalog.opened(qualified, track)
        else:
            allowed = self.catalog.opened(campaign)
        if number is None and mode == "exam":
            number = random.SystemRandom().choice(sorted(allowed)) if allowed else None
        if number not in allowed:
            raise PermissionError("error.locked")
        active = self.store.active()
        if any(run["user_id"] == user for run in active):
            raise ValueError("error.active")
        if len(active) >= self.max_bays:
            raise ValueError("error.busy")
        run = self.store.create_run(
            user, number, mode, minutes, route=track if mode == "track" else ""
        )
        self.preparing.add(run["id"])
        try:
            await asyncio.to_thread(self.runtime.create, run)
            await self.setup_stage(run)
            self.store.ready(run)
        except Exception:
            self.store.update(run, status="setup_failed", ended=self.store.clock())
            await asyncio.to_thread(self.runtime.teardown, run)
            raise
        finally:
            self.preparing.discard(run["id"])
        return self.store.run(run["id"], user)

    async def setup_stage(self, run):
        script = self.catalog.script(run["level"], run["stage"], "setup")
        await asyncio.to_thread(
            self.runtime.exec,
            run,
            "set -euo pipefail\ncd ~/quest\n" + script,
            timeout=180,
        )
        quest = self.catalog.quests[run["level"]]
        facts = quest.get("immutable", {}).get(run["stage"], [])
        if facts:
            await asyncio.to_thread(self.runtime.capture_facts, run, facts)
        if run["mode"] != "exam":
            events = run["events"] + [
                {
                    "who": (
                        "npc.maya",
                        "npc.noah",
                        "npc.ira",
                    )[run["stage"] % 3],
                    "text": self.catalog.text(
                        run["level"], quest["stages"][run["stage"]]["brief"]
                    ),
                    "at": self.store.clock(),
                }
            ]
            self.store.update(run, events=events)

    async def poll(self, run, final=False):
        async with self.lock(run):
            run = self.store.run(run["id"], run["user_id"])
            if run["status"] != "active" or run["id"] in self.preparing:
                return run
            now = self.store.clock()
            reason = (
                "expired"
                if run["deadline"] and now >= run["deadline"]
                else "idle"
                if now - run["activity"] >= 1800
                else None
            )
            if reason:
                self.store.update(run, status=reason, ended=now)
                await asyncio.to_thread(self.runtime.teardown, run)
                return self.store.run(run["id"], run["user_id"])
            quest = self.catalog.quests[run["level"]]
            if run["level"] in {78, 93, 121, 123}:
                await asyncio.to_thread(self.runtime.game_controls, run)
            if run["level"] in {75, 77, 116, 117}:
                await asyncio.to_thread(self.runtime.observe, run)
            stage = quest["stages"][run["stage"]]
            goals = []
            failures = []
            for goal in stage["objectives"]:
                result = await asyncio.to_thread(
                    self.runtime.exec,
                    run,
                    "set -euo pipefail\ncd ~/quest\n" + goal["check"],
                    check=False,
                    timeout=25,
                )
                goals.append(result.returncode == 0)
                if result.returncode:
                    detail = self.redact((result.stderr or result.stdout or "")[:2000])
                    detail = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", detail)
                    detail = "".join(
                        c for c in detail if c.isprintable() or c in "\n\t"
                    )[:600]
                    failures.append(
                        {
                            "objective": len(goals) - 1,
                            "code": result.returncode,
                            "detail": detail,
                            "reason": self.probe_reason(detail),
                        }
                    )
            events = run["events"]
            if run["mode"] != "exam":
                for index, passed in enumerate(goals):
                    if passed and (
                        index >= len(run["goals"]) or not run["goals"][index]
                    ):
                        objective = stage["objectives"][index]["text"]
                        events = events[-198:] + [
                            {
                                "who": "npc.noah",
                                "at": now,
                                "message": {
                                    "key": "npc.confirmed",
                                    "values": {
                                        "objective": self.catalog.text(
                                            run["level"], objective
                                        )
                                    },
                                },
                            }
                        ]
            self.store.update(run, goals=goals, events=events)
            outcome = {"status": "failed", "stage": run["stage"], "remaining": failures}
            if all(goals):
                if run["stage"] + 1 < len(quest["stages"]):
                    self.store.update(run, stage=run["stage"] + 1, goals=[])
                    run = self.store.run(run["id"], run["user_id"])
                    await self.setup_stage(run)
                    outcome = {"status": "advanced"}
                elif final:
                    run = self.store.run(run["id"], run["user_id"])
                    run = self.store.finish(run)
                    await asyncio.to_thread(self.runtime.teardown, run)
                    run["check_result"] = {"status": "passed"}
                    return run
            result = self.store.run(run["id"], run["user_id"])
            if final:
                result["check_result"] = outcome
            return result

    async def stop(self, user):
        # Serialize against preparation/reset, then against objective probes.
        async with self.start_lock:
            run = self.store.run(user=user)
            if not run or run["status"] != "active":
                return run
            async with self.lock(run):
                run = self.store.run(run["id"], user)
                if run["status"] == "active":
                    await asyncio.to_thread(self.runtime.teardown, run)
                    self.store.update(run, status="abandoned", ended=self.store.clock())
                return self.store.run(run["id"], user)

    async def reset(self, run):
        async with self.start_lock:
            async with self.lock(run):
                run = self.store.run(run["id"], run["user_id"])
                if run["status"] != "active":
                    raise ValueError("error.no_active")
                await asyncio.to_thread(self.runtime.teardown, run)
                self.store.update(run, status="reset", ended=self.store.clock())
            fresh = await self._start(
                run["user_id"],
                run["level"],
                run["mode"],
                max(1, int((run["deadline"] - run["started"]) / 60))
                if run["deadline"]
                else 15,
                run.get("route") or None,
            )
            self.store.update(fresh, resets=run["resets"] + 1, hints=run["hints"])
            return self.store.run(fresh["id"], fresh["user_id"])

    def hint(self, run):
        if run["mode"] == "exam":
            raise PermissionError("error.exam_hint")
        if run["status"] != "active":
            raise ValueError("error.no_active")
        self.store.update(
            run,
            hints=min(POLICY["hint_limit"], run["hints"] + 1),
            activity=self.store.clock(),
        )
        return self.store.run(run["id"], run["user_id"])

    @staticmethod
    def probe_reason(detail):
        value = detail.lower()
        for key, markers in (
            (
                "timeout",
                (
                    "timed out",
                    "timeout",
                    "deadline exceeded",
                    "exceeded its progress deadline",
                ),
            ),
            ("denied", ("forbidden", "permission denied", "unauthorized")),
            ("missing", ("notfound", "not found", "no such file")),
            ("not_ready", ("not ready", "not available", "unavailable")),
            (
                "configuration",
                (
                    "invalid configuration",
                    "configuration is invalid",
                    "unsupported argument",
                    "missing required argument",
                ),
            ),
        ):
            if any(marker in value for marker in markers):
                return "checks.cause." + key
        return "checks.cause.unsatisfied" if detail else "checks.cause.no_detail"

    @staticmethod
    def redact(line):
        value = r"(?:\"[^\"]*\"|'[^']*'|[^\s,;]+)"
        line = re.sub(
            r"(?i)((?:password|token|secret|api[_-]?key)\s*[=:]\s*)" + value,
            r"\1[REDACTED]",
            line,
        )
        line = re.sub(
            r"(?i)(--(?:password|token|secret|api[-_]?key)(?:=|\s+))" + value,
            r"\1[REDACTED]",
            line,
        )
        return re.sub(r"(?i)(Bearer\s+)\S+", r"\1[REDACTED]", line)

    def command(self, run, line):
        # Store a short learning trace, never full terminal output or credentials.
        if not line.strip():
            return
        line = self.redact(line)
        tokens = re.findall(r"[A-Za-z_][A-Za-z_0-9-]*", line)
        classified = {self.aliases.get(token, token) for token in tokens}
        if any(
            command in classified
            for command in (
                "kubectl",
                "ansible",
                "tofu",
                "helm",
                "curl",
                "ssh",
                "vim",
                "nano",
                "cat",
                "sed",
                "kill",
                "docker",
            )
        ):
            commands = run["commands"][-199:] + [line[:500]]
            self.store.update(
                run,
                commands=commands,
                **(
                    {"activity": self.store.clock()}
                    if run["status"] == "active"
                    else {}
                ),
            )
        elif run["status"] == "active":
            self.store.update(run, activity=self.store.clock())

    async def background(self):
        while True:
            for run in self.store.active():
                try:
                    await self.poll(run)
                except Exception:
                    logging.getLogger(__name__).exception(
                        "Bay probe failed: %s", run["id"]
                    )
                    # Keep a failed probe distinct from a solved objective.
                    current = self.store.run(run["id"], run["user_id"])
                    if current and current["status"] == "active":
                        self.store.update(current, goals=[])
            await asyncio.sleep(2.5)
