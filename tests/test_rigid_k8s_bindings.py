"""The shipped identity/permission predicates reject decoys and broader access."""

import copy
import json
import re
import subprocess

import pytest
import yaml

from devops_quests.catalog import ROOT


PREFIXES = {
    "rules": "def exact(",
    "subjects": ".subjects |",
    "secret": ".spec.template.spec.containers as",
    "mount": ".spec.template.spec as $pod",
}


def probe(number, goal, kind, document):
    quest = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())
    source = quest["stages"][0]["objectives"][goal]["check"]
    matches = [
        s for s in re.findall(r"'([^']+)'", source) if s.startswith(PREFIXES[kind])
    ]
    assert len(matches) == 1
    return subprocess.run(
        ["jq", "-e", "--arg", "ns", "dq-test", matches[0]],
        input=json.dumps(document),
        capture_output=True,
        text=True,
        timeout=5,
    )


def narrow_role():
    return {
        "rules": [
            {
                "apiGroups": [""],
                "resources": ["configmaps"],
                "resourceNames": ["route"],
                "verbs": ["get"],
            }
        ]
    }


@pytest.mark.parametrize("number,goal", [(37, 0), (114, 1), (125, 0)])
def test_named_read_rules_accept_reference_and_duplicate_equivalents(number, goal):
    role = narrow_role()
    assert probe(number, goal, "rules", role).returncode == 0
    role["rules"][0]["verbs"].append("get")
    role["rules"][0]["nonResourceURLs"] = []
    role["rules"].append(copy.deepcopy(role["rules"][0]))
    assert probe(number, goal, "rules", role).returncode == 0


@pytest.mark.parametrize("number,goal", [(37, 0), (114, 1), (125, 0)])
@pytest.mark.parametrize(
    "change",
    [
        "list",
        "other_name",
        "all_names",
        "other_resource",
        "other_group",
        "url",
        "extra_rule",
    ],
)
def test_narrow_role_cannot_grant_broader_or_unrelated_access(number, goal, change):
    role = narrow_role()
    rule = role["rules"][0]
    if change == "list":
        rule["verbs"].append("list")
    elif change == "other_name":
        rule["resourceNames"].append("protected")
    elif change == "all_names":
        rule.pop("resourceNames")
    elif change == "other_resource":
        rule["resources"].append("secrets")
    elif change == "other_group":
        rule["apiGroups"].append("apps")
    elif change == "url":
        rule["nonResourceURLs"] = ["/healthz"]
    else:
        role["rules"].append(
            {"apiGroups": [""], "resources": ["pods"], "verbs": ["get"]}
        )
    assert probe(number, goal, "rules", role).returncode != 0


def test_binding_normalizes_only_the_same_controller_principal():
    subject = {"kind": "ServiceAccount", "name": "controller", "namespace": "dq-test"}
    assert probe(125, 0, "subjects", {"subjects": [subject]}).returncode == 0
    duplicate = {**subject, "apiGroup": ""}
    user = {
        "kind": "User",
        "apiGroup": "rbac.authorization.k8s.io",
        "name": "system:serviceaccount:dq-test:controller",
    }
    assert (
        probe(125, 0, "subjects", {"subjects": [duplicate, subject, user]}).returncode
        == 0
    )
    assert (
        probe(
            125,
            0,
            "subjects",
            {"subjects": [{"kind": "ServiceAccount", "name": "controller"}]},
        ).returncode
        == 0
    )


@pytest.mark.parametrize(
    "subject",
    [
        {"kind": "ServiceAccount", "name": "observer", "namespace": "dq-test"},
        {"kind": "ServiceAccount", "name": "controller", "namespace": "other"},
        {"kind": "User", "name": "controller", "apiGroup": "rbac.authorization.k8s.io"},
        {
            "kind": "Group",
            "name": "system:serviceaccounts:dq-test",
            "apiGroup": "rbac.authorization.k8s.io",
        },
    ],
)
def test_binding_rejects_an_extra_or_wrong_principal(subject):
    reference = {"kind": "ServiceAccount", "name": "controller", "namespace": "dq-test"}
    assert probe(125, 0, "subjects", {"subjects": [subject]}).returncode != 0
    assert probe(125, 0, "subjects", {"subjects": [reference, subject]}).returncode != 0


