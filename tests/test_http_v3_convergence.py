"""Quest 102 polls the Service until its HTTP body converges."""

import json
import os
from pathlib import Path
import subprocess
import time

import yaml

ROOT = Path(__file__).resolve().parents[1]


def http_v3_check():
    quest = yaml.safe_load((ROOT / "quests/102/quest.yaml").read_text())
    return quest["stages"][1]["objectives"][2]["check"]


def python_poll(source):
    return source.split("python3 - <<'DQ_HTTP_V3'\n", 1)[1].split("\nDQ_HTTP_V3", 1)[0]


def make_fixture(
    tmp_path, responses, *, hang_from_call=0, hang_seconds=0, raw_response=b""
):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    binaries = tmp_path / "bin"
    binaries.mkdir()
    deployment = {
        "metadata": {"uid": "fixture-deployment"},
        "spec": {
            "replicas": 2,
            "strategy": {
                "type": "RollingUpdate",
                "rollingUpdate": {"maxSurge": 1, "maxUnavailable": 0},
            },
            "template": {
                "spec": {
                    "containers": [
                        {
                            "name": "worker",
                            "readinessProbe": {"httpGet": {"port": 8080}},
                        }
                    ]
                }
            },
        },
        "status": {"readyReplicas": 2},
    }
    deployment_file = tmp_path / "deployment.json"
    deployment_file.write_text(json.dumps(deployment))
    responses_file = tmp_path / "responses.txt"
    responses_file.write_text("\n".join(responses) + "\n")
    calls_file = tmp_path / "calls.txt"
    kubectl = binaries / "kubectl"
    kubectl.write_text(
        """#!/usr/bin/env python3
import os
import sys
import time
from pathlib import Path

args = sys.argv[1:]
if args[:2] == ["get", "deployment"]:
    sys.stdout.write(Path(os.environ["DEPLOYMENT_FILE"]).read_text())
    raise SystemExit(0)
if args and args[0] == "exec":
    calls_file = Path(os.environ["CALLS_FILE"])
    count = int(calls_file.read_text()) + 1 if calls_file.exists() else 1
    calls_file.write_text(str(count))
    if count >= int(os.environ["HANG_FROM_CALL"]):
        time.sleep(float(os.environ["HANG_SECONDS"]))
    raw_response = os.environ.get("RAW_RESPONSE_HEX", "")
    if raw_response:
        sys.stdout.buffer.write(bytes.fromhex(raw_response))
        raise SystemExit(0)
    responses = Path(os.environ["RESPONSES_FILE"]).read_text().splitlines()
    print(responses[min(count - 1, len(responses) - 1)])
    raise SystemExit(0)
raise SystemExit(99)
"""
    )
    kubectl.chmod(0o755)
    env = {
        **os.environ,
        "HOME": str(home),
        "PATH": f"{binaries}{os.pathsep}{os.environ['PATH']}",
        "DEPLOYMENT_FILE": str(deployment_file),
        "RESPONSES_FILE": str(responses_file),
        "CALLS_FILE": str(calls_file),
        "HANG_FROM_CALL": str(hang_from_call),
        "HANG_SECONDS": str(hang_seconds),
        "RAW_RESPONSE_HEX": raw_response.hex(),
    }
    return env, calls_file


def test_http_v3_poll_passes_after_service_returns_old_body(tmp_path):
    env, calls_file = make_fixture(tmp_path, ["north-102", "north-102-v3"])
    result = subprocess.run(
        ["bash", "-c", http_v3_check()],
        text=True,
        capture_output=True,
        env=env,
        timeout=8,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert not result.stdout
    assert calls_file.read_text().strip() == "2"


def test_http_v3_hung_request_is_bounded_and_never_v3_fails(tmp_path):
    env, calls_file = make_fixture(
        tmp_path, ["north-102"], hang_from_call=2, hang_seconds=10
    )
    started = time.monotonic()
    result = subprocess.run(
        ["bash", "-c", http_v3_check()],
        text=True,
        capture_output=True,
        env=env,
        timeout=8,
    )
    elapsed = time.monotonic() - started

    assert result.returncode == 1
    assert 'last body: "north-102"' in result.stdout
    assert "[DQ:http_v3]" in result.stdout
    assert int(calls_file.read_text().strip()) >= 2
    assert 3.5 <= elapsed < 5


def test_http_v3_invalid_utf8_body_is_escaped_without_a_traceback(tmp_path):
    env, _ = make_fixture(
        tmp_path, ["unused"], raw_response=b"old\nbody\x01\xff"
    )
    result = subprocess.run(
        ["bash", "-c", http_v3_check()],
        text=True,
        capture_output=True,
        env=env,
        timeout=8,
    )

    assert result.returncode == 1
    assert 'last body: "old\\nbody\\u0001\\ufffd"' in result.stdout
    assert "[DQ:http_v3]" in result.stdout
    assert result.stdout.count("\n") == 1
    assert "Traceback" not in result.stdout + result.stderr


def test_quest_objective_and_stage_check_use_the_same_http_poll():
    objective = python_poll(http_v3_check())
    stage_check = (ROOT / "quests/102/check-1.sh").read_text()

    assert objective == python_poll(stage_check)
