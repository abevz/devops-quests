"""Actual quest predicates accept equivalent budgets without accepting wrong workers."""

import copy
import json
import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import ROOT


CASES = [
    (34, 1, {"requests": {"cpu": "100m"}, "limits": {"cpu": "300m"}}),
    (34, 2, {"requests": {"memory": "16Mi"}, "limits": {"memory": "64Mi"}}),
    (88, 0, {"limits": {"memory": "96Mi"}}),
    (
        94,
        2,
        {
            "requests": {"cpu": "50m", "memory": "8Mi"},
            "limits": {"cpu": "50m", "memory": "32Mi"},
        },
    ),
    (112, 0, {"requests": {"cpu": "100m"}, "limits": {"cpu": "200m"}}),
]


def quantity_probe(number, goal, document):
    quest = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())
    check = quest["stages"][0]["objectives"][goal]["check"]
    program = check.split("<<'DQ_QUANTITY'\n", 1)[1].split("\nDQ_QUANTITY", 1)[0]
    return subprocess.run(
        [sys.executable, "-", json.dumps(document)],
        input=program,
        capture_output=True,
        text=True,
        timeout=5,
    )


def deployment(resources, *, sidecar=False):
    worker = {"name": "worker", "resources": copy.deepcopy(resources)}
    containers = [worker]
    if sidecar:
        containers.insert(
            0, {"name": "observer", "resources": {"limits": {"memory": "1Mi"}}}
        )
    return {"spec": {"template": {"spec": {"containers": containers}}}}


@pytest.mark.parametrize("number,goal,resources", CASES)
def test_quantity_reference_and_reordered_worker(number, goal, resources):
    assert quantity_probe(number, goal, deployment(resources)).returncode == 0
    assert (
        quantity_probe(number, goal, deployment(resources, sidecar=True)).returncode
        == 0
    )


@pytest.mark.parametrize("number,goal,resources", CASES)
def test_quantity_equivalent_units_and_unrelated_resource_keys(number, goal, resources):
    equivalent = copy.deepcopy(resources)
    aliases = {
        "100m": "100e-3",
        "200m": "0.2",
        "300m": "0.3",
        "50m": "0.05",
        "8Mi": "8388608",
        "16Mi": "16777216",
        "32Mi": "33554432",
        "64Mi": "67108864",
        "96Mi": "100663296",
    }
    for values in equivalent.values():
        for key, value in list(values.items()):
            values[key] = aliases[value]
    equivalent.setdefault("requests", {})["ephemeral-storage"] = "1Mi"
    assert (
        quantity_probe(number, goal, deployment(equivalent, sidecar=True)).returncode
        == 0
    )


@pytest.mark.parametrize("number,goal,resources", CASES)
def test_every_required_quantity_rejects_a_wrong_amount(number, goal, resources):
    for category, values in resources.items():
        for name in values:
            wrong = copy.deepcopy(resources)
            wrong[category][name] = "1"  # one core/byte is never one of these budgets
            result = quantity_probe(number, goal, deployment(wrong))
            assert result.returncode != 0, (number, goal, category, name)


@pytest.mark.parametrize("number,goal,resources", CASES)
def test_matching_decoy_cannot_replace_the_actual_worker_budget(
    number, goal, resources
):
    document = deployment(resources)
    decoy = copy.deepcopy(document["spec"]["template"]["spec"]["containers"][0])
    decoy["name"] = "observer"
    worker = document["spec"]["template"]["spec"]["containers"][0]
    worker["resources"] = {}
    document["spec"]["template"]["spec"]["containers"].insert(0, decoy)
    assert quantity_probe(number, goal, document).returncode != 0


@pytest.mark.parametrize(
    "bad", [None, True, [], {}, "NaN", "infinity", "16Mi trailing"]
)
def test_invalid_quantity_is_not_a_valid_memory_budget(bad):
    assert (
        quantity_probe(88, 0, deployment({"limits": {"memory": bad}})).returncode != 0
    )


def test_cpu_diagnostics_still_identify_both_failed_conditions():
    result = quantity_probe(112, 0, deployment({}))
    assert result.returncode != 0
    assert "[DQ:request]" in result.stdout
    assert "[DQ:limit]" in result.stdout
    assert "Traceback" not in result.stderr
