"""034/057 preserve budgets and claims while recovering real startup/data."""

import copy
import hashlib
import json
import os
import secrets
import shlex
import subprocess
import time
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime

IMAGE = "registry/app@sha256:" + "a" * 64
OTHER = "registry/other@sha256:" + "b" * 64


def program(number, index, marker):
    source = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())[
        "stages"
    ][0]["objectives"][index]["check"]
    return source.split("<<'" + marker + "'\n", 1)[1].split("\n" + marker, 1)[0]


def deployment(name, spec):
    return {
        "metadata": {"uid": name + "-deployment"},
        "spec": {
            "replicas": 1,
            "template": {
                "metadata": {"labels": {"app": name}},
                "spec": copy.deepcopy(spec),
            },
        },
        "status": {"readyReplicas": 1},
    }


def owned_pod(name, spec):
    return {
        "metadata": {
            "name": name + "-pod",
            "ownerReferences": [
                {"kind": "ReplicaSet", "uid": name + "-rs", "controller": True}
            ],
        },
        "spec": copy.deepcopy(spec),
        "status": {
            "phase": "Running",
            "conditions": [{"type": "Ready", "status": "True"}],
        },
    }


def replica_set(name):
    return {
        "metadata": {
            "uid": name + "-rs",
            "ownerReferences": [
                {"kind": "Deployment", "uid": name + "-deployment", "controller": True}
            ],
        }
    }


def execute_probe(
    monkeypatch, code, facts_path, facts, docs, variant, budget, exec_output=None
):
    real_read = Path.read_text
    elapsed = [0.0]

    def read(path, *args, **kwargs):
        return (
            json.dumps(facts)
            if str(path) == facts_path
            else real_read(path, *args, **kwargs)
        )

    def cli(args, **kwargs):
        if variant in ("slow-api", "moderate-api"):
            delay = (2 if budget == 15 else 4) if variant == "slow-api" else 1
            allowed = kwargs["timeout"]
            elapsed[0] += min(delay, allowed)
            if delay > allowed:
                raise subprocess.TimeoutExpired(args, allowed)
        if variant == "cli-fails":
            return SimpleNamespace(returncode=1, stdout="", stderr="unavailable")
        if args[1] == "get":
            name = args[3] if args[3] != "-o" else ""
            output = json.dumps(docs[args[2] + "/" + name])
        elif args[1] == "rollout":
            return SimpleNamespace(
                returncode=int(variant == "rollout"), stdout="", stderr=""
            )
        elif args[1] == "exec":
            output = exec_output(args)
        else:
            raise AssertionError(args)
        return SimpleNamespace(returncode=0, stdout=output, stderr="")

    monkeypatch.setattr(Path, "read_text", read)
    monkeypatch.setattr(subprocess, "run", cli)
    with monkeypatch.context() as clock_patch:
        if variant in ("slow-api", "moderate-api"):
            clock_patch.setattr(time, "monotonic", lambda: elapsed[0])
        try:
            exec(compile(code, "shipped-capacity-storage", "exec"), {})
        except SystemExit as result:
            if variant == "slow-api":
                assert elapsed[0] <= budget
            return result.code or 0
    return 0