def reader():
    return {
        "spec": {
            "template": {
                "spec": {
                    "volumes": [
                        {
                            "name": "data",
                            "persistentVolumeClaim": {"claimName": "route-data"},
                        }
                    ],
                    "containers": [
                        {
                            "name": "worker",
                            "volumeMounts": [
                                {"name": "data", "mountPath": "/data", "readOnly": True}
                            ],
                        }
                    ],
                }
            }
        }
    }


def test_readonly_claim_accepts_aliases_defaults_and_effective_readonly_placement():
    document = reader()
    assert probe(45, 1, "mount", document).returncode == 0
    pod = document["spec"]["template"]["spec"]
    pod["volumes"][0]["name"] = "ledger"
    pod["volumes"][0]["persistentVolumeClaim"]["readOnly"] = False
    mount = pod["containers"][0]["volumeMounts"][0]
    mount.update(name="ledger", subPath="", mountPropagation="None")
    pod["containers"].insert(0, {"name": "observer"})
    assert probe(45, 1, "mount", document).returncode == 0
    pod["volumes"][0]["persistentVolumeClaim"]["readOnly"] = True
    mount["readOnly"] = False
    assert probe(45, 1, "mount", document).returncode == 0


@pytest.mark.parametrize(
    "change",
    [
        "write",
        "wrong_claim",
        "wrong_path",
        "extra_volume",
        "extra_mount",
        "sidecar_write",
        "subpath",
        "propagation",
    ],
)
def test_claim_preserves_only_and_readonly_constraints(change):
    document = reader()
    pod = document["spec"]["template"]["spec"]
    mount = pod["containers"][0]["volumeMounts"][0]
    if change == "write":
        mount["readOnly"] = False
    elif change == "wrong_claim":
        pod["volumes"][0]["persistentVolumeClaim"]["claimName"] = "other"
    elif change == "wrong_path":
        mount["mountPath"] = "/other"
    elif change == "extra_volume":
        pod["volumes"].append({"name": "extra", "emptyDir": {}})
    elif change == "extra_mount":
        pod["containers"][0]["volumeMounts"].append({**mount, "mountPath": "/extra"})
    elif change == "sidecar_write":
        pod["containers"].append(
            {"name": "observer", "volumeMounts": [{**mount, "readOnly": False}]}
        )
    elif change == "subpath":
        mount["subPath"] = "another-tree"
    else:
        mount["mountPropagation"] = "Bidirectional"
    assert probe(45, 1, "mount", document).returncode != 0


def route_document():
    return {
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
                                        "secretKeyRef": {
                                            "name": "station",
                                            "key": "route",
                                        }
                                    },
                                },
                            ],
                        }
                    ]
                }
            }
        }
    }


def test_route_uses_named_worker_and_named_environment_reference():
    document = route_document()
    assert probe(31, 2, "secret", document).returncode == 0
    containers = document["spec"]["template"]["spec"]["containers"]
    containers[0]["env"].insert(0, {"name": "EXTRA", "value": "unrelated"})
    containers[0]["env"][1]["valueFrom"]["secretKeyRef"]["optional"] = False
    containers.insert(0, {"name": "observer", "env": []})
    assert probe(31, 2, "secret", document).returncode == 0


@pytest.mark.parametrize(
    "change",
    [
        "literal",
        "wrong_name",
        "wrong_key",
        "decoy_env",
        "decoy_container",
        "earlier_literal",
    ],
)
def test_route_rejects_embedded_or_wrong_effective_references(change):
    document = route_document()
    containers = document["spec"]["template"]["spec"]["containers"]
    route = containers[0]["env"][0]
    if change == "literal":
        route.pop("valueFrom")
        route["value"] = "north"
    elif change == "wrong_name":
        route["valueFrom"]["secretKeyRef"]["name"] = "other"
    elif change == "wrong_key":
        route["valueFrom"]["secretKeyRef"]["key"] = "other"
    elif change == "decoy_env":
        route["name"] = "DECOY"
        containers[0]["env"].append({"name": "ROUTE", "value": "north"})
    elif change == "decoy_container":
        containers[0]["name"] = "observer"
        containers.append(
            {"name": "worker", "env": [{"name": "ROUTE", "value": "north"}]}
        )
    else:
        containers[0]["env"].insert(0, {"name": "ROUTE", "value": "north"})
    assert probe(31, 2, "secret", document).returncode != 0
