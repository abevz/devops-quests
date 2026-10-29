"""Network policy failures keep their translated condition and raw identity."""

import json
import re
import subprocess
import sys
from copy import deepcopy

import pytest

from devops_quests.catalog import Catalog, ROOT


@pytest.fixture(scope="module")
def catalog():
    return Catalog()


def run_policy(number, policies, *, empty_pods=False):
    target = "board" if number == 119 else "shelf"
    source = (ROOT / f"quests/{number:03}/check-0.sh").read_text()
    program = source.split("<<'DQ_POLICY'\n", 1)[1].split("\nDQ_POLICY\n", 1)[0]
    pods = {
        "items": [] if empty_pods else [{"metadata": {"labels": {"app": "client"}}}]
    }
    return subprocess.run(
        [
            sys.executable,
            "-",
            json.dumps({"items": policies}),
            json.dumps(pods),
            target,
        ],
        input=program,
        capture_output=True,
        text=True,
    )


@pytest.mark.parametrize("number", [119, 120])
@pytest.mark.parametrize(
    "case",
    [
        "missing_policy",
        "missing_dns",
        "missing_target",
        "extra_flow",
        "other_policy",
        "empty_pods",
        "other_invalid",
    ],
)
def test_policy_failure_markers_are_translated(catalog, number, case):
    target = "board" if number == 119 else "shelf"
    dns = {
        "to": [
            {
                "namespaceSelector": {
                    "matchLabels": {"kubernetes.io/metadata.name": "kube-system"}
                },
                "podSelector": {"matchLabels": {"k8s-app": "kube-dns"}},
            }
        ],
        "ports": [{"port": 53, "protocol": "UDP"}, {"port": 53, "protocol": "TCP"}],
    }
    application = {
        "to": [{"podSelector": {"matchLabels": {"app": target}}}],
        "ports": [{"port": 8080, "protocol": "TCP"}],
    }
    policy = {
        "metadata": {"name": "client-egress"},
        "spec": {
            "podSelector": {"matchLabels": {"app": "client"}},
            "policyTypes": ["Egress"],
            "egress": [dns, application],
        },
    }
    policies = [deepcopy(policy)]
    if case == "missing_policy":
        policies = []
        expected = "named"
    elif case == "missing_dns":
        policies[0]["spec"]["egress"][0]["ports"] = [{"port": 53, "protocol": "UDP"}]
        expected = "missing_dns_tcp_53"
    elif case == "missing_target":
        policies[0]["spec"]["egress"].pop()
        expected = f"missing_{target}_tcp_8080"
    elif case == "extra_flow":
        policies[0]["spec"]["egress"][1]["ports"].append(
            {"port": 8081, "protocol": "TCP"}
        )
        expected = "unexpected"
    elif case == "empty_pods":
        expected = "pods"
    elif case == "other_invalid":
        policies.append(
            {
                "metadata": {"name": "bad-example"},
                "spec": {"podSelector": {}, "policyTypes": ["Egress"], "egress": [{}]},
            }
        )
        expected = "other_invalid"
    else:
        policies.append(
            {
                "metadata": {"name": "extra-example"},
                "spec": {
                    "podSelector": {},
                    "policyTypes": ["Egress"],
                    "egress": [
                        {
                            "to": [{"podSelector": {"matchLabels": {"app": target}}}],
                            "ports": [{"port": 8081}],
                        }
                    ],
                },
            }
        )
        expected = "other_egress"
    result = run_policy(number, policies, empty_pods=case == "empty_pods")
    assert result.returncode != 0
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
    assert expected in markers, result.stdout
    assert len(markers) == len(result.stdout.splitlines()), result.stdout
    if case == "other_policy":
        assert "extra-example" in result.stdout
    for marker in markers:
        assert set(catalog.public(number)["diagnostics"][marker]) >= {
            "en",
            "pl",
            "es",
            "de",
            "ru",
        }
    assert (ROOT / f"quests/{number:03}/check-0.sh").read_text() == catalog.quests[
        number
    ]["stages"][0]["objectives"][0]["check"]


@pytest.mark.parametrize("number", [119, 120])
def test_unavailable_resources_emit_localized_lines(tmp_path, catalog, number):
    import os

    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    binaries = tmp_path / "bin"
    binaries.mkdir()
    kubectl = binaries / "kubectl"
    kubectl.write_text("#!/bin/sh\nexit 1\n")
    kubectl.chmod(0o755)
    source = (ROOT / f"quests/{number:03}/check-0.sh").read_text()
    source = source.replace("/run/dq/facts/0", str(tmp_path / "missing-facts"))
    env = {
        **os.environ,
        "HOME": str(home),
        "PATH": f"{binaries}:{os.environ['PATH']}",
        "DQ_NAMESPACE": "dq-test",
    }
    result = subprocess.run(
        ["bash", "-c", source], text=True, capture_output=True, env=env, timeout=20
    )
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
    assert result.returncode != 0
    assert len(markers) == len(result.stdout.splitlines()), (
        result.stdout + result.stderr
    )
    assert {"policies", "pods", "dns", "http"} <= set(markers)
    for marker in markers:
        assert set(catalog.public(number)["diagnostics"][marker]) >= {
            "en",
            "pl",
            "es",
            "de",
            "ru",
        }
