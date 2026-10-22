"""Initial evidence is frozen before the learner receives the bay."""

import subprocess
from types import SimpleNamespace

import pytest

from devops_quests.engine import Engine
from devops_quests.runtime import Runtime


def test_capture_preserves_original_evidence_and_refuses_replacement(tmp_path):
    runtime = Runtime.__new__(Runtime)
    runtime.state = tmp_path
    source = ["original-digest\n"]
    runtime.exec = lambda *a: subprocess.CompletedProcess([], 0, source[0], "")
    run = {"id": "a" * 24, "stage": 0}
    runtime.capture_facts(run, ["catalog.json"])
    path = tmp_path / "bays" / run["id"] / "client/facts/0/catalog.json"
    assert path.read_text() == source[0]
    assert path.stat().st_mode & 0o777 == 0o444
    source[0] = "replacement\n"
    with pytest.raises(RuntimeError, match="overwrite frozen"):
        runtime.capture_facts(run, ["catalog.json"])
    assert path.read_text() == "original-digest\n"


@pytest.mark.parametrize("name", ["../catalog", "a/b", "$(id)", "", "a" * 65])
def test_capture_rejects_nonlocal_names_before_reading(tmp_path, name):
    runtime = Runtime.__new__(Runtime)
    runtime.state = tmp_path
    with pytest.raises(ValueError, match="filename"):
        runtime.capture_facts({"id": "a" * 24, "stage": 0}, [name])
    assert not list(tmp_path.iterdir())


async def test_production_stage_freezes_facts_after_setup_before_ready():
    events = []
    engine = Engine.__new__(Engine)
    engine.catalog = SimpleNamespace(
        script=lambda *args: "write fixture",
        quests={66: {"immutable": {0: ["catalog.json"]}}},
    )
    engine.runtime = SimpleNamespace(
        exec=lambda *a, **k: events.append("setup"),
        capture_facts=lambda *a: events.append("freeze"),
    )
    await engine.setup_stage({"id": "a" * 24, "level": 66, "stage": 0, "mode": "exam"})
    assert events == ["setup", "freeze"]
