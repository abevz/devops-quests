"""Native-sidecar probes retain the heartbeat test under equivalent shell spelling."""

import json
import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import ROOT


def source(goal):
    return yaml.safe_load((ROOT / "quests/101/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][goal]["check"]


def watcher(command):
    return {
        "spec": {
            "template": {
                "spec": {
                    "initContainers": [
                        {"name": "prepare"},
                        {
                            "name": "watcher",
                            "restartPolicy": "Always",
                            "startupProbe": {
                                "exec": {"command": command},
                                "periodSeconds": 1,
                                "failureThreshold": 10,
                            },
                        },
                    ]
                }
            }
        }
    }


def run(document):
    program = source(1).split("<<'DQ_HEARTBEAT'\n", 1)[1].split("\nDQ_HEARTBEAT", 1)[0]
    return subprocess.run(
        [sys.executable, "-", json.dumps(document)],
        input=program,
        text=True,
        capture_output=True,
        timeout=5,
    )


@pytest.mark.parametrize(
    "command,accepted",
    [
        (["test", "-s", "/shared/heartbeat"], True),
        (["sh", "-c", "test -s '/shared/heartbeat';"], True),
        (["/bin/sh", "-c", "exec /bin/test -s /shared/heartbeat"], True),
        (["[", "-s", "/shared/heartbeat", "]"], True),
        (["true"], False),
        (["test", "-e", "/shared/heartbeat"], False),
        (["test", "-s", "/shared/route"], False),
        (["sh", "-c", "test -s /shared/heartbeat || true"], False),
    ],
)
def test_heartbeat_accepts_equivalent_test_but_never_always_success(command, accepted):
    assert (run(watcher(command)).returncode == 0) is accepted


@pytest.mark.parametrize(
    "field,value,marker",
    [("periodSeconds", 2, "period"), ("failureThreshold", 20, "threshold")],
)
def test_supplied_startup_timing_remains_required(field, value, marker):
    doc = watcher(["test", "-s", "/shared/heartbeat"])
    doc["spec"]["template"]["spec"]["initContainers"][1]["startupProbe"][field] = value
    result = run(doc)
    assert result.returncode != 0 and "[DQ:" + marker + "]" in result.stdout


def test_restartable_sidecar_cannot_become_a_one_shot_init_container():
    doc = watcher(["test", "-s", "/shared/heartbeat"])
    doc["spec"]["template"]["spec"]["initContainers"][1].pop("restartPolicy")
    assert run(doc).returncode != 0


def test_preparation_compares_live_shared_bytes_not_the_init_argv(
    tmp_path, monkeypatch
):
    import os

    executable = tmp_path / "kubectl"
    executable.write_text(
        '#!/usr/bin/env python3\nimport os,sys\nfrom pathlib import Path\nassert sys.argv[1:]==["exec","board-pod","-c","worker","--","cat","/shared/route"]\nsys.stdout.buffer.write(Path(os.environ["DQ_TEST_ROUTE"]).read_bytes())\n'
    )
    executable.chmod(0o755)
    route = tmp_path / "route"
    route.write_bytes(b"north-101\n")
    monkeypatch.setenv("DQ_TEST_ROUTE", str(route))
    monkeypatch.setenv("PATH", str(tmp_path) + os.pathsep + os.environ["PATH"])
    code = source(0).split("<<'DQ_PREPARED'\n", 1)[1].split("\nDQ_PREPARED", 1)[0]
    pod = {
        "metadata": {"name": "board-pod"},
        "status": {
            "initContainerStatuses": [
                {"name": "prepare", "state": {"terminated": {"exitCode": 0}}}
            ]
        },
    }

    def check():
        return subprocess.run(
            [
                sys.executable,
                "-",
                json.dumps({"items": [pod]}),
                json.dumps({"data": {"route": "north-101\n"}}),
            ],
            input=code,
            text=True,
            capture_output=True,
            timeout=5,
        )

    assert check().returncode == 0
    route.write_bytes(b"wrong\n")
    assert check().returncode != 0
    route.write_bytes(b"north-101\n")
    pod["status"]["initContainerStatuses"][0]["state"]["terminated"]["exitCode"] = 1
    assert check().returncode != 0


def test_volume_defaults_are_equivalent_but_order_and_source_are_fixed():
    import re

    expression = next(
        s for s in re.findall(r"'([^']+)'", source(2)) if "as $volumes" in s
    )
    volumes = [
        {"name": "input", "configMap": {"name": "route", "defaultMode": 420}},
        {"name": "shared", "emptyDir": {}},
    ]

    def check():
        document = {"spec": {"template": {"spec": {"volumes": volumes}}}}
        return subprocess.run(
            ["jq", "-e", expression],
            input=json.dumps(document),
            text=True,
            capture_output=True,
        )

    assert check().returncode == 0
    volumes[0]["configMap"]["optional"] = False
    volumes[1]["emptyDir"]["medium"] = ""
    assert check().returncode == 0
    volumes.reverse()
    assert check().returncode != 0
    volumes.reverse()
    volumes[0]["configMap"]["defaultMode"] = 384
    assert check().returncode != 0


def test_sidecar_and_ready_worker_must_share_the_successfully_initialized_pod():
    import re

    expression = next(
        item
        for item in re.findall(r"'([^']+)'", source(3))
        if "prepare" in item and "watcher" in item and "worker" in item
    )
    pod = {
        "metadata": {},
        "status": {
            "initContainerStatuses": [
                {"name": "prepare", "state": {"terminated": {"exitCode": 0}}},
                {"name": "watcher", "started": True, "state": {"running": {}}},
            ],
            "containerStatuses": [{"name": "worker", "ready": True}],
        },
    }

    def check():
        return subprocess.run(
            ["jq", "-e", expression],
            input=json.dumps({"items": [pod]}),
            text=True,
            capture_output=True,
        )

    assert check().returncode == 0
    statuses = pod["status"]["containerStatuses"]
    statuses.insert(0, {"name": "observer", "ready": True})
    assert check().returncode == 0
    statuses[1]["ready"] = False
    assert check().returncode != 0
