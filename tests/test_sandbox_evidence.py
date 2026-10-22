"""Control reads stay bounded; only server observations create readonly receipts."""

import json
import os
import subprocess
import sys

import pytest

from devops_quests.sandbox_evidence import CONTROL_READER, observe


@pytest.mark.parametrize("kind", ["fifo", "symlink", "invalid", "large", "valid"])
def test_control_reader_uses_a_nonblocking_regular_file(tmp_path, kind):
    quest = tmp_path / "quest"
    quest.mkdir()
    path = quest / "registry-repair.json"
    if kind == "fifo":
        os.mkfifo(path)
    elif kind == "symlink":
        target = tmp_path / "regular.json"
        target.write_text('{"action":"start"}')
        path.symlink_to(target)
    elif kind == "invalid":
        path.write_bytes(b"\xff\x00invalid")
    elif kind == "large":
        path.write_text(" " * 5000)
    else:
        path.write_text('{"action":"start"}')
    result = subprocess.run(
        [sys.executable, "-", path.name],
        input=CONTROL_READER,
        text=True,
        capture_output=True,
        env=dict(os.environ, HOME=str(tmp_path)),
        timeout=2,
        check=False,
    )
    assert result.returncode == 0
    assert json.loads(result.stdout) == (
        {"action": "start"} if kind == "valid" else None
    )


@pytest.mark.parametrize("reason", ["DeletionByPodGC", "EvictionByEvictionAPI"])
def test_only_actual_eviction_condition_creates_receipt(tmp_path, reason):
    run = {"id": "a" * 24, "level": 77}
    client = tmp_path / "bays" / run["id"] / "client"
    initial = client / "facts/0/original-pod-uids.json"
    initial.parent.mkdir(parents=True)
    initial.write_text('["original-uid"]')

    class Runtime:
        state = tmp_path

        def namespace(self, run):
            return "dq-" + run["id"]

        def kube(self, *a, **k):
            pods = {
                "items": [
                    {
                        "metadata": {"uid": "original-uid"},
                        "status": {
                            "conditions": [
                                {
                                    "type": "DisruptionTarget",
                                    "status": "True",
                                    "reason": reason,
                                }
                            ]
                        },
                    }
                ]
            }
            return subprocess.CompletedProcess([], 0, json.dumps(pods), "")

    observe(Runtime(), run)
    receipt = client / "observations/evictions.json"
    if reason == "EvictionByEvictionAPI":
        assert json.loads(receipt.read_text()) == ["original-uid"]
        assert receipt.stat().st_mode & 0o777 == 0o444
    else:
        assert not receipt.exists()


@pytest.mark.parametrize("accepted", [False, True])
def test_manual_refresh_does_not_create_authenticated_webhook_receipt(
    tmp_path, accepted
):
    run = {"id": "a" * 24, "level": 75}
    client = tmp_path / "bays" / run["id"] / "client"
    client.mkdir(parents=True)
    repo = "http://gitea-" + run["id"] + ":3000/rail/station"
    message = (
        "Received push event repo: " + repo + ", revision: main, touchedHead: true"
    )
    event = {
        "level": "info",
        "msg": message if accepted else "Refreshing application board",
    }

    class Runtime:
        state = tmp_path

        def kube(self, *a, **k):
            return subprocess.CompletedProcess([], 0, json.dumps(event), "")

    observe(Runtime(), run)
    receipt = client / "observations/webhook.json"
    assert receipt.exists() == accepted