def cpu_probe(monkeypatch, index, variant):
    code = program(34, index, "DQ_CPU_POLICY" if index == 1 else "DQ_CPU_STARTUP")
    contract = {
        "deployment": "board",
        "initializer": "prepare-route",
        "source": {"configMap": "route-source"},
        "phaseRequestCeiling": "100m",
    }
    spec = {
        "containers": [
            {
                "name": "worker",
                "image": IMAGE,
                "resources": {"requests": {"cpu": "100m"}, "limits": {"cpu": "300m"}},
            }
        ],
        "initContainers": [
            {
                "name": "prepare-route",
                "image": IMAGE,
                "resources": {"requests": {"cpu": "10m"}},
            }
        ],
    }
    current = deployment("board", spec)
    pod = owned_pod("board", spec)
    pod["status"]["initContainerStatuses"] = [
        {"name": "prepare-route", "state": {"terminated": {"exitCode": 0}}}
    ]
    docs = {
        "deployment/board": current,
        "configmap/route-source": {
            "metadata": {"uid": "source"},
            "data": {"index.html": "north\n"},
        },
        "pods/": {"items": [pod]},
        "replicasets/": {"items": [replica_set("board")]},
    }
    facts = {
        "contract": contract,
        "image": IMAGE,
        "identities": {
            "deployment/board": "board-deployment",
            "configmap/route-source": "source",
        },
        "sourceData": {"index.html": "north\n"},
    }
    target = current["spec"]["template"]["spec"] if index == 1 else pod["spec"]
    if variant == "identity":
        docs["configmap/route-source"]["metadata"]["uid"] = "replacement"
    if variant == "source":
        docs["configmap/route-source"]["data"]["index.html"] = "old\n"
    if variant == "extra-source":
        docs["configmap/route-source"]["data"]["unrelated"] = "retained"
    if variant == "missing-init":
        target["initContainers"] = []
    if variant in ("over", "zero", "missing-request", "equivalent", "boolean"):
        init = target["initContainers"][0]["resources"]
        init["requests"]["cpu"] = {
            "over": "1",
            "zero": "0",
            "equivalent": "100e-3",
            "boolean": True,
        }.get(variant)
        if variant == "missing-request":
            init["requests"].pop("cpu")
    if variant == "sidecar":
        target["containers"].append(
            {
                "name": "observer",
                "image": IMAGE,
                "resources": {"requests": {"cpu": "10m"}},
            }
        )
    if variant == "restartable-over":
        target["initContainers"].insert(
            0,
            {
                "name": "observer",
                "image": IMAGE,
                "restartPolicy": "Always",
                "resources": {"requests": {"cpu": "10m"}},
            },
        )
    if variant == "wrong-init-kind":
        target["initContainers"][0]["restartPolicy"] = "Always"
    if variant == "parent":
        target["resources"] = {"requests": {"cpu": "100m"}}
    if variant == "parent-over":
        target["resources"] = {"requests": {"cpu": "200m"}}
    if variant == "overhead":
        target["overhead"] = {"cpu": "1m"}
    if variant == "image":
        target["initContainers"][0]["image"] = OTHER
    if variant == "image-alias":
        for item in target["containers"] + target["initContainers"]:
            item["image"] = "alias/app@sha256:" + "a" * 64
    if variant == "unready":
        pod["status"]["conditions"][0]["status"] = "False"
    if variant == "foreign":
        pod["metadata"]["ownerReferences"][0]["uid"] = "unowned"
    if variant == "terminating":
        pod["metadata"]["deletionTimestamp"] = "now"
    if variant == "incomplete":
        pod["status"]["initContainerStatuses"][0]["state"] = {"running": {}}
    return execute_probe(
        monkeypatch,
        code,
        "/run/dq/facts/0/cpu-identities.json",
        facts,
        docs,
        variant,
        10,
    )


@pytest.mark.parametrize(
    "variant,accepted",
    [
        ("reference", True),
        ("extra-source", True),
        ("zero", True),
        ("missing-request", True),
        ("equivalent", True),
        ("parent", True),
        ("image-alias", True),
        ("moderate-api", True),
        ("identity", False),
        ("source", False),
        ("missing-init", False),
        ("over", False),
        ("boolean", False),
        ("sidecar", False),
        ("restartable-over", False),
        ("wrong-init-kind", False),
        ("parent-over", False),
        ("image", False),
        ("slow-api", False),
        ("cli-fails", False),
    ],
)
def test_cpu_template_policy(monkeypatch, variant, accepted):
    assert (cpu_probe(monkeypatch, 1, variant) == 0) is accepted


@pytest.mark.parametrize(
    "variant,accepted",
    [
        ("reference", True),
        ("zero", True),
        ("missing-request", True),
        ("equivalent", True),
        ("parent", True),
        ("image-alias", True),
        ("moderate-api", True),
        ("missing-init", False),
        ("over", False),
        ("boolean", False),
        ("sidecar", False),
        ("restartable-over", False),
        ("wrong-init-kind", False),
        ("parent-over", False),
        ("overhead", False),
        ("image", False),
        ("unready", False),
        ("foreign", False),
        ("terminating", False),
        ("incomplete", False),
        ("slow-api", False),
        ("cli-fails", False),
    ],
)
def test_cpu_actual_startup(monkeypatch, variant, accepted):
    assert (cpu_probe(monkeypatch, 3, variant) == 0) is accepted


