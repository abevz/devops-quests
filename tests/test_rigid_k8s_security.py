"""Effective security stays restrictive across equivalent policy placements."""

import copy
import json
import os
import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import ROOT


def check_source(number, goal):
    return yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())[
        "stages"
    ][0]["objectives"][goal]["check"]


def program_probe(number, document, marker="DQ_SECURITY"):
    goal = 1 if number == 103 else 2
    if marker == "DQ_ELIGIBLE":
        goal = 0
    source = check_source(number, goal)
    code = source.split("<<'" + marker + "'\n", 1)[1].split("\n" + marker, 1)[0]
    return subprocess.run(
        [sys.executable, "-", json.dumps(document)],
        input=code,
        text=True,
        capture_output=True,
        timeout=5,
    )


def secure_document():
    context = {
        "allowPrivilegeEscalation": False,
        "readOnlyRootFilesystem": True,
        "capabilities": {"drop": ["ALL"]},
    }
    return {
        "metadata": {"generation": 2},
        "spec": {
            "template": {
                "spec": {
                    "securityContext": {
                        "runAsNonRoot": True,
                        "runAsUser": 1000,
                        "seccompProfile": {"type": "RuntimeDefault"},
                    },
                    "containers": [
                        {
                            "name": "worker",
                            "securityContext": context,
                            "volumeMounts": [{"name": "scratch", "mountPath": "/tmp"}],
                        }
                    ],
                    "volumes": [{"name": "scratch", "emptyDir": {}}],
                }
            }
        },
        "status": {
            "observedGeneration": 2,
            "desiredNumberScheduled": 1,
            "updatedNumberScheduled": 1,
            "numberMisscheduled": 0,
        },
    }


@pytest.mark.parametrize("number", [103, 109])
def test_pod_and_per_container_security_are_equivalent(number):
    document = secure_document()
    assert program_probe(number, document).returncode == 0
    pod = document["spec"]["template"]["spec"]
    policy = pod["securityContext"]
    worker = pod["containers"][0]
    worker["securityContext"].update(
        runAsNonRoot=policy.pop("runAsNonRoot"),
        seccompProfile=policy.pop("seccompProfile"),
        runAsUser=1001,
    )
    assert program_probe(number, document).returncode == 0
    initial = {
        "name": "prepare",
        "securityContext": copy.deepcopy(worker["securityContext"]),
    }
    pod["initContainers"] = [initial]
    assert program_probe(number, document).returncode == 0


@pytest.mark.parametrize("number", [103, 109])
@pytest.mark.parametrize(
    "change",
    [
        "root",
        "root_override",
        "unconfined",
        "init_root",
        "privileged",
        "escalation",
        "retained_caps",
        "added_caps",
        "host_network",
        "host_path",
    ],
)
def test_equivalent_security_does_not_allow_a_privileged_override(number, change):
    document = secure_document()
    pod = document["spec"]["template"]["spec"]
    context = pod["containers"][0]["securityContext"]
    if change == "root":
        context["runAsUser"] = 0
    elif change == "root_override":
        context["runAsNonRoot"] = False
    elif change == "unconfined":
        context["seccompProfile"] = {"type": "Unconfined"}
    elif change == "init_root":
        pod["initContainers"] = [
            {"name": "prepare", "securityContext": {**context, "runAsUser": 0}}
        ]
    elif change == "privileged":
        context["privileged"] = True
    elif change == "escalation":
        context["allowPrivilegeEscalation"] = True
    elif change == "retained_caps":
        context["capabilities"]["drop"] = ["NET_RAW"]
    elif change == "added_caps":
        context["capabilities"]["add"] = ["NET_ADMIN"]
    elif change == "host_network":
        pod["hostNetwork"] = True
    else:
        pod["volumes"].append({"name": "host", "hostPath": {"path": "/"}})
    assert program_probe(number, document).returncode != 0


def test_tmp_volume_alias_does_not_permit_another_writable_mount():
    document = secure_document()
    pod = document["spec"]["template"]["spec"]
    pod["volumes"][0]["name"] = "temporary"
    pod["containers"][0]["volumeMounts"][0]["name"] = "temporary"
    assert program_probe(109, document).returncode == 0
    pod["volumes"].append({"name": "other", "emptyDir": {}})
    pod["containers"][0]["volumeMounts"].append(
        {"name": "other", "mountPath": "/other"}
    )
    assert program_probe(109, document).returncode != 0
    pod["containers"][0]["volumeMounts"][-1]["readOnly"] = True
    assert program_probe(109, document).returncode == 0


def test_readonly_root_and_writable_tmp_both_remain_required():
    document = secure_document()
    pod = document["spec"]["template"]["spec"]
    pod["containers"][0]["securityContext"]["readOnlyRootFilesystem"] = False
    assert program_probe(109, document).returncode != 0
    pod["containers"][0]["securityContext"]["readOnlyRootFilesystem"] = True
    pod["containers"][0]["volumeMounts"][0]["readOnly"] = True
    assert program_probe(109, document).returncode != 0


def test_eligibility_uses_current_controller_evidence_not_one_selector_spelling():
    document = secure_document()
    document["spec"]["template"]["spec"]["nodeSelector"] = {"kubernetes.io/os": "linux"}
    assert program_probe(103, document, "DQ_ELIGIBLE").returncode == 0
    document["spec"]["template"]["spec"].pop("nodeSelector")
    document["metadata"]["generation"] = 3
    document["status"]["observedGeneration"] = 3
    assert program_probe(103, document, "DQ_ELIGIBLE").returncode == 0
    document["status"]["observedGeneration"] = 2
    assert program_probe(103, document, "DQ_ELIGIBLE").returncode != 0
    document["status"]["observedGeneration"] = 3
    document["status"]["desiredNumberScheduled"] = 0
    assert program_probe(103, document, "DQ_ELIGIBLE").returncode != 0
    document["status"]["desiredNumberScheduled"] = 1
    document["status"]["updatedNumberScheduled"] = 0
    assert program_probe(103, document, "DQ_ELIGIBLE").returncode != 0


@pytest.mark.parametrize("live_uid,accepted", [(1001, True), (65534, True), (0, False)])
def test_security_goal_observes_a_nonroot_live_uid(tmp_path, live_uid, accepted):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    binaries = tmp_path / "bin"
    binaries.mkdir()
    data = secure_document()
    data["spec"]["template"]["spec"]["containers"][0]["securityContext"][
        "runAsUser"
    ] = 1001
    binary = binaries / "kubectl"
    binary.write_text(
        "#!/bin/bash\n"
        + "if [ \"$1\" = get ]; then printf '%s\\n' '"
        + json.dumps(data)
        + "'; elif [[ \"$*\" == *' id -u' ]]; then printf '%s\\n' '"
        + str(live_uid)
        + "'; else exit 0; fi\n"
    )
    binary.chmod(0o755)
    result = subprocess.run(
        ["bash", "-c", check_source(109, 2)],
        env={
            **os.environ,
            "HOME": str(home),
            "PATH": str(binaries) + os.pathsep + os.environ["PATH"],
        },
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert (result.returncode == 0) is accepted, result.stdout + result.stderr
    if not accepted:
        assert "[DQ:live_uid]" in result.stdout
