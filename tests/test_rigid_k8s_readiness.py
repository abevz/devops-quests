"""Port, rollout and CPU-metric checks use effective named properties."""

import copy
import json
import re
import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import ROOT


def source(number, goal):
    return yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())[
        "stages"
    ][0]["objectives"][goal]["check"]


def run_program(number, goal, marker, *documents):
    code = (
        source(number, goal)
        .split("<<'" + marker + "'\n", 1)[1]
        .split("\n" + marker, 1)[0]
    )
    return subprocess.run(
        [sys.executable, "-", *[json.dumps(d) for d in documents]],
        input=code,
        text=True,
        capture_output=True,
        timeout=5,
    )


def board():
    return {
        "kind": "Deployment",
        "metadata": {"name": "board"},
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
    }


@pytest.mark.parametrize(
    "surge,unavailable,accepted",
    [
        (1, 0, True),
        ("50%", "0%", True),
        ("25%", "25%", True),
        ("1%", "1%", True),
        ("100%", 0, False),
        (1, "50%", False),
        (0, 0, False),
        ("nonsense", 0, False),
    ],
)
def test_effective_rolling_budget_uses_kubernetes_rounding(
    surge, unavailable, accepted
):
    document = board()
    document["spec"]["strategy"]["rollingUpdate"].update(
        maxSurge=surge, maxUnavailable=unavailable
    )
    assert (run_program(102, 0, "DQ_ROLLING", document).returncode == 0) is accepted


def test_named_worker_and_named_port_are_equivalent_but_decoys_fail():
    document = board()
    containers = document["spec"]["template"]["spec"]["containers"]
    worker = containers[0]
    worker["ports"] = [{"name": "http", "containerPort": 8080}]
    worker["readinessProbe"]["httpGet"]["port"] = "http"
    containers.insert(0, {"name": "observer"})
    assert run_program(102, 0, "DQ_ROLLING", document).returncode == 0
    containers[0]["readinessProbe"] = {"httpGet": {"port": 8080}}
    worker["ports"][0]["containerPort"] = 9090
    result = run_program(102, 0, "DQ_ROLLING", document)
    assert result.returncode != 0
    assert "[DQ:readiness]" in result.stdout


def test_release_and_live_health_endpoints_must_both_match():
    live = board()
    rendered = copy.deepcopy(live)
    assert run_program(67, 3, "DQ_READINESS", live, rendered).returncode == 0
    worker = live["spec"]["template"]["spec"]["containers"][0]
    worker["ports"] = [{"name": "http", "containerPort": 8080}]
    worker["readinessProbe"] = {"tcpSocket": {"port": "http"}}
    assert run_program(67, 3, "DQ_READINESS", live, rendered).returncode == 0
    rendered["spec"]["template"]["spec"]["containers"][0]["readinessProbe"]["httpGet"][
        "port"
    ] = 9090
    assert run_program(67, 3, "DQ_READINESS", live, rendered).returncode != 0
    worker["readinessProbe"] = {"exec": {"command": ["true"]}}
    assert run_program(67, 3, "DQ_READINESS", live, board()).returncode != 0


@pytest.mark.parametrize(
    "value,accepted",
    [(8080, True), ("8080", True), (9090, False), ("9090", False), (True, False)],
)
def test_helm_numeric_and_string_port_values_have_the_same_meaning(value, accepted):
    expression = next(
        s for s in re.findall(r"'([^']+)'", source(67, 0)) if "readinessPort" in s
    )
    result = subprocess.run(
        ["jq", "-e", expression],
        input=json.dumps({"readinessPort": value}),
        text=True,
        capture_output=True,
    )
    assert (result.returncode == 0) is accepted


def metric(name, value):
    return {
        "type": "Resource",
        "resource": {
            "name": name,
            "target": {"type": "Utilization", "averageUtilization": value},
        },
    }


def metric_probe(goal, document):
    prefix = "[.spec.metrics" if goal == 1 else "any(.status.currentMetrics"
    expression = next(
        s for s in re.findall(r"'([^']+)'", source(112, goal)) if s.startswith(prefix)
    )
    return subprocess.run(
        ["jq", "-e", expression],
        input=json.dumps(document),
        text=True,
        capture_output=True,
    )


def test_cpu_target_is_selected_by_resource_not_array_position():
    assert metric_probe(1, {"spec": {"metrics": [metric("cpu", 50)]}}).returncode == 0
    assert (
        metric_probe(
            1, {"spec": {"metrics": [metric("memory", 100), metric("cpu", 50)]}}
        ).returncode
        == 0
    )
    assert (
        metric_probe(
            1, {"spec": {"metrics": [metric("memory", 50), metric("cpu", 80)]}}
        ).returncode
        != 0
    )
    assert (
        metric_probe(
            1, {"spec": {"metrics": [metric("cpu", 50), metric("cpu", 30)]}}
        ).returncode
        != 0
    )
    assert (
        metric_probe(
            1, {"spec": {"metrics": [metric("cpu", 80), metric("cpu", 50)]}}
        ).returncode
        == 0
    )


def test_current_memory_utilization_cannot_substitute_for_cpu():
    def current(name, value):
        return {
            "type": "Resource",
            "resource": {"name": name, "current": {"averageUtilization": value}},
        }

    assert (
        metric_probe(2, {"status": {"currentMetrics": [current("cpu", 60)]}}).returncode
        == 0
    )
    assert (
        metric_probe(
            2,
            {"status": {"currentMetrics": [current("memory", 2), current("cpu", 60)]}},
        ).returncode
        == 0
    )
    assert (
        metric_probe(
            2,
            {"status": {"currentMetrics": [current("memory", 99), current("cpu", 40)]}},
        ).returncode
        != 0
    )
    assert (
        metric_probe(
            2, {"status": {"currentMetrics": [current("memory", 99)]}}
        ).returncode
        != 0
    )


def test_cpu_metric_can_target_the_named_application_container():
    target = {
        "type": "ContainerResource",
        "containerResource": {
            "name": "cpu",
            "container": "worker",
            "target": {"type": "Utilization", "averageUtilization": 50},
        },
    }
    assert metric_probe(1, {"spec": {"metrics": [target]}}).returncode == 0
    target["containerResource"]["container"] = "observer"
    assert metric_probe(1, {"spec": {"metrics": [target]}}).returncode != 0
    current = {
        "type": "ContainerResource",
        "containerResource": {
            "name": "cpu",
            "container": "worker",
            "current": {"averageUtilization": 70},
        },
    }
    assert metric_probe(2, {"status": {"currentMetrics": [current]}}).returncode == 0
    current["containerResource"]["container"] = "observer"
    assert metric_probe(2, {"status": {"currentMetrics": [current]}}).returncode != 0
