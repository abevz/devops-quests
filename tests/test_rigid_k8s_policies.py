"""Equivalent policy grammar must never expand traffic or admission scope."""

import base64
import json
import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import ROOT


def program(number, marker):
    check = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())[
        "stages"
    ][0]["objectives"][0]["check"]
    return check.split("<<'" + marker + "'\n", 1)[1].split("\n" + marker, 1)[0]


def run(number, marker, *args, cwd=None):
    return subprocess.run(
        [sys.executable, "-", *args],
        input=program(number, marker),
        text=True,
        capture_output=True,
        cwd=cwd,
        timeout=5,
    )


def board_pods():
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


def policy():
    return {
        "spec": {
            "podSelector": {"matchLabels": {"app": "board"}},
            "policyTypes": ["Ingress"],
            "ingress": [
                {
                    "from": [{"podSelector": {"matchLabels": {"role": "dispatcher"}}}],
                    "ports": [{"port": 8080, "protocol": "TCP"}],
                }
            ],
        }
    }


def ingress(document):
    return run(62, "DQ_INGRESS_POLICY", json.dumps(document), json.dumps(board_pods()))


def test_ingress_accepts_conjunctive_selectors_and_named_http_without_broadening():
    doc = policy()
    assert ingress(doc).returncode == 0
    doc["spec"]["podSelector"] = {
        "matchExpressions": [
            {"key": "app", "operator": "In", "values": ["board", "client"]},
            {"key": "app", "operator": "NotIn", "values": ["client"]},
            {"key": "app", "operator": "Exists"},
        ]
    }
    doc["spec"]["ingress"][0]["ports"] = [{"port": "http"}]
    doc["spec"]["ingress"] *= 2
    assert ingress(doc).returncode == 0
    doc["spec"]["podSelector"]["matchExpressions"][1]["values"] = []
    assert ingress(doc).returncode != 0


@pytest.mark.parametrize(
    "wrong", ["peer", "namespace", "port", "range", "protocol", "direction"]
)
def test_ingress_rejects_every_expanded_flow(wrong):
    doc = policy()
    rule = doc["spec"]["ingress"][0]
    if wrong == "peer":
        rule["from"][0]["podSelector"] = {}
    if wrong == "namespace":
        rule["from"][0]["namespaceSelector"] = {}
    if wrong == "port":
        rule["ports"][0]["port"] = 9090
    if wrong == "range":
        rule["ports"][0]["endPort"] = 8081
    if wrong == "protocol":
        rule["ports"][0]["protocol"] = "UDP"
    if wrong == "direction":
        doc["spec"]["policyTypes"].append("Egress")
    assert ingress(doc).returncode != 0


def webhook(selector):
    return {"webhooks": [{"namespaceSelector": selector}]}


def scope(selector):
    return run(
        121, "DQ_NAMESPACE_SCOPE", json.dumps(webhook(selector)), "install", "bay"
    )


def test_admission_scope_accepts_equivalent_conjunction_only():
    labels = {"devops-quests.installation": "install", "devops-quests.run": "bay"}
    assert scope({"matchLabels": labels}).returncode == 0
    selector = {
        "matchExpressions": [
            {"key": key, "operator": "In", "values": [value]}
            for key, value in labels.items()
        ]
    }
    selector["matchExpressions"].append(
        {"key": "devops-quests.run", "operator": "Exists"}
    )
    assert scope(selector).returncode == 0
    selector["matchExpressions"][0]["values"].append("foreign")
    assert scope(selector).returncode != 0
    assert scope({"matchLabels": {"devops-quests.run": "bay"}}).returncode != 0


def test_ca_accepts_pem_formatting_but_not_different_or_extra_trust(tmp_path):
    # The predicate compares a supplied certificate's DER identity; no test CA is trusted externally.
    cert = b"\x30\x03\x02\x01\x01"
    encoded = base64.b64encode(cert)
    expected = (
        b"-----BEGIN CERTIFICATE-----\n" + encoded + b"\n-----END CERTIFICATE-----\n"
    )
    (tmp_path / "admission-ca.pem").write_bytes(expected)

    def ca(content):
        doc = {
            "webhooks": [
                {"clientConfig": {"caBundle": base64.b64encode(content).decode()}}
            ]
        }
        return run(121, "DQ_CA", json.dumps(doc), cwd=tmp_path)

    assert ca(expected).returncode == 0
    assert (
        ca(
            b"\n-----BEGIN CERTIFICATE-----\r\n"
            + encoded[:4]
            + b"\r\n"
            + encoded[4:]
            + b"\r\n-----END CERTIFICATE-----\r\n"
        ).returncode
        == 0
    )
    assert ca(expected.replace(encoded, b"Zm9yZWlnbg==")).returncode != 0
    assert ca(expected + expected).returncode != 0


def egress_policy():
    return {
        "items": [
            {
                "metadata": {"name": "client-egress"},
                "spec": {
                    "podSelector": {"matchLabels": {"app": "client"}},
                    "policyTypes": ["Egress"],
                    "egress": [
                        {
                            "to": [
                                {
                                    "namespaceSelector": {
                                        "matchLabels": {
                                            "kubernetes.io/metadata.name": "kube-system"
                                        }
                                    },
                                    "podSelector": {
                                        "matchLabels": {"k8s-app": "kube-dns"}
                                    },
                                }
                            ],
                            "ports": [
                                {"protocol": "UDP", "port": 53},
                                {"protocol": "TCP", "port": 53},
                            ],
                        },
                        {
                            "to": [{"podSelector": {"matchLabels": {"app": "board"}}}],
                            "ports": [{"port": 8080}],
                        },
                    ],
                },
            }
        ]
    }


def egress(document):
    client = {"items": [{"metadata": {"labels": {"app": "client"}}}]}
    return run(
        119,
        "DQ_POLICY",
        json.dumps(document),
        json.dumps(client),
        "board",
        json.dumps(board_pods()),
    )


def test_egress_accepts_named_ports_and_redundant_scope_but_not_unrelated_port():
    doc = egress_policy()
    assert egress(doc).returncode == 0
    spec = doc["items"][0]["spec"]
    spec["podSelector"]["matchExpressions"] = [{"key": "app", "operator": "Exists"}]
    spec["egress"][0]["ports"] = [
        {"protocol": "UDP", "port": "dns"},
        {"protocol": "TCP", "port": "dns-tcp"},
    ]
    spec["egress"][1]["ports"] = [{"port": "http"}]
    assert egress(doc).returncode == 0
    spec["egress"][1]["ports"][0]["port"] = "other"
    assert egress(doc).returncode != 0


@pytest.mark.parametrize(
    "wrong", ["namespace", "range", "additional-policy", "broad-peer", "udp-http"]
)
def test_egress_rejects_all_observed_broadening(wrong):
    doc = egress_policy()
    spec = doc["items"][0]["spec"]
    if wrong == "namespace":
        spec["egress"][0]["to"][0]["namespaceSelector"] = {}
    if wrong == "range":
        spec["egress"][1]["ports"][0]["endPort"] = 8081
    if wrong == "additional-policy":
        doc["items"].append(
            {
                "metadata": {"name": "open"},
                "spec": {"podSelector": {}, "policyTypes": ["Egress"], "egress": [{}]},
            }
        )
    if wrong == "broad-peer":
        spec["egress"][1]["to"][0]["podSelector"] = {}
    if wrong == "udp-http":
        spec["egress"][1]["ports"][0]["protocol"] = "UDP"
    assert egress(doc).returncode != 0
