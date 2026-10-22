"""The game agent can only start the unchanged registry of the requesting bay."""

import json
import subprocess
from types import SimpleNamespace

import pytest

from devops_quests.engine import Engine
from devops_quests.platform import Platform


@pytest.mark.parametrize(
    "payload",
    [
        {"action": "start", "name": "foreign"},
        {"action": "reboot"},
        ["start"],
        None,
        {"action": "start", "args": ["--privileged"]},
    ],
)
@pytest.mark.parametrize("level,role", [(78, "registry"), (93, "vault")])
def test_unapproved_requests_never_touch_host_docker(payload, monkeypatch, level, role):
    class Runtime:
        def exec(self, *a, **k):
            return subprocess.CompletedProcess([], 0, json.dumps(payload), "")

    files = {}
    platform = Platform(Runtime())
    monkeypatch.setattr(platform, "put", lambda run, n, text: files.update({n: text}))
    platform.game_controls({"level": level})
    assert json.loads(files[role + "-agent-status.json"])["status"] == "rejected"


@pytest.mark.parametrize("foreign", [False, True])
@pytest.mark.parametrize("level,role", [(78, "registry"), (93, "vault")])
def test_start_is_scoped_and_refuses_replacement(foreign, monkeypatch, level, role):
    calls = []

    class Runtime:
        installation = "fixture"
        network = "owned-bridge"

        def __init__(self):
            self.images = {role: role + "@sha256:fixture"}

        def names(self, run):
            return {"workstation": "owned-ws"}

        def exec(self, *a, **k):
            return subprocess.CompletedProcess([], 0, '{"action":"start"}', "")

        def inspect(self, name):
            assert name == "owned-ws-" + role
            return {
                "Config": {
                    "Image": self.images[role],
                    "Labels": {
                        "devops-quests.installation": "foreign"
                        if foreign
                        else self.installation,
                    },
                },
                "HostConfig": {"NetworkMode": self.network, "Privileged": False},
                "State": {"Running": False},
            }

        def docker(self, *args):
            calls.append(args)

    platform = Platform(Runtime())
    monkeypatch.setattr(platform, "put", lambda *a: None)
    monkeypatch.setattr(platform, "wait", lambda *a, **k: None)
    run = {"level": level, "id": "a" * 24}
    if foreign:
        with pytest.raises(RuntimeError, match="foreign or replaced"):
            platform.game_controls(run)
        assert calls == []
    else:
        platform.game_controls(run)
        assert calls == [("start", "owned-ws-" + role)]


@pytest.mark.parametrize("expired", [False, True])
@pytest.mark.parametrize("level", [78, 93])
async def test_agent_runs_before_objectives_only_for_an_active_unexpired_bay(
    expired, level
):
    calls = []
    run = {
        "id": "fixture",
        "user_id": 1,
        "level": level,
        "stage": 0,
        "status": "active",
        "mode": "exam",
        "activity": 2,
        "deadline": 1 if expired else None,
        "goals": [],
        "events": [],
    }

    class Store:
        def run(self, *args):
            return run.copy()

        def clock(self):
            return 2

        def update(self, value, **fields):
            run.update(fields)

    engine = Engine.__new__(Engine)
    engine.store = Store()
    engine.locks = {}
    engine.preparing = set()
    engine.catalog = SimpleNamespace(
        quests={
            level: {"stages": [{"objectives": [{"check": "probe actual registry"}]}]}
        }
    )
    engine.runtime = SimpleNamespace(
        game_controls=lambda run: calls.append("agent"),
        teardown=lambda run: calls.append("teardown"),
        exec=lambda *a, **k: (
            calls.append("goal") or subprocess.CompletedProcess([], 1, "", "")
        ),
    )
    await engine.poll(run)
    assert calls == (["teardown"] if expired else ["agent", "goal"])
