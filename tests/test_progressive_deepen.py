"""051: source publication and retained-Service handover, including old shortcuts."""

import copy
import json
import os
import secrets
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime


def program(stage):
    source = yaml.safe_load((ROOT / "quests/051/quest.yaml").read_text())["stages"][
        stage
    ]["objectives"][0]["check"]
    return source.split("<<'DQ_PROPERTY'\n", 1)[1].split("\nDQ_PROPERTY", 1)[0]


def observed(monkeypatch, stage, variant, code):
    contract = {
        "producer": {"deployment": "relay", "sourceConfigMap": "source"},
        "consumer": {"deployment": "backup"},
        "publicService": {"name": "gateway", "port": 8080},
        "producerPath": "/release.json",
        "consumerPath": "/consumer.json",
        "consumerEnvironment": ["ROUTE", "PRODUCER_ID"],
    }
    record = {"route": "north", "producer_id": "original"}
    data = {
        "ROUTE": "north",
        "PRODUCER_ID": "original",
        "release.json": json.dumps(record),
    }
    facts = {
        "contract": contract,
        "producer_uid": "relay-id",
        "source_uid": "source-id",
        "data": copy.deepcopy(data),
    }
    retained = {
        "consumer_uid": "backup-id",
        "service_uid": "service-id",
        "producer_port": 8181,
    }

    def deployment(name):
        worker = {
            "name": "worker",
            "env": [
                {
                    "name": k,
                    "valueFrom": {"configMapKeyRef": {"name": "source", "key": k}},
                }
                for k in contract["consumerEnvironment"]
            ],
            "volumeMounts": [{"name": "config", "mountPath": "/source"}],
        }
        return {
            "metadata": {"uid": name + "-id"},
            "spec": {
                "template": {
                    "metadata": {"labels": {"app": name}},
                    "spec": {
                        "containers": [worker],
                        "volumes": [
                            {"name": "config", "configMap": {"name": "source"}}
                        ],
                    },
                }
            },
        }

    producer, consumer = deployment("relay"), deployment("backup")
    cm = {"metadata": {"uid": "source-id"}, "data": data}
    service = {
        "metadata": {"uid": "service-id"},
        "spec": {
            "type": "ClusterIP",
            "selector": {"app": "backup" if stage else "relay"},
            "ports": [{"port": 8080}],
        },
    }
    pods, replicasets = [], []
    for name in ["relay", "backup"]:
        replicasets.append(
            {
                "metadata": {
                    "uid": name + "-rs",
                    "ownerReferences": [
                        {"controller": True, "kind": "Deployment", "uid": name + "-id"}
                    ],
                }
            }
        )
        pods.append(
            {
                "metadata": {
                    "name": name + "-pod",
                    "uid": name + "-pod-id",
                    "ownerReferences": [
                        {"controller": True, "kind": "ReplicaSet", "uid": name + "-rs"}
                    ],
                },
                "status": {"conditions": [{"type": "Ready", "status": "True"}]},
            }
        )
    endpoint = {
        "metadata": {"ownerReferences": [{"kind": "Service", "uid": "service-id"}]},
        "endpoints": [
            {
                "conditions": {"ready": True},
                "targetRef": {
                    "kind": "Pod",
                    "uid": ("backup" if stage else "relay") + "-pod-id",
                },
            }
        ],
    }
    worker = consumer["spec"]["template"]["spec"]["containers"][0]
    if variant == "literal":
        worker["env"] = [
            {"name": k, "value": data[k]} for k in contract["consumerEnvironment"]
        ]
    elif variant == "envfrom":
        worker.pop("env")
        worker["envFrom"] = [{"configMapRef": {"name": "source"}}]
    elif variant in ["envfrom-unrelated", "envfrom-overridden", "secret-overridden"]:
        worker.pop("env")
        reference = "secretRef" if variant == "secret-overridden" else "configMapRef"
        worker["envFrom"] = [
            {"configMapRef": {"name": "source"}},
            {reference: {"name": "later"}},
        ]
    elif variant == "literal-overrides-envfrom":
        worker["env"] = [{"name": "ROUTE", "value": "north"}]
        worker["envFrom"] = [{"configMapRef": {"name": "source"}}]
    elif variant == "projected":
        for d in [producer, consumer]:
            d["spec"]["template"]["spec"]["volumes"] = [
                {
                    "name": "config",
                    "projected": {"sources": [{"configMap": {"name": "source"}}]},
                }
            ]
    elif variant == "unmounted":
        producer["spec"]["template"]["spec"]["containers"][0].pop("volumeMounts")
    elif variant == "changed-source":
        data["ROUTE"] = "retired"
    elif variant == "source-uid":
        cm["metadata"]["uid"] = "replacement"
    elif variant == "producer-uid":
        producer["metadata"]["uid"] = "replacement"
    elif variant == "consumer-uid":
        consumer["metadata"]["uid"] = "replacement"
    elif variant == "service-uid":
        service["metadata"]["uid"] = "replacement"
    elif variant == "wrong-selector":
        service["spec"]["selector"] = {"app": "foreign"}
    elif variant == "foreign-endpoint":
        endpoint["endpoints"][0]["targetRef"]["uid"] = "foreign-pod"
    elif variant == "foreign-slice":
        endpoint["metadata"]["ownerReferences"][0]["uid"] = "foreign-service"
    elif variant == "wrong-rs-owner":
        replicasets[stage]["metadata"]["ownerReferences"][0]["uid"] = (
            "foreign-controller"
        )
    elif variant == "unready":
        pods[stage]["status"]["conditions"][0]["status"] = "False"
    elif variant == "deleted-pod":
        pods[stage]["metadata"]["deletionTimestamp"] = "now"
    elif variant == "wrong-protocol":
        service["spec"]["ports"][0]["protocol"] = "UDP"
    elif variant == "wrong-type":
        service["spec"]["type"] = "NodePort"

    def read(path, *args, **kwargs):
        if str(path) == "/run/dq/facts/0/progressive-identities.json":
            return json.dumps(facts)
        assert str(path) == "/run/dq/facts/1/failover-identities.json"
        return json.dumps(retained)

    def cli(argv, **kwargs):
        result, code = "", 0
        if argv[:2] == ["kubectl", "get"]:
            kind = argv[2]
            if kind == "deployment":
                result = producer if argv[3] == "relay" else consumer
            elif kind in ["configmap", "secret"]:
                result = (
                    cm
                    if argv[3] == "source"
                    else {
                        "data": {"OTHER": "unrelated"}
                        if variant == "envfrom-unrelated"
                        else data
                    }
                )
            elif kind == "service":
                result = service
            else:
                result = {
                    "items": {
                        "pods": pods,
                        "replicasets": replicasets,
                        "endpointslices": [endpoint],
                    }[kind]
                }
            result = json.dumps(result)
        elif argv[:2] == ["kubectl", "rollout"]:
            code = int(variant == "producer-down" and argv[3] == "deployment/relay")
        elif "printenv" in argv:
            result = data[argv[-1]] if variant != "wrong-env" else "retired"
        else:
            assert (
                argv[:2] == ["kubectl", "exec"]
                and "-c" in argv
                and argv[argv.index("-c") + 1] == "worker"
            )
            if "127.0.0.1" in argv[-1]:
                assert ":8181/" in argv[-1]
            value = dict(record)
            if variant == "stale-http" or (
                variant == "stale-consumer" and argv[-1].endswith("/consumer.json")
            ):
                value["producer_id"] = "stale"
            result = json.dumps(value)
        return SimpleNamespace(returncode=code, stdout=result)

    monkeypatch.setattr(Path, "read_text", read)
    monkeypatch.setattr(subprocess, "run", cli)
    try:
        exec(compile(code, "051-shipped-publication", "exec"), {})
    except SystemExit as result:
        return result.code or 0
    return 0


