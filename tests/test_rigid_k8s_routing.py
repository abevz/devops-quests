"""Routing checks preserve effective endpoints and all original identity boundaries."""

import copy
import json
import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import ROOT


def run(number, marker, *documents):
    source = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())[
        "stages"
    ][0]["objectives"][0]["check"]
    program = source.split("<<'" + marker + "'\n", 1)[1].split("\n" + marker, 1)[0]
    return subprocess.run(
        [sys.executable, "-", *[json.dumps(d) for d in documents]],
        input=program,
        text=True,
        capture_output=True,
        timeout=5,
    )


def services():
    return {
        "items": [
            {
                "metadata": {"name": name, "uid": name + "-original"},
                "spec": {
                    "type": kind,
                    "clusterIP": ip,
                    "clusterIPs": [ip],
                    "ports": [
                        {
                            "name": "http",
                            "port": 8080,
                            "targetPort": 8080,
                            "protocol": "TCP",
                            **({"nodePort": 30080} if kind == "NodePort" else {}),
                        }
                    ],
                },
            }
            for name, kind, ip in [
                ("board-internal", "ClusterIP", "10.0.0.1"),
                ("board-headless", "ClusterIP", "None"),
                ("board-node", "NodePort", "10.0.0.2"),
            ]
        ]
    }


def recorded(live):
    return [
        {
            "name": s["metadata"]["name"],
            "uid": s["metadata"]["uid"],
            **copy.deepcopy(s["spec"]),
        }
        for s in live["items"]
    ]


def target_pods():
    return {
        "items": [
            {
                "metadata": {"labels": {"app": "board"}},
                "spec": {
                    "containers": [
                        {
                            "name": "worker",
                            "ports": [{"name": "http", "containerPort": 8080}],
                        }
                    ]
                },
            }
        ]
    }


def test_service_contract_uses_named_target_not_serialized_port_order():
    live = services()
    original = recorded(live)
    assert (
        run(106, "DQ_SERVICE_CONTRACTS", live, original, target_pods()).returncode == 0
    )
    for service in live["items"]:
        service["spec"]["ports"][0]["targetPort"] = "http"
    live["items"].reverse()
    assert (
        run(106, "DQ_SERVICE_CONTRACTS", live, original, target_pods()).returncode == 0
    )
    live["items"][0]["spec"]["ports"][0]["targetPort"] = 9090
    assert (
        run(106, "DQ_SERVICE_CONTRACTS", live, original, target_pods()).returncode != 0
    )


@pytest.mark.parametrize(
    "field,value",
    [
        ("uid", "replacement"),
        ("type", "LoadBalancer"),
        ("clusterIP", "10.0.0.99"),
        ("clusterIPs", ["10.0.0.99"]),
    ],
)
def test_service_identity_addresses_and_exposure_cannot_change(field, value):
    live = services()
    original = recorded(live)
    if field == "uid":
        live["items"][0]["metadata"][field] = value
    else:
        live["items"][0]["spec"][field] = value
    result = run(106, "DQ_SERVICE_CONTRACTS", live, original, target_pods())
    assert result.returncode != 0
    assert "[DQ:contract_board_internal_" + field.lower() + "]" in result.stdout


def ingress():
    return {
        "spec": {
            "rules": [
                {
                    "host": "station.internal",
                    "http": {
                        "paths": [
                            {
                                "path": "/",
                                "pathType": "Prefix",
                                "backend": {
                                    "service": {
                                        "name": "board",
                                        "port": {"number": 8080},
                                    }
                                },
                            }
                        ]
                    },
                }
            ]
        }
    }


def service():
    return {"spec": {"ports": [{"name": "http", "port": 8080}]}}


def test_ingress_locates_host_and_resolves_service_port_name():
    doc = ingress()
    assert run(107, "DQ_INGRESS_ROUTE", doc, service()).returncode == 0
    doc["spec"]["rules"].insert(0, {"host": "other.internal", "http": {"paths": []}})
    doc["spec"]["rules"][1]["http"]["paths"][0]["backend"]["service"]["port"] = {
        "name": "http"
    }
    assert run(107, "DQ_INGRESS_ROUTE", doc, service()).returncode == 0
    doc["spec"]["rules"][1]["http"]["paths"][0]["backend"]["service"]["name"] = "other"
    assert run(107, "DQ_INGRESS_ROUTE", doc, service()).returncode != 0


@pytest.mark.parametrize("field,value", [("path", "/other"), ("pathType", "Exact")])
def test_ingress_still_covers_root_and_subpaths(field, value):
    doc = ingress()
    doc["spec"]["rules"][0]["http"]["paths"][0][field] = value
    assert run(107, "DQ_INGRESS_ROUTE", doc, service()).returncode != 0