def storage_probe(monkeypatch, index, variant):
    code = program(57, index, "DQ_STORAGE_POLICY" if index == 0 else "DQ_STORAGE_DATA")
    body = "current-route\n"
    contract = {
        "source": {
            "claim": "reserve",
            "deployment": "reserve",
            "container": "worker",
            "mountPath": "/archive",
            "replicas": 1,
        },
        "target": {
            "claim": "spool",
            "deployment": "relay",
            "container": "worker",
            "mountPath": "/spool",
            "replicas": 1,
        },
        "dataset": [
            {
                "path": "index.html",
                "type": "regular",
                "bytes": len(body),
                "sha256": hashlib.sha256(body.encode()).hexdigest(),
            },
            {
                "path": "payload.bin",
                "type": "regular",
                "bytes": 65536,
                "sha256": hashlib.sha256(bytes(65536)).hexdigest(),
            },
        ],
        "interface": {"port": 8080, "path": "/", "body": body},
    }
    docs, pods, sets = {}, [], []
    for label in ("source", "target"):
        role = contract[label]
        name = role["deployment"]
        spec = {
            "containers": [
                {
                    "name": "worker",
                    "image": IMAGE,
                    "volumeMounts": [
                        {
                            "name": "data",
                            "mountPath": role["mountPath"],
                            "readOnly": label == "source",
                        }
                    ],
                }
            ],
            "volumes": [
                {"name": "data", "persistentVolumeClaim": {"claimName": role["claim"]}}
            ],
        }
        docs["deployment/" + name] = deployment(name, spec)
        pods.append(owned_pod(name, spec))
        sets.append(replica_set(name))
    docs["pvc/reserve"] = {
        "metadata": {"uid": "source-claim"},
        "status": {"phase": "Bound"},
    }
    docs["pods/"], docs["replicasets/"] = {"items": pods}, {"items": sets}
    identities = {
        key: value["metadata"]["uid"]
        for key, value in docs.items()
        if key.startswith(("deployment/", "pvc/"))
    }
    facts = {"contract": contract, "identities": identities, "image": IMAGE}
    if variant in ("source-uid", "reader-uid", "target-uid"):
        key = {
            "source-uid": "pvc/reserve",
            "reader-uid": "deployment/reserve",
            "target-uid": "deployment/relay",
        }[variant]
        docs[key]["metadata"]["uid"] = "replacement"
    if variant == "source-unbound":
        docs["pvc/reserve"]["status"]["phase"] = "Pending"
    affected = (
        docs["deployment/relay"]["spec"]["template"]["spec"]
        if index == 0
        else pods[1]["spec"]
    )
    source_spec = (
        docs["deployment/reserve"]["spec"]["template"]["spec"]
        if index == 0
        else pods[0]["spec"]
    )
    if variant == "wrong-claim":
        affected["volumes"][0]["persistentVolumeClaim"]["claimName"] = "other"
    if variant == "writable-source":
        source_spec["containers"][0]["volumeMounts"][0]["readOnly"] = False
    if variant == "readonly-volume":
        source_spec["containers"][0]["volumeMounts"][0].pop("readOnly")
        source_spec["volumes"][0]["persistentVolumeClaim"]["readOnly"] = True
    if variant in ("overlay", "unrelated-mount"):
        path = "/spool/payload.bin" if variant == "overlay" else "/spool/logs"
        affected["containers"][0]["volumeMounts"].append(
            {"name": "extra", "mountPath": path, "subPath": "payload.bin"}
            if variant == "overlay"
            else {"name": "extra", "mountPath": path}
        )
        affected["volumes"].append(
            {"name": "extra", "configMap": {"name": "extra"}}
            if variant == "overlay"
            else {"name": "extra", "emptyDir": {}}
        )
    if variant == "image":
        affected["containers"][0]["image"] = OTHER
    if variant == "image-alias":
        for label in ("source", "target"):
            name = contract[label]["deployment"]
            (
                docs["deployment/" + name]["spec"]["template"]["spec"]
                if index == 0
                else pods[0 if label == "source" else 1]["spec"]
            )["containers"][0]["image"] = "alias/app@sha256:" + "a" * 64
    if variant == "replicas":
        docs["deployment/relay"]["spec"]["replicas"] = 0
    if variant == "unready":
        pods[1]["status"]["conditions"][0]["status"] = "False"
    if variant == "foreign":
        pods[1]["metadata"]["ownerReferences"][0]["uid"] = "foreign"
    if variant == "terminating":
        pods[1]["metadata"]["deletionTimestamp"] = "now"

    def output(args):
        target = args[2] == "relay-pod"
        command = args[6]
        if command == "stat":
            values = [
                "regular file:" + str(item["bytes"]) for item in contract["dataset"]
            ]
            if target and variant == "wrong-size":
                values[1] = "regular file:65535"
            if target and variant == "symlink":
                values[1] = "symbolic link:12"
            return "\n".join(values) + "\n"
        if command == "sha256sum":
            values = [
                item["sha256"] + "  " + item["path"] for item in contract["dataset"]
            ]
            if target and variant == "wrong-sha":
                values[1] = "b" * 64 + "  payload.bin"
            return "\n".join(values) + "\n"
        if command == "wget":
            return "old\n" if target and variant == "publication" else body
        raise AssertionError(args)

    return execute_probe(
        monkeypatch,
        code,
        "/run/dq/facts/0/storage-identities.json",
        facts,
        docs,
        variant,
        10 if index == 0 else 15,
        output,
    )


