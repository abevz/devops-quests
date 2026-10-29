"""Bounded egress comparisons accept equivalent rule shapes without broadening."""

import json
import subprocess
import sys
from copy import deepcopy

import pytest

from devops_quests.catalog import ROOT


@pytest.fixture
def policy():
    return {
        "metadata": {"name": "client-egress"},
        "spec": {
            "podSelector": {"matchLabels": {"app": "client"}},
            "policyTypes": ["Egress"],
            "egress": [
                {
                    "to": [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "kube-system"}}, "podSelector": {"matchLabels": {"k8s-app": "kube-dns"}}}],
                    "ports": [{"port": 53, "protocol": "UDP"}, {"port": 53, "protocol": "TCP"}],
                },
                {"to": [{"podSelector": {"matchLabels": {"app": "board"}}}], "ports": [{"port": 8080, "protocol": "TCP"}]},
            ],
        },
    }


def run_policy_probe(policy_list, target="board", labels=None):
    source = (ROOT / "quests/119/check-0.sh").read_text()
    program = source.split("<<'DQ_POLICY'\n", 1)[1].split("\nDQ_POLICY\n", 1)[0]
    return subprocess.run(
        [sys.executable, "-", json.dumps({"items": policy_list}), json.dumps({"items": [{"metadata": {"labels": labels or {"app": "client"}}}]}), target],
        input=program,
        capture_output=True,
        text=True,
    )


def test_reordered_and_split_rules_with_default_tcp_are_accepted(policy):
    dns, board = policy["spec"]["egress"]
    udp, tcp = dns["ports"]
    split = deepcopy(policy)
    split["spec"]["egress"] = [board, {"to": dns["to"], "ports": [{"port": 53}]}, {"to": dns["to"], "ports": [udp]}]
    assert tcp["protocol"] == "TCP"
    assert run_policy_probe([split]).returncode == 0


@pytest.mark.parametrize("kind", ["all_destinations", "extra_port", "separate_selectors", "extra_policy"])
def test_broader_egress_is_rejected(policy, kind):
    changed = deepcopy(policy)
    policies = [changed]
    if kind == "all_destinations":
        changed["spec"]["egress"][0]["to"] = []
    elif kind == "extra_port":
        changed["spec"]["egress"][1]["ports"].append({"port": 80, "protocol": "TCP"})
    elif kind == "separate_selectors":
        peer = changed["spec"]["egress"][0]["to"][0]
        changed["spec"]["egress"][0]["to"] = [{"namespaceSelector": peer["namespaceSelector"]}, {"podSelector": peer["podSelector"]}]
    else:
        policies.append({"metadata": {"name": "extra"}, "spec": {"podSelector": {}, "policyTypes": ["Egress"], "egress": [{}]}})
    result = run_policy_probe(policies)
    assert result.returncode != 0
    assert result.stdout.strip()


def test_policy_selecting_live_pod_label_cannot_broaden_egress(policy):
    extra = {"metadata": {"name": "extra"}, "spec": {"podSelector": {"matchLabels": {"added": "yes"}}, "policyTypes": ["Egress"], "egress": [{}]}}
    result = run_policy_probe([policy, extra], labels={"app": "client", "added": "yes"})
    assert result.returncode != 0
    assert "networkpolicy/extra" in result.stdout


def test_singleton_in_selectors_are_equivalent(policy):
    changed = deepcopy(policy)
    changed["spec"]["podSelector"] = {"matchExpressions": [{"key": "app", "operator": "In", "values": ["client"]}]}
    peer = changed["spec"]["egress"][0]["to"][0]
    peer["podSelector"] = {"matchExpressions": [{"key": "k8s-app", "operator": "In", "values": ["kube-dns"]}]}
    changed["spec"]["egress"][1]["to"][0]["podSelector"] = {"matchExpressions": [{"key": "app", "operator": "In", "values": ["board"]}]}
    assert run_policy_probe([changed]).returncode == 0
