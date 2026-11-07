"""Quota and admission defaults compare quantities and bind readiness to one worker."""

import json
import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import ROOT


def run(goal, marker, *documents):
    check = yaml.safe_load((ROOT / "quests/126/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][goal]["check"]
    program = check.split("<<'" + marker + "'\n", 1)[1].split("\n" + marker, 1)[0]
    return subprocess.run(
        [sys.executable, "-", *[json.dumps(doc) for doc in documents]],
        input=program,
        text=True,
        capture_output=True,
        timeout=5,
    )


def budgets():
    return {
        "requests.cpu": "200m",
        "limits.cpu": "400m",
        "requests.memory": "32Mi",
        "limits.memory": "64Mi",
        "pods": "2",
    }


@pytest.mark.parametrize("key", list(budgets()))
def test_quota_preserves_every_budget(key):
    hard = budgets()
    assert run(0, "DQ_QUOTA", {"spec": {"hard": hard}}).returncode == 0
    hard.update(
        {
            "requests.cpu": "0.2",
            "limits.cpu": "0.4",
            "requests.memory": "33554432",
            "limits.memory": "67108864",
            "count/services": "3",
        }
    )
    assert run(0, "DQ_QUOTA", {"spec": {"hard": hard}}).returncode == 0
    hard[key] = "1"
    assert run(0, "DQ_QUOTA", {"spec": {"hard": hard}}).returncode != 0


def deployment():
    return {
        "spec": {"template": {"spec": {"containers": [{"name": "worker"}]}}},
        "status": {"readyReplicas": 1},
    }


def test_container_defaults_are_found_by_type_and_worker_by_name():
    limits = {
        "spec": {
            "limits": [
                {
                    "type": "Container",
                    "default": {"cpu": "200m"},
                    "defaultRequest": {"cpu": "100m"},
                }
            ]
        }
    }
    board = deployment()
    assert run(1, "DQ_DEFAULTS", limits, board).returncode == 0
    limits["spec"]["limits"].insert(0, {"type": "Pod", "max": {"cpu": "1"}})
    container = limits["spec"]["limits"][1]
    container["default"]["cpu"] = "0.2"
    container["defaultRequest"]["cpu"] = "0.1"
    board["spec"]["template"]["spec"]["containers"].insert(
        0, {"name": "observer", "resources": {"requests": {"cpu": "1m"}}}
    )
    assert run(1, "DQ_DEFAULTS", limits, board).returncode == 0
    container["default"]["cpu"] = "300m"
    assert run(1, "DQ_DEFAULTS", limits, board).returncode != 0
    container["default"]["cpu"] = "200m"
    board["spec"]["template"]["spec"]["containers"][1]["resources"] = {
        "requests": {"cpu": "100m"}
    }
    assert run(1, "DQ_DEFAULTS", limits, board).returncode != 0


def pod():
    return {
        "metadata": {},
        "spec": {
            "containers": [
                {
                    "name": "worker",
                    "resources": {
                        "requests": {"cpu": "100m", "memory": "16Mi"},
                        "limits": {"cpu": "200m", "memory": "32Mi"},
                    },
                }
            ]
        },
        "status": {"containerStatuses": [{"name": "worker", "ready": True}]},
    }


def test_admitted_resources_and_ready_status_are_on_the_same_worker():
    original = pod()
    board = deployment()
    assert run(2, "DQ_ADMITTED", board, {"items": [original]}).returncode == 0
    worker = original["spec"]["containers"][0]
    worker["resources"]["requests"].update(cpu="0.1", memory="16777216")
    worker["resources"]["limits"].update(cpu="0.2", memory="33554432")
    original["spec"]["containers"].insert(0, {"name": "observer"})
    assert run(2, "DQ_ADMITTED", board, {"items": [original]}).returncode == 0
    original["status"]["containerStatuses"] = [
        {"name": "observer", "ready": True},
        {"name": "worker", "ready": False},
    ]
    assert run(2, "DQ_ADMITTED", board, {"items": [original]}).returncode != 0


def test_split_or_terminating_pods_cannot_supply_the_required_combination():
    first = pod()
    second = pod()
    first["spec"]["containers"][0]["resources"]["limits"]["cpu"] = "300m"
    second["spec"]["containers"][0]["resources"]["requests"]["cpu"] = "200m"
    assert (
        run(2, "DQ_ADMITTED", deployment(), {"items": [first, second]}).returncode != 0
    )
    original = pod()
    original["metadata"]["deletionTimestamp"] = "2026-11-07T00:00:00Z"
    assert run(2, "DQ_ADMITTED", deployment(), {"items": [original]}).returncode != 0
