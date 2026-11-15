"""116: controller acknowledgement does not prove consumer configuration delivery."""

import copy
import json
import os
import secrets
import subprocess
import threading
import time
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime


def program(index, marker):
    source = yaml.safe_load((ROOT / "quests/116/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][index]["check"]
    return source.split("<<'" + marker + "'\n", 1)[1].split("\n" + marker, 1)[0]


def probe(monkeypatch, index, variant):
    contract = {
        "producer": {"deployment": "board", "container": "board"},
        "consumer": {
            "deployment": "client",
            "container": "worker",
            "service": "client-view",
            "replicas": 1,
        },
        "interface": {
            "type": "ClusterIP",
            "port": 8080,
            "path": "/",
            "body": "north-116\n",
        },
    }
    image = "registry/app@sha256:original"
    docs = {
        "stationboard/station": {"metadata": {"uid": "station"}},
        "configmap/board-route": {"metadata": {"uid": "route"}},
        "service/client-view": {
            "metadata": {"uid": "service"},
            "spec": {"selector": {"app": "client"}, "ports": [{"port": 8080}]},
        },
    }
    for name, container in (("board", "board"), ("client", "worker")):
        docs["deployment/" + name] = {
            "metadata": {"uid": name},
            "spec": {
                "replicas": 1,
                "template": {
                    "metadata": {"labels": {"app": name}},
                    "spec": {"containers": [{"name": container, "image": image}]},
                },
            },
            "status": {"readyReplicas": 1},
        }
    identities = {
        key: value["metadata"]["uid"]
        for key, value in docs.items()
        if key != "deployment/board"
    }
    facts = {"contract": contract, "identities": identities, "image": image}
    owner = {"kind": "Deployment", "uid": "client", "controller": True}
    pod = {
        "metadata": {
            "name": "client-123",
            "ownerReferences": [
                {"kind": "ReplicaSet", "uid": "rs", "controller": True}
            ],
        },
        "spec": {"containers": [{"name": "worker", "image": image}]},
        "status": {
            "phase": "Running",
            "conditions": [{"type": "Ready", "status": "True"}],
        },
    }
    docs["pods/"] = {"items": [pod]}
    docs["replicasets/"] = {
        "items": [{"metadata": {"uid": "rs", "ownerReferences": [owner]}}]
    }
    response = contract["interface"]["body"]
    if variant in ("station-uid", "source-uid", "client-uid", "service-uid"):
        key = {
            "station-uid": "stationboard/station",
            "source-uid": "configmap/board-route",
            "client-uid": "deployment/client",
            "service-uid": "service/client-view",
        }[variant]
        docs[key]["metadata"]["uid"] = "replacement"
    if variant in ("producer-image", "consumer-image"):
        name = "board" if variant == "producer-image" else "client"
        docs["deployment/" + name]["spec"]["template"]["spec"]["containers"][0][
            "image"
        ] = "other"
    if variant == "image-alias":
        for key in ("deployment/board", "deployment/client"):
            docs[key]["spec"]["template"]["spec"]["containers"][0]["image"] = (
                "alias@sha256:original"
            )
        pod["spec"]["containers"][0]["image"] = "alias@sha256:original"
    if variant == "pod-image":
        pod["spec"]["containers"][0]["image"] = "other"
    if variant == "foreign-rs":
        owner["uid"] = "foreign"
    if variant == "foreign-pod":
        pod["metadata"]["ownerReferences"][0]["uid"] = "foreign"
    if variant == "terminating":
        pod["metadata"]["deletionTimestamp"] = "now"
    if variant == "unready":
        pod["status"]["conditions"][0]["status"] = "False"
    if variant == "no-pods":
        docs["pods/"]["items"] = []
    if variant == "replicas":
        docs["deployment/client"]["spec"]["replicas"] = 0
    if variant == "not-ready":
        docs["deployment/client"]["status"]["readyReplicas"] = 0
    if variant == "selector":
        docs["service/client-view"]["spec"]["selector"] = {"app": "board"}
    if variant == "empty-selector":
        docs["service/client-view"]["spec"]["selector"] = {}
    if variant == "port":
        docs["service/client-view"]["spec"]["ports"][0]["port"] = 9090
    if variant == "protocol":
        docs["service/client-view"]["spec"]["ports"][0]["protocol"] = "UDP"
    if variant == "external":
        docs["service/client-view"]["spec"]["type"] = "ExternalName"
    if variant == "stale":
        response = "closed\n"
    if variant == "no-newline":
        response = "north-116"
    real_read = Path.read_text

    def read(path, *args, **kwargs):
        if str(path) == "/run/dq/facts/0/reconciliation-identities.json":
            return json.dumps(facts)
        return real_read(path, *args, **kwargs)

    elapsed = [0.0]

    def cli(args, **kwargs):
        if variant in ("slow-api", "moderate-api"):
            delay = 2.25 if variant == "slow-api" else 1.25
            remaining = kwargs["timeout"]
            elapsed[0] += min(delay, remaining)
            if delay > remaining:
                raise subprocess.TimeoutExpired(args, remaining)
        if variant == "cli-fails":
            return SimpleNamespace(returncode=1, stdout="", stderr="no API")
        if args[1] == "get":
            name = args[3] if args[3] != "-o" else ""
            text = json.dumps(docs[args[2] + "/" + name])
        elif args[1] == "rollout":
            return SimpleNamespace(
                returncode=int(variant == "rollout"), stdout="", stderr=""
            )
        elif args[1] == "exec":
            text = response
        else:
            raise AssertionError(args)
        return SimpleNamespace(returncode=0, stdout=text, stderr="")

    monkeypatch.setattr(Path, "read_text", read)
    monkeypatch.setattr(subprocess, "run", cli)
    marker = (
        "DQ_RECONCILIATION_IDENTITY" if index == 0 else "DQ_RECONCILIATION_DELIVERY"
    )
    code = program(index, marker)
    with monkeypatch.context() as clock_patch:
        if variant in ("slow-api", "moderate-api"):
            clock_patch.setattr(time, "monotonic", lambda: elapsed[0])
        try:
            exec(compile(code, "shipped-reconciliation-check", "exec"), {})
        except SystemExit as result:
            if variant == "slow-api":
                assert elapsed[0] <= 10
            return result.code or 0
    return 0


@pytest.mark.parametrize(
    "variant,accepted",
    [
        ("reference", True),
        ("image-alias", True),
        ("moderate-api", True),
        ("slow-api", False),
        ("station-uid", False),
        ("source-uid", False),
        ("client-uid", False),
        ("service-uid", False),
        ("producer-image", False),
        ("consumer-image", False),
        ("cli-fails", False),
    ],
)
def test_original_reconciliation_identity_and_images(
    monkeypatch, variant, accepted, capsys
):
    assert (probe(monkeypatch, 0, variant) == 0) is accepted
    if variant == "slow-api":
        assert "[DQ:reconciliation_image]" in capsys.readouterr().out


@pytest.mark.parametrize(
    "variant,accepted",
    [
        ("reference", True),
        ("image-alias", True),
        ("moderate-api", True),
        ("slow-api", False),
        ("pod-image", False),
        ("foreign-rs", False),
        ("foreign-pod", False),
        ("terminating", False),
        ("unready", False),
        ("no-pods", False),
        ("replicas", False),
        ("not-ready", False),
        ("selector", False),
        ("empty-selector", False),
        ("port", False),
        ("protocol", False),
        ("external", False),
        ("stale", False),
        ("no-newline", False),
        ("rollout", False),
        ("cli-fails", False),
    ],
)
def test_actual_consumer_delivery(monkeypatch, variant, accepted, capsys):
    assert (probe(monkeypatch, 2, variant) == 0) is accepted
    if variant == "slow-api":
        assert "[DQ:reconciliation_service]" in capsys.readouterr().out


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Explicit local sandbox opt-in required",
)
def test_native_controller_reconciliation_is_not_consumer_delivery():
    catalog, runtime = Catalog(), Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": 116}
    folder = Path(
        os.environ.get("DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/reconciliation")
    )
    folder.mkdir(parents=True, exist_ok=True)
    log = {"quest": 116, "commands": []}
    stop = threading.Event()
    errors = []
    thread = None

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

    def observer():
        while not stop.wait(2.5):
            try:
                runtime.observe(run)
            except (
                RuntimeError,
                OSError,
                ValueError,
                KeyError,
                subprocess.SubprocessError,
            ) as error:
                errors.append(str(error))

    def get(kind, name):
        return json.loads(
            execute("kubectl get " + kind + " " + name + " -o json").stdout
        )

    try:
        runtime.create(run)
        execute(catalog.script(116, 0, "setup"))
        runtime.capture_facts(dict(run, stage=0), catalog.quests[116]["immutable"][0])
        runtime.observe(run)
        execute(catalog.script(116, 0, "check"), 1)
        thread = threading.Thread(target=observer, daemon=True)
        thread.start()
        legacy = (
            ROOT / "tests/fixtures/deepen-reconciliation/116-legacy-check.sh"
        ).read_text()
        execute((ROOT / "tests/fixtures/deepen-reconciliation/116.sh").read_text())
        execute(legacy)
        assert (
            "[DQ:reconciliation_publication]"
            in execute(catalog.script(116, 0, "check"), 1).stdout
        )
        log["old_whole_quest"] = (
            "PASS; current controller/producer but stale consumer publication"
        )
        execute((ROOT / "solutions/116/0.sh").read_text())
        execute(catalog.script(116, 0, "check"))
        before = get("pods", "-l app=client")["items"]
        client = get("deployment", "client")
        mounts = copy.deepcopy(
            client["spec"]["template"]["spec"]["containers"][0]["volumeMounts"]
        )
        mounts[0].pop("subPath")
        mounts[0]["mountPath"] = "/tmp/site"
        patch = json.dumps(
            [
                {
                    "op": "replace",
                    "path": "/spec/template/spec/containers/0/volumeMounts",
                    "value": mounts,
                }
            ]
        )
        import shlex

        execute(
            "kubectl patch deployment client --type=json -p "
            + shlex.quote(patch)
            + "\nkubectl rollout status deployment/client --timeout=90s"
        )
        for pod in before:
            execute(
                "kubectl wait --for=delete pod/"
                + pod["metadata"]["name"]
                + " --timeout=30s"
            )
        execute(catalog.script(116, 0, "check"))
        log["whole_volume_delivery_equivalence"] = "PASS"
        service = get("service", "client-view")
        replacement = {
            "apiVersion": "v1",
            "kind": "Service",
            "metadata": {"name": "client-view"},
            "spec": {
                "selector": service["spec"]["selector"],
                "ports": service["spec"]["ports"],
            },
        }
        execute(
            "kubectl delete service client-view\nkubectl apply -f - <<'OBJECT'\n"
            + json.dumps(replacement)
            + "\nOBJECT"
        )
        execute(legacy)
        assert (
            "[DQ:reconciliation_identity]"
            in execute(catalog.script(116, 0, "check"), 1).stdout
        )
        log["same_name_consumer_service_is_not_original"] = "PASS rejection"
        assert not errors, errors
        log["result"] = "PASS"
    finally:
        stop.set()
        if thread is not None:
            thread.join(30)
        try:
            runtime.teardown(run)
            log["teardown"] = "PASS"
        finally:
            (folder / "116-shortcuts.json").write_text(json.dumps(log, indent=2) + "\n")