@pytest.mark.parametrize("stage", [0, 1])
@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "projected",
        "envfrom",
        "envfrom-unrelated",
        "unmounted",
        "changed-source",
        "source-uid",
        "producer-uid",
        "wrong-selector",
        "foreign-endpoint",
        "foreign-slice",
        "wrong-rs-owner",
        "unready",
        "deleted-pod",
        "wrong-protocol",
        "wrong-type",
        "stale-http",
    ],
)
def test_current_publication_identity_and_ownership(monkeypatch, stage, variant):
    assert observed(monkeypatch, stage, variant, program(stage)) == (
        0
        if variant in ["reference", "projected", "envfrom", "envfrom-unrelated"]
        else 1
    )


@pytest.mark.parametrize(
    "variant",
    [
        "literal",
        "literal-overrides-envfrom",
        "envfrom-overridden",
        "secret-overridden",
        "consumer-uid",
        "service-uid",
        "producer-down",
        "wrong-env",
        "stale-consumer",
    ],
)
def test_failover_preserves_source_relationships(monkeypatch, variant):
    assert observed(monkeypatch, 1, variant, program(1)) == 1


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Explicit local sandbox opt-in required",
)
def test_native_old_progressive_fixes():
    catalog, runtime = Catalog(), Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": 51}
    folder = Path(
        os.environ.get("DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/progressive-shortcuts")
    )
    folder.mkdir(parents=True, exist_ok=True)
    log = {"quest": 51, "commands": []}

    def execute(script, expected=0):
        p = runtime.exec(
            run, "set -euo pipefail\ncd ~/quest\n" + script, check=False, timeout=180
        )
        log["commands"].append(
            {
                "script": script,
                "exit": p.returncode,
                "stdout": p.stdout,
                "stderr": p.stderr,
            }
        )
        assert p.returncode == expected, p.stdout + p.stderr
        return p

    try:
        runtime.create(run)
        for stage in [0, 1]:
            execute(catalog.script(51, stage, "setup"))
            runtime.capture_facts(
                dict(run, stage=stage), catalog.quests[51]["immutable"][stage]
            )
            execute(
                (ROOT / f"tests/fixtures/deepen-progressive/051-{stage}.sh").read_text()
            )
            execute(
                (
                    ROOT / f"tests/fixtures/deepen-progressive/051-legacy-{stage}.sh"
                ).read_text()
            )
            result = execute(catalog.script(51, stage, "check"), 1)
            assert "[DQ:progressive_" in result.stdout
            execute((ROOT / f"solutions/051/{stage}.sh").read_text())
            execute(catalog.script(51, stage, "check"))
        # Later envFrom wins only for keys it defines. An unrelated source is
        # valid, but a same-valued overriding source breaks the declared binding.
        execute("kubectl create configmap later --from-literal=OTHER=unrelated")
        execute(
            'kubectl patch deployment backup --type=json -p \'[{"op":"replace","path":"/spec/template/spec/containers/0/env","value":[]},{"op":"add","path":"/spec/template/spec/containers/0/envFrom","value":[{"configMapRef":{"name":"relay-source"}},{"configMapRef":{"name":"later"}}]}]\'\nkubectl rollout status deployment/backup --timeout=90s'
        )
        execute(catalog.script(51, 1, "check"))
        execute(
            "kubectl get configmap relay-source -o json | jq '{data:.data}' > override.json\nkubectl patch configmap later --type=merge --patch-file=override.json\nkubectl rollout restart deployment/backup\nkubectl rollout status deployment/backup --timeout=90s"
        )
        execute(
            (ROOT / "tests/fixtures/deepen-progressive/051-legacy-1.sh").read_text()
        )
        assert (
            "[DQ:progressive_consumer]"
            in execute(catalog.script(51, 1, "check"), 1).stdout
        )
        log["result"] = (
            "PASS; both full old stages pass their old fixes, new dataflow remains unmet"
        )
    finally:
        try:
            runtime.teardown(run)
            log["teardown"] = "PASS"
        finally:
            (folder / "051-old-minimal.json").write_text(
                json.dumps(log, indent=2) + "\n"
            )
