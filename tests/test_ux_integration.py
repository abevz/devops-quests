"""Opt-in UX lifecycle matrix against real, installation-owned sandbox resources.

Unlike the general curriculum matrix, Stop uses unmodified production teardown:
the owned kind node is not kept warm, and only a synthetic profile is opened.
"""

import fcntl
import hashlib
import json
import os

import pytest

from devops_quests.catalog import ROOT, Catalog
from devops_quests.engine import Engine
from devops_quests.runtime import Runtime
from devops_quests.store import Store

pytestmark = pytest.mark.skipif(
    os.environ.get("DQ_UX_INTEGRATION") != "1",
    reason="Explicit real UX matrix opt-in required",
)
CASES = [
    (1, "normal", None),
    (2, "track", "Ansible"),
    (3, "free", None),
    (27, "free", None),
    (10, "track", "Boss"),
    (100, "free", None),
    (1, "exam", None),
]


@pytest.fixture(scope="module")
def exclusive_ux():
    path = ROOT / ".state/runtime/server.lock"
    with path.open("a") as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pytest.fail("Stop other installation sandbox users before the UX matrix")
        yield


@pytest.mark.parametrize("number,mode,track", CASES)
async def test_real_mode_stop_and_reference(
    number, mode, track, tmp_path, exclusive_ux
):
    runtime, catalog = Runtime(ROOT / ".state/runtime"), Catalog()
    store = Store(tmp_path / "profile/progress.db")
    token = store.login("admin", store.bootstrap().read_text().strip(), "synthetic")
    user = store.session(token)["user_id"]
    engine = Engine(store, catalog, runtime)
    if mode == "exam":
        # Explicit eligibility precondition; not claimed as a solved real bay.
        seed = store.create_run(user, number, "normal")
        store.finish(seed)
    before = store.progress(user)
    evidence = {
        "level": number,
        "mode": mode,
        "track": track,
        "quest_sha256": hashlib.sha256(
            (ROOT / f"quests/{number:03}/quest.yaml").read_bytes()
        ).hexdigest(),
        "stages": [],
        "finished": False,
    }
    folder = ROOT / "artifacts/ux"
    folder.mkdir(parents=True, exist_ok=True)
    own_runs = {}
    try:
        stopped = await engine.start(user, number, mode, track=track)
        own_runs[stopped["id"]] = stopped
        initial = runtime.exec(
            stopped,
            "set -euo pipefail\ncd ~/quest\n" + catalog.script(number, 0, "check"),
            check=False,
            timeout=60,
        )
        assert initial.returncode != 0, "Setup must be initially unsolved"
        result = await engine.stop(user)
        # Successful Stop already completed production teardown. A second
        # Platform cleanup cannot query namespaces after kind has stopped.
        own_runs.pop(stopped["id"])
        assert result["status"] == "abandoned" and result["score"] == 0
        assert store.progress(user) == before and store.active() == []
        assert not any(
            runtime.inspect(name) for name in runtime.names(stopped).values()
        )
        for suffix in ("home", "docker", "certs"):
            assert (
                runtime.docker(
                    "volume",
                    "inspect",
                    runtime.names(stopped)["workstation"] + "-" + suffix,
                    check=False,
                ).returncode
                != 0
            )
        evidence["stop"] = {
            "initial_fail": True,
            "abandoned": True,
            "progress_preserved": True,
            "containers_and_volumes_removed": True,
        }
        run = await engine.start(user, number, mode, track=track)
        own_runs[run["id"]] = run
        for stage in range(len(catalog.quests[number]["stages"])):
            assert run["stage"] == stage and run["status"] == "active"
            reference = ROOT / f"solutions/{number:03}/{stage}.sh"
            assert reference.is_file()
            repaired = runtime.exec(
                run,
                "set -euo pipefail\ncd ~/quest\n" + reference.read_text(),
                check=False,
                timeout=240,
            )
            assert repaired.returncode == 0, (
                f"Private reference failed at stage {stage}: exit {repaired.returncode}"
            )
            run = await engine.poll(run, final=True)
            assert run["status"] == "passed" or run["stage"] == stage + 1
            evidence["stages"].append(
                {"stage": stage, "reference_exit": 0, "canonical_checks": "PASS"}
            )
        if run["status"] == "passed":
            own_runs.pop(run["id"])
        assert run["status"] == "passed" and store.active() == []
        assert not any(runtime.inspect(name) for name in runtime.names(run).values())
        if mode == "exam":
            assert store.progress(user) == before
        elif mode == "free":
            assert store.completions(user, "campaign") == set()
            assert {p["level"] for p in store.progress(user)} == {number}
        elif mode == "track":
            assert store.completions(user, "campaign") == set()
            assert store.completions(user, "track:" + track) == {number}
        else:
            assert store.completions(user, "campaign") == {number}
        evidence["result"] = "PASS"
    finally:
        # Only IDs created by this fixture may be reclaimed, even after failure.
        for run in own_runs.values():
            runtime.teardown(run)
        evidence["finished"] = True
        (folder / f"{number:03}-{mode}.json").write_text(
            json.dumps(evidence, indent=2) + "\n"
        )
