"""Final migration primitives retain the frozen pre-extraction behavior."""

import ast
import base64
import copy
import json
from pathlib import Path
import re
import subprocess

import pytest

import dq_check as helper
from test_check_helper import original as b1_original, outcome


REFERENCES = json.loads(
    (
        Path(__file__).parent / "fixtures/check-helper-remaining-reference.json"
    ).read_text()
)["programs"]


def original(quest, tag, required=None):
    key = f"{quest:03}:{tag}"
    if key not in REFERENCES:
        return b1_original(quest, tag, required)
    for candidate in REFERENCES[key]:
        tree = ast.parse(candidate["python"])
        definitions = [
            n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.ClassDef))
        ]
        if required is None or any(n.name == required for n in definitions):
            namespace = dict(json=json, re=re, subprocess=subprocess, base64=base64)
            exec(
                compile(ast.Module(body=definitions, type_ignores=[]), key, "exec"),
                namespace,
            )
            return namespace
    raise AssertionError(f"No frozen definition {required} in {key}")


def encoded(value):
    return base64.b64encode(json.dumps(value).encode()).decode()


@pytest.mark.parametrize(
    "kind",
    ["kubernetes.io/dockerconfigjson", "kubernetes.io/dockercfg", "Opaque", None],
)
@pytest.mark.parametrize(
    "entry",
    [
        {"auth": base64.b64encode(b"reader:token").decode()},
        {"username": "reader", "password": "token"},
        {"auth": "", "username": "reader", "password": "token"},
        {"auth": "broken"},
        {"auth": None},
        {},
        None,
    ],
)
def test_registry_formats_match_frozen(kind, entry, monkeypatch):
    source = original(27, "DQ_PRIVATE_PULL", "credentials")
    monkeypatch.setitem(source, "base64", base64)
    value = {"registry:5000": entry}
    key = (
        ".dockerconfigjson"
        if kind == "kubernetes.io/dockerconfigjson"
        else ".dockercfg"
    )
    payload = {"auths": value} if key == ".dockerconfigjson" else value
    secret = {"type": kind, "data": {key: encoded(payload)}}
    assert outcome(
        helper.registry_credentials, secret, "registry:5000", "reader", "token"
    ) == outcome(source["credentials"], secret, "registry:5000", "reader", "token")


@pytest.mark.parametrize("payload", [b'{"auths":{},"auths":{}}', b"{", b"null", b"[]"])
def test_registry_malformed_payload_matches_frozen(payload, monkeypatch):
    source = original(27, "DQ_PRIVATE_PULL", "credentials")
    monkeypatch.setitem(source, "base64", base64)
    secret = {
        "type": "kubernetes.io/dockerconfigjson",
        "data": {".dockerconfigjson": base64.b64encode(payload).decode()},
    }
    assert outcome(helper.registry_credentials, secret, "r", "u", "p") == outcome(
        source["credentials"], secret, "r", "u", "p"
    )


@pytest.mark.parametrize(
    "names",
    [
        None,
        [],
        [{"name": "pull"}],
        [{"name": "pull"}, {"name": "pull"}],
        [{"name": "Bad"}],
        [{}],
        [None],
        "pull",
    ],
)
def test_pull_names_match_frozen(names):
    pod = {"spec": {"imagePullSecrets": names}}
    assert outcome(helper.pull_secret_names, pod) == outcome(
        original(27, "DQ_PRIVATE_PULL")["pull_names"], pod
    )


@pytest.mark.parametrize("port", [8080, 0, -1, 65536, True, "http", "missing", None])
@pytest.mark.parametrize("action", ["httpGet", "tcpSocket", "exec", "grpc"])
@pytest.mark.parametrize("tcp", [False, True])
def test_readiness_port_policy_matches_frozen(port, action, tcp):
    container = {
        "name": "worker",
        "ports": [{"name": "http", "containerPort": 8080}],
        "readinessProbe": {action: {"port": port}},
    }
    document = {"spec": {"template": {"spec": {"containers": [container]}}}}
    assert outcome(helper.readiness_probe, document, tcp) == outcome(
        original(67, "DQ_READINESS")["readiness"], document, tcp
    )


@pytest.mark.parametrize(
    "containers",
    [
        [],
        [{"ports": [{"name": "http", "containerPort": 8080}]}],
        [
            {
                "ports": [
                    {"name": "http", "containerPort": 8080},
                    {"name": "http", "containerPort": 8081},
                ]
            }
        ],
    ],
)
@pytest.mark.parametrize("value", [8080, True, "http", "", None])
def test_workload_port_policy_matches_frozen(containers, value):
    assert outcome(helper.port_number, containers, value) == outcome(
        original(40, "DQ_BOSS", "port_number")["port_number"], containers, value
    )


@pytest.mark.parametrize(
    "selector",
    [
        {},
        {"matchLabels": {"app": "board"}},
        {"matchExpressions": [{"key": "app", "operator": "In", "values": ["board"]}]},
        {
            "matchExpressions": [{"key": "app", "operator": "DoesNotExist"}],
            "matchLabels": {"app": "board"},
        },
        {"matchExpressions": [{"key": "app", "operator": "Bad"}]},
        None,
    ],
)
def test_implication_matches_frozen(selector):
    required = {"app": "board"}
    assert outcome(helper.selector_implies, selector, required) == outcome(
        original(120, "DQ_BOSS", "implies")["implies"], selector, required
    )


