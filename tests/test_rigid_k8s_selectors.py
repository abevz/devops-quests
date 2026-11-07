"""Equivalent workload selectors and projections remain bound to the real consumer."""

import json
import re
import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import ROOT


def source(number, goal=0, stage=0):
    return yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())[
        "stages"
    ][stage]["objectives"][goal]["check"]


def selector(selector, pods, key="app", value="board"):
    code = source(118, 1).split("<<'DQ_SELECTOR'\n", 1)[1].split("\nDQ_SELECTOR", 1)[0]
    return subprocess.run(
        [
            sys.executable,
            "-",
            json.dumps({"spec": {"selector": selector}}),
            json.dumps(
                {"items": [{"metadata": {"labels": labels}} for labels in pods]}
            ),
            key,
            value,
        ],
        input=code,
        text=True,
        capture_output=True,
        timeout=5,
    )


@pytest.mark.parametrize(
    "extra,accepted",
    [({}, True), ({"pool": "station"}, True), ({"pool": "wrong"}, False)],
)
def test_equivalent_service_selector_preserves_the_whole_workload(extra, accepted):
    pods = [{"app": "board", "pool": "station"}, {"app": "client", "pool": "station"}]
    assert (selector({"app": "board", **extra}, pods).returncode == 0) is accepted


def test_selector_cannot_drop_a_replica_or_add_an_unrelated_workload():
    pods = [
        {"app": "board", "version": "blue"},
        {"app": "board", "version": "green"},
        {"app": "client", "version": "green"},
    ]
    assert selector({"app": "board", "version": "blue"}, pods).returncode != 0
    assert selector({"version": "green"}, pods).returncode != 0
    assert selector({"app": "board"}, []).returncode != 0


def expression(number, goal, needle):
    return next(
        text
        for line in source(number, goal).splitlines()
        if needle in line
        for text in re.findall(r"'([^']+)'", line)
        if needle in text
    )


def jq(number, goal, needle, document):
    return subprocess.run(
        ["jq", "-e", expression(number, goal, needle)],
        input=json.dumps(document),
        text=True,
        capture_output=True,
    )


@pytest.mark.parametrize(
    "fault,accepted",
    [
        ("selector", True),
        (" SELECTOR ", True),
        ("\tSELECTOR\n", True),
        ("service-selector mismatch", True),
        ("dns", False),
        ("proxy", False),
        ("selector or dns", False),
        (None, False),
    ],
)
def test_diagnosis_is_a_single_unambiguous_category(fault, accepted):
    assert (jq(118, 0, "ascii_downcase", {"fault": fault}).returncode == 0) is accepted


def projection():
    return {
        "spec": {
            "template": {
                "spec": {
                    "containers": [
                        {
                            "name": "worker",
                            "volumeMounts": [
                                {
                                    "name": "credential",
                                    "mountPath": "/credential",
                                    "readOnly": True,
                                }
                            ],
                        }
                    ],
                    "volumes": [
                        {
                            "name": "credential",
                            "projected": {
                                "sources": [
                                    {
                                        "serviceAccountToken": {
                                            "path": "token",
                                            "expirationSeconds": 600,
                                            "audience": "https://kubernetes.default.svc.cluster.local",
                                        }
                                    }
                                ]
                            },
                        }
                    ],
                }
            }
        }
    }


def token_check(document):
    return jq(114, 0, "as $pod", document)


def test_projection_is_found_through_the_worker_mount_and_source_identity():
    document = projection()
    assert token_check(document).returncode == 0
    pod = document["spec"]["template"]["spec"]
    pod["containers"].insert(0, {"name": "observer"})
    pod["volumes"].insert(0, {"name": "other", "emptyDir": {}})
    pod["volumes"][1]["projected"]["sources"].insert(0, {"downwardAPI": {"items": []}})
    assert token_check(document).returncode == 0
    pod["containers"][1]["volumeMounts"][0]["name"] = "other"
    assert token_check(document).returncode != 0


@pytest.mark.parametrize(
    "field,value",
    [("path", "other"), ("expirationSeconds", 3600), ("audience", "other")],
)
def test_wrong_projected_token_is_rejected(field, value):
    document = projection()
    document["spec"]["template"]["spec"]["volumes"][0]["projected"]["sources"][0][
        "serviceAccountToken"
    ][field] = value
    assert token_check(document).returncode != 0


def test_stateful_data_mount_accepts_explicit_defaults_but_not_different_access():
    mount = {"name": "ledger", "mountPath": "/data"}
    document = {
        "spec": {
            "template": {
                "spec": {"containers": [{"name": "worker", "volumeMounts": [mount]}]}
            }
        }
    }

    def run():
        return jq(111, 0, "as $worker", document)

    assert run().returncode == 0
    mount.update(readOnly=False, mountPropagation="None", subPath="")
    document["spec"]["template"]["spec"]["containers"].insert(0, {"name": "observer"})
    assert run().returncode == 0
    mount["readOnly"] = True
    assert run().returncode != 0
    mount["readOnly"] = False
    mount["subPath"] = "other"
    assert run().returncode != 0


@pytest.mark.parametrize(
    "pod_flag,account_flag,accepted",
    [
        (False, True, True),
        (None, False, True),
        (True, False, False),
        (None, True, False),
        (None, None, False),
    ],
)
def test_automatic_mounting_uses_pod_override_then_serviceaccount_policy(
    pod_flag, account_flag, accepted
):
    code = (
        source(114, 0).split("<<'DQ_AUTOMOUNT'\n", 1)[1].split("\nDQ_AUTOMOUNT", 1)[0]
    )
    document = {
        "spec": {"template": {"spec": {"automountServiceAccountToken": pod_flag}}}
    }
    result = subprocess.run(
        [
            sys.executable,
            "-",
            json.dumps(document),
            json.dumps({"automountServiceAccountToken": account_flag}),
        ],
        input=code,
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert (result.returncode == 0) is accepted
