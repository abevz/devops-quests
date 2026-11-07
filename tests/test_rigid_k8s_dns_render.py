"""DNS configuration and rendered objects are located by runtime identity."""

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


def program(marker):
    return source(105, 0).split("<<'" + marker + "'\n", 1)[1].split("\n" + marker, 1)[0]


def run(marker, *arguments):
    return subprocess.run(
        [sys.executable, "-", *arguments],
        input=program(marker),
        text=True,
        capture_output=True,
        timeout=5,
    )


@pytest.mark.parametrize(
    "core,accepted",
    [
        (".:1053 { errors hosts { 10.0.0.1 north.station.internal ttl 1 } }", True),
        (
            ".:1053 {\n # same zone\n hosts {\n ttl 1\n 10.0.0.1 north.station.internal\n }\n errors\n}",
            True,
        ),
        (".:53 { errors hosts { 10.0.0.1 north.station.internal ttl 1 } }", False),
        (".:1053 { errors hosts { 10.0.0.2 north.station.internal ttl 1 } }", False),
        (".:1053 { errors hosts { 10.0.0.1 north.station.internal ttl 30 } }", False),
        (".:1053 { errors hosts { 10.0.0.1 other.internal ttl 1 } }", False),
    ],
)
def test_corefile_retains_address_zone_listener_and_ttl(core, accepted):
    assert (run("DQ_CORE", core, "10.0.0.1").returncode == 0) is accepted


def dns():
    return {
        "spec": {
            "template": {
                "spec": {
                    "containers": [
                        {
                            "name": "worker",
                            "command": ["/coredns", "-conf", "/etc/station/Corefile"],
                        }
                    ]
                }
            }
        }
    }


def dns_service():
    return {
        "spec": {
            "ports": [
                {"port": 53, "targetPort": 1053, "protocol": "UDP"},
                {"port": 53, "targetPort": 1053, "protocol": "TCP"},
            ]
        }
    }


def runtime(deployment, service):
    return run("DQ_DNS_RUNTIME", json.dumps(deployment), json.dumps(service))


def test_coredns_flag_forms_and_named_target_ports_are_equivalent():
    doc = dns()
    service = dns_service()
    assert runtime(doc, service).returncode == 0
    worker = doc["spec"]["template"]["spec"]["containers"][0]
    worker["command"] = ["/coredns"]
    worker["args"] = ["-conf=/etc/station/Corefile"]
    worker["ports"] = [
        {"name": "udp-dns", "containerPort": 1053, "protocol": "UDP"},
        {"name": "tcp-dns", "containerPort": 1053, "protocol": "TCP"},
    ]
    doc["spec"]["template"]["spec"]["containers"].insert(0, {"name": "observer"})
    service["spec"]["ports"][0]["targetPort"] = "udp-dns"
    service["spec"]["ports"][1]["targetPort"] = "tcp-dns"
    assert runtime(doc, service).returncode == 0
    worker["args"] = ["-conf=/etc/other"]
    assert runtime(doc, service).returncode != 0
    worker["args"] = ["-conf=/etc/station/Corefile"]
    worker["ports"][0]["containerPort"] = 53
    assert runtime(doc, service).returncode != 0


def rendered():
    return [
        {
            "kind": "ConfigMap",
            "metadata": {"name": "route-hash"},
            "data": {"ROUTE": "north-108"},
        },
        {
            "kind": "Deployment",
            "metadata": {"name": "board"},
            "spec": {
                "template": {
                    "spec": {
                        "containers": [
                            {
                                "name": "worker",
                                "env": [
                                    {
                                        "name": "ROUTE",
                                        "valueFrom": {
                                            "configMapKeyRef": {
                                                "name": "route-hash",
                                                "key": "ROUTE",
                                            }
                                        },
                                    }
                                ],
                            }
                        ]
                    }
                }
            },
        },
    ]


def select_cm(documents):
    expression = next(
        s
        for s in re.findall(r"'([^']+)'", source(108, 0))
        if s.startswith(". as $documents")
    )
    return subprocess.run(
        ["jq", "-c", expression],
        input=json.dumps(documents),
        text=True,
        capture_output=True,
    )


def test_rendered_configmap_is_the_one_referenced_by_named_board_worker():
    docs = rendered()
    expected = docs[0]
    assert json.loads(select_cm(docs).stdout) == expected
    docs.insert(0, {"kind": "ConfigMap", "metadata": {"name": "unrelated"}})
    docs.insert(0, {"kind": "Deployment", "metadata": {"name": "observer"}})
    docs[-1]["spec"]["template"]["spec"]["containers"].insert(0, {"name": "observer"})
    assert json.loads(select_cm(docs).stdout) == expected
    docs[-1]["spec"]["template"]["spec"]["containers"][1]["env"][0]["valueFrom"][
        "configMapKeyRef"
    ]["name"] = "missing"
    assert json.loads(select_cm(docs).stdout) == {}


@pytest.mark.parametrize(
    "body",
    [
        "hosts { 10.0.0.1 north.station.internal ttl 1 }",
        "log errors hosts { 10.0.0.1 north.station.internal ttl 1 }",
        "errors errors hosts { 10.0.0.1 north.station.internal ttl 1 }",
    ],
)
def test_corefile_keeps_the_explicit_single_errors_hosts_contract(body):
    assert run("DQ_CORE", ".:1053 { " + body + " }", "10.0.0.1").returncode != 0


def test_inherited_coredns_entrypoint_requires_the_running_binary_proof():
    document = dns()
    worker = document["spec"]["template"]["spec"]["containers"][0]
    worker.pop("command")
    worker["args"] = ["-conf=/etc/station/Corefile"]
    args = (json.dumps(document), json.dumps(dns_service()))
    assert run("DQ_DNS_RUNTIME", *args, "CoreDNS-1.13.2\nlinux/amd64").returncode == 0
    assert run("DQ_DNS_RUNTIME", *args, "busybox").returncode != 0
    worker["args"] = ["-conf=/etc/other"]
    assert (
        run(
            "DQ_DNS_RUNTIME", json.dumps(document), args[1], "CoreDNS-1.13.2"
        ).returncode
        != 0
    )


def test_existing_rendered_configmap_reference_accepts_optional_without_embedding():
    expression = next(
        s for s in re.findall(r"'([^']+)'", source(108, 1)) if "as $worker" in s
    )
    document = rendered()[1]
    worker = document["spec"]["template"]["spec"]["containers"][0]

    def check():
        return subprocess.run(
            ["jq", "-e", "--arg", "name", "route-hash", expression],
            input=json.dumps(document),
            text=True,
            capture_output=True,
        )

    assert check().returncode == 0
    worker["env"][0]["valueFrom"]["configMapKeyRef"]["optional"] = True
    document["spec"]["template"]["spec"]["containers"].insert(0, {"name": "observer"})
    assert check().returncode == 0
    worker["env"][0]["value"] = "north-108"
    assert check().returncode != 0
    worker["env"][0].pop("value")
    worker["env"].append({"name": "OTHER", "value": "unrelated"})
    assert check().returncode != 0