@pytest.mark.parametrize(
    "variant,accepted",
    [
        ("reference", True),
        ("readonly-volume", True),
        ("unrelated-mount", True),
        ("image-alias", True),
        ("moderate-api", True),
        ("source-uid", False),
        ("reader-uid", False),
        ("target-uid", False),
        ("source-unbound", False),
        ("wrong-claim", False),
        ("writable-source", False),
        ("overlay", False),
        ("image", False),
        ("slow-api", False),
        ("cli-fails", False),
    ],
)
def test_storage_identity_and_mounts(monkeypatch, variant, accepted):
    assert (storage_probe(monkeypatch, 0, variant) == 0) is accepted


@pytest.mark.parametrize(
    "variant,accepted",
    [
        ("reference", True),
        ("readonly-volume", True),
        ("unrelated-mount", True),
        ("image-alias", True),
        ("moderate-api", True),
        ("wrong-claim", False),
        ("writable-source", False),
        ("overlay", False),
        ("image", False),
        ("replicas", False),
        ("unready", False),
        ("foreign", False),
        ("terminating", False),
        ("wrong-size", False),
        ("symlink", False),
        ("wrong-sha", False),
        ("publication", False),
        ("rollout", False),
        ("slow-api", False),
        ("cli-fails", False),
    ],
)
def test_actual_pvc_data(monkeypatch, variant, accepted):
    assert (storage_probe(monkeypatch, 1, variant) == 0) is accepted


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Explicit local sandbox opt-in required",
)
@pytest.mark.parametrize("number", [34, 57])
def test_native_capacity_storage_shortcuts(number):
    catalog, runtime = Catalog(), Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": number}
    folder = Path(
        os.environ.get("DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/capacity-storage")
    )
    folder.mkdir(parents=True, exist_ok=True)
    log = {"quest": number, "commands": []}

    def execute(script, expected=0):
        result = runtime.exec(
            run, "set -euo pipefail\ncd ~/quest\n" + script, check=False, timeout=180
        )
        log["commands"].append(
            {
                "script": script,
                "exit": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
            }
        )
        assert result.returncode == expected, result.stdout + result.stderr
        return result

    def get(kind, name):
        return json.loads(
            execute("kubectl get " + kind + " " + name + " -o json").stdout
        )

    def patch(name, value):
        execute(
            "kubectl patch deployment "
            + name
            + " --type=merge -p "
            + shlex.quote(json.dumps({"spec": {"template": {"spec": value}}}))
            + "\nkubectl rollout status deployment/"
            + name
            + " --timeout=90s"
        )

    try:
        runtime.create(run)
        execute(catalog.script(number, 0, "setup"))
        runtime.capture_facts(
            dict(run, stage=0), catalog.quests[number]["immutable"][0]
        )
        kind = "deepen-cpu-phases" if number == 34 else "deepen-pvc-data"
        legacy = (
            ROOT / f"tests/fixtures/{kind}/{number:03}-legacy-check.sh"
        ).read_text()
        if number == 34:
            execute(
                "kubectl set resources deployment/board -c worker --requests=cpu=100m,memory=16Mi --limits=cpu=300m,memory=64Mi"
            )
            execute(legacy, 1)
            assert (
                "[DQ:cpu_phase]"
                in execute(catalog.script(number, 0, "check"), 1).stdout
            )
        execute((ROOT / f"tests/fixtures/{kind}/{number:03}.sh").read_text())
        execute(legacy)
        expected = "[DQ:cpu_initializer]" if number == 34 else "[DQ:storage_data_relay]"
        assert expected in execute(catalog.script(number, 0, "check"), 1).stdout
        log["old_whole_quest"] = (
            "PASS; required initializer absent"
            if number == 34
            else "PASS; target claim Bound and ready but dataset absent"
        )
        execute((ROOT / f"solutions/{number:03}/0.sh").read_text())
        execute(catalog.script(number, 0, "check"))
        if number == 34:
            execute(
                "printf '%s\\n' 'raise RuntimeError(\"untrusted cwd json\")' > json.py\nprintf '%s\\n' 'raise RuntimeError(\"untrusted cwd dq_check\")' > dq_check.py"
            )
            execute(catalog.script(number, 0, "check"))
            value = [
                {
                    "op": "replace",
                    "path": "/spec/template/spec/initContainers/0/resources/requests/cpu",
                    "value": "0",
                }
            ]
            execute(
                "kubectl patch deployment board --type=json -p "
                + shlex.quote(json.dumps(value))
                + "\nkubectl rollout status deployment/board --timeout=90s"
            )
            execute(catalog.script(number, 0, "check"))
            patch("board", {"resources": {"requests": {"cpu": "100m"}}})
            execute(catalog.script(number, 0, "check"))
            log["zero_init_request_and_pod_request_equivalence"] = "PASS"
            log["untrusted_working_directory_modules_ignored"] = "PASS"
        else:
            execute(
                "kubectl exec deployment/relay -c worker -- sh -c 'rm -f /spool/payload.bin; dd if=/dev/zero of=/tmp/payload bs=1024 count=64 2>/dev/null; ln -s /tmp/payload /spool/payload.bin'"
            )
            execute(legacy)
            assert (
                "[DQ:storage_data_relay]"
                in execute(catalog.script(number, 0, "check"), 1).stdout
            )
            execute((ROOT / "solutions/057/0.sh").read_text())
            execute(catalog.script(number, 0, "check"))
            execute(
                "kubectl exec deployment/relay -c worker -- rm /spool/index.html /spool/payload.bin"
            )
            source_uid = get("pvc", "reserve")["metadata"]["uid"]
            source = get("deployment", "reserve")["spec"]["template"]["spec"]
            fake = copy.deepcopy(source["containers"][0])
            fake["name"] = "restore-view"
            fake["command"] = [
                "sh",
                "-c",
                "cp /source/index.html /target/index.html; cp /source/payload.bin /target/payload.bin",
            ]
            fake["volumeMounts"] = [
                {"name": "source", "mountPath": "/source", "readOnly": True},
                {"name": "view", "mountPath": "/target"},
            ]
            fake["resources"] = {
                "requests": {"cpu": "10m", "memory": "8Mi"},
                "limits": {"cpu": "100m", "memory": "32Mi"},
            }
            patch(
                "relay",
                {
                    "volumes": [
                        {
                            "name": "spool",
                            "emptyDir": {},
                            "persistentVolumeClaim": None,
                        },
                        {
                            "name": "source",
                            "persistentVolumeClaim": {"claimName": "reserve"},
                        },
                        {"name": "view", "emptyDir": {}},
                    ],
                    "initContainers": [fake],
                },
            )
            # Keep the supplied main mount name but point it at the initialized emptyDir.
            execute(
                "kubectl patch deployment relay --type=json -p "
                + shlex.quote(
                    json.dumps(
                        [
                            {
                                "op": "replace",
                                "path": "/spec/template/spec/containers/0/volumeMounts/0/name",
                                "value": "view",
                            }
                        ]
                    )
                )
                + "\nkubectl rollout status deployment/relay --timeout=90s"
            )
            execute(legacy)
            assert (
                "[DQ:storage_mount_relay]"
                in execute(catalog.script(number, 0, "check"), 1).stdout
            )
            assert get("pvc", "reserve")["metadata"]["uid"] == source_uid
            log["same_bytes_on_ephemeral_view_are_not_restored_pvc_data"] = (
                "PASS rejection"
            )
        log["result"] = "PASS"
    finally:
        try:
            runtime.teardown(run)
            log["teardown"] = "PASS"
        finally:
            (folder / f"{number:03}-shortcuts.json").write_text(
                json.dumps(log, indent=2) + "\n"
            )