def test_metrics_service_matches_named_http_port_not_array_position():
    source = yaml.safe_load((ROOT / "quests/127/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][0]["check"]
    program = source.split("<<'DQ_METRICS_PORT'\n", 1)[1].split("\nDQ_METRICS_PORT", 1)[
        0
    ]
    doc = {"spec": {"ports": [{"name": "http", "port": 8080, "targetPort": 8080}]}}

    def check():
        return subprocess.run(
            [sys.executable, "-", json.dumps(doc), json.dumps(target_pods())],
            input=program,
            text=True,
            capture_output=True,
            timeout=5,
        )

    assert check().returncode == 0
    doc["spec"]["ports"].insert(0, {"name": "unrelated", "port": 9090})
    doc["spec"]["ports"][1]["targetPort"] = "http"
    assert check().returncode == 0
    doc["spec"]["ports"][1]["targetPort"] = 9090
    assert check().returncode != 0


def route_expression(marker, document):
    import re

    source = yaml.safe_load((ROOT / "quests/113/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][1]["check"]
    line = next(line for line in source.splitlines() if "[DQ:" + marker + "]" in line)
    expression = re.findall(r"'([^']+)'", line)[1]
    return subprocess.run(
        ["jq", "-e", expression],
        input=json.dumps(document),
        text=True,
        capture_output=True,
    )


def route():
    conditions = [
        {"type": "Accepted", "status": "True"},
        {"type": "ResolvedRefs", "status": "True"},
    ]
    return {
        "metadata": {"namespace": "bay"},
        "spec": {
            "parentRefs": [{"name": "station"}],
            "hostnames": ["north.station.internal"],
            "rules": [{"backendRefs": [{"name": "board", "port": 8080}]}],
        },
        "status": {
            "parents": [{"parentRef": {"name": "station"}, "conditions": conditions}]
        },
    }


def test_gateway_explicit_defaults_and_repeated_identical_host_are_equivalent():
    doc = route()
    markers = ["parent", "hostnames", "backend_name", "backend_port", "parent_both"]
    assert all(route_expression(marker, doc).returncode == 0 for marker in markers)
    doc["spec"]["parentRefs"][0].update(
        group="gateway.networking.k8s.io", kind="Gateway", namespace="bay"
    )
    doc["spec"]["hostnames"] *= 2
    doc["spec"]["rules"][0]["backendRefs"][0].update(
        group="", kind="Service", namespace="bay", weight=2
    )
    assert all(route_expression(marker, doc).returncode == 0 for marker in markers)
    doc["spec"]["rules"][0]["backendRefs"].append({"name": "other", "port": 8080})
    assert route_expression("backend_name", doc).returncode != 0


def test_gateway_requires_the_same_intended_parent_and_only_north_host():
    doc = route()
    doc["spec"]["hostnames"].append("other.station.internal")
    assert route_expression("hostnames", doc).returncode != 0
    doc = route()
    doc["spec"]["parentRefs"][0]["namespace"] = "foreign"
    assert route_expression("parent", doc).returncode != 0
    doc = route()
    doc["status"]["parents"][0]["parentRef"]["name"] = "unrelated"
    assert (
        route_expression("parent_both", doc).returncode == 0
    )  # Documented identity-proof bound.
    doc = route()
    doc["status"]["parents"] = [
        {
            "parentRef": {"name": "station"},
            "conditions": [{"type": "Accepted", "status": "True"}],
        },
        {
            "parentRef": {"name": "station"},
            "conditions": [{"type": "ResolvedRefs", "status": "True"}],
        },
    ]
    assert route_expression("parent_both", doc).returncode != 0


def test_gateway_ignores_inactive_backends_and_unrelated_parent_order():
    doc = route()
    doc["spec"]["parentRefs"].insert(0, {"name": "unrelated"})
    backend = doc["spec"]["rules"][0]["backendRefs"]
    backend.insert(0, {"name": "inactive", "port": 9090, "weight": 0})
    assert route_expression("parent", doc).returncode == 0
    assert route_expression("backend_name", doc).returncode == 0
    assert route_expression("backend_port", doc).returncode == 0
    backend[1]["weight"] = 0
    assert route_expression("backend_name", doc).returncode != 0
    assert route_expression("backend_port", doc).returncode != 0
    doc = route()
    doc["status"]["parents"][0]["parentRef"]["namespace"] = "foreign"
    assert route_expression("parent_both", doc).returncode == 0