@pytest.mark.parametrize(
    "policy",
    [
        {},
        {
            "runAsUser": 1000,
            "runAsNonRoot": True,
            "seccompProfile": {"type": "RuntimeDefault"},
        },
        {"runAsUser": True},
        {"runAsUser": 0},
        {"runAsNonRoot": False},
        {"seccompProfile": "invalid"},
    ],
)
@pytest.mark.parametrize(
    "contexts",
    [
        [],
        [{}],
        [{"runAsUser": 1001}],
        [{"runAsNonRoot": False}],
        [{"seccompProfile": {"type": "Unconfined"}}],
    ],
)
def test_inherited_security_policies_match_frozen(policy, contexts, monkeypatch):
    source = original(103, "DQ_SECURITY", "positive_ids")
    monkeypatch.setitem(source, "policy", copy.deepcopy(policy))
    monkeypatch.setitem(source, "contexts", copy.deepcopy(contexts))
    for api, old in [
        (helper.positive_user_ids, "positive_ids"),
        (helper.nonroot_policy, "nonroot"),
        (helper.runtime_default_policy, "default_filter"),
    ]:
        assert outcome(api, policy, contexts) == outcome(source[old])


@pytest.mark.parametrize(
    "context",
    [
        {},
        {"capabilities": None},
        {"capabilities": {"drop": ["ALL"]}},
        {"capabilities": []},
        {"seccompProfile": {"type": "RuntimeDefault"}},
        {"seccompProfile": 1},
    ],
)
def test_security_field_shapes_match_frozen(context):
    source = original(103, "DQ_SECURITY", "caps")
    assert outcome(helper.capability_list, context, "drop") == outcome(
        source["caps"], context, "drop"
    )
    assert outcome(helper.seccomp_profile, context) == outcome(
        source["profile"], context
    )


@pytest.mark.parametrize(
    "source",
    [
        {},
        {"secret": {}},
        {"persistentVolumeClaim": {"readOnly": True}},
        {"emptyDir": {}},
    ],
)
@pytest.mark.parametrize(
    "mount", [{"name": "data"}, {"name": "data", "readOnly": True}, {"name": "missing"}]
)
def test_readonly_volume_rules_match_frozen(source, mount, monkeypatch):
    namespace = original(103, "DQ_SECURITY", "readonly")
    volumes = {"data": source}
    monkeypatch.setitem(namespace, "by_name", volumes)
    assert outcome(helper.readonly_mount, mount, volumes) == outcome(
        namespace["readonly"], mount
    )


def health_workload():
    return {
        "spec": {
            "template": {
                "spec": {
                    "securityContext": {"runAsUser": 1000, "runAsNonRoot": True},
                    "containers": [
                        {
                            "name": "worker",
                            "image": "fixture@sha256:" + "a" * 64,
                            "env": [{"name": "CPU", "value": "100m"}],
                            "readinessProbe": {"httpGet": {"port": 8080}},
                            "securityContext": {
                                "allowPrivilegeEscalation": False,
                                "capabilities": {"drop": ["ALL"]},
                            },
                        }
                    ],
                }
            }
        }
    }


@pytest.mark.parametrize(
    "change",
    [
        "same",
        "image",
        "command",
        "args",
        "env",
        "env-duplicate",
        "env-from",
        "probe",
        "missing-worker",
        "duplicate-worker",
        "privileged",
        "allow-escalation",
        "drop",
        "add-capability",
        "root",
        "bool-user",
        "host-network",
        "extra-container",
        "pod-nonroot",
        "seccomp",
    ],
)
def test_workload_agreement_and_safety_match_frozen(change):
    reference = health_workload()
    current = copy.deepcopy(reference)
    spec = current["spec"]["template"]["spec"]
    worker = spec["containers"][0]
    if change == "image":
        worker["image"] = "different"
    elif change == "command":
        worker["command"] = ["other"]
    elif change == "args":
        worker["args"] = ["other"]
    elif change == "env":
        worker["env"][0]["value"] = "200m"
    elif change == "env-duplicate":
        worker["env"].append({"name": "CPU", "value": "100m"})
    elif change == "env-from":
        worker["env"] = [
            {"name": "CPU", "valueFrom": {"fieldRef": {"fieldPath": "metadata.name"}}}
        ]
    elif change == "probe":
        worker["readinessProbe"]["httpGet"]["port"] = 9000
    elif change == "missing-worker":
        spec["containers"] = []
    elif change == "duplicate-worker":
        spec["containers"].append(copy.deepcopy(worker))
    elif change == "privileged":
        worker["securityContext"]["privileged"] = True
    elif change == "allow-escalation":
        worker["securityContext"]["allowPrivilegeEscalation"] = None
    elif change == "drop":
        worker["securityContext"]["capabilities"]["drop"] = []
    elif change == "add-capability":
        worker["securityContext"]["capabilities"]["add"] = ["NET_ADMIN"]
    elif change == "root":
        worker["securityContext"]["runAsUser"] = 0
    elif change == "bool-user":
        worker["securityContext"]["runAsUser"] = True
    elif change == "host-network":
        spec["hostNetwork"] = True
    elif change == "extra-container":
        spec["containers"].append({"name": "observer"})
    elif change == "pod-nonroot":
        spec["securityContext"]["runAsNonRoot"] = False
    elif change == "seccomp":
        spec["securityContext"]["seccompProfile"] = {"type": "Unconfined"}
    namespace = original(68, "DQ_GIT_HEALTH", "agreement")
    assert outcome(helper.workload_agreement, reference, current) == outcome(
        namespace["agreement"], reference, current
    )
    assert outcome(helper.workload_safety, reference, current) == outcome(
        namespace["safety"], reference, current
    )
