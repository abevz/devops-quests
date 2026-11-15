"""Exercise the shipped checkpoint and configuration-retirement boundaries."""

import base64
import copy
import hashlib
import io
import json
import os
import secrets
import subprocess
import tarfile
import time
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime

IMAGE = "registry/app@sha256:" + "a" * 64
OTHER = "registry/app@sha256:" + "b" * 64
SECRET = b"NEVER_PRINT_SECRET"
FINGERPRINT = hashlib.sha256(SECRET).hexdigest()
ORDERS = b"marker\tgeneration\troute\tunits\nsynthetic\t7\tnorth\t7\nsynthetic\t7\tsouth\t14\nsynthetic\t7\teast\t10\n"
SUMMARY = b'{"marker":"synthetic","generation":7,"total":31}\n'


def program(number, stage, index):
    quest = yaml.safe_load((ROOT / f"quests/{number}/quest.yaml").read_text())
    marker = (
        "DQ_RETIREMENT"
        if number == 129
        else "DQ_CHECKPOINT_" + ("SNAPSHOT" if stage == 0 else "RESTORE")
    )
    return (
        quest["stages"][stage]["objectives"][index]["check"]
        .split("<<'" + marker + "'\n", 1)[1]
        .split("\n" + marker, 1)[0]
    )


def deployment(name, *, replicas=1, claim=None, secret=None):
    policy = {"containers": [{"name": "worker", "image": IMAGE}]}
    if claim or secret:
        policy["containers"][0]["volumeMounts"] = [
            {
                "name": "data",
                "mountPath": "/data" if claim else "/config",
                "readOnly": True,
            }
        ]
        policy["volumes"] = [
            {
                "name": "data",
                **(
                    {"persistentVolumeClaim": {"claimName": claim}}
                    if claim
                    else {"secret": {"secretName": secret}}
                ),
            }
        ]
    return {
        "metadata": {"name": name, "uid": name + "-uid"},
        "spec": {"replicas": replicas, "template": {"spec": policy}},
    }


def owned(workloads):
    sets, pods = [], []
    for workload in workloads:
        name = workload["metadata"]["name"]
        sets.append(
            {
                "metadata": {
                    "name": name + "-rs",
                    "uid": name + "-rs",
                    "ownerReferences": [
                        {
                            "kind": "Deployment",
                            "uid": workload["metadata"]["uid"],
                            "controller": True,
                        }
                    ],
                }
            }
        )
        if workload["spec"]["replicas"]:
            pods.append(
                {
                    "metadata": {
                        "name": name + "-pod",
                        "uid": name + "-pod",
                        "ownerReferences": [
                            {
                                "kind": "ReplicaSet",
                                "uid": name + "-rs",
                                "controller": True,
                            }
                        ],
                    },
                    "spec": copy.deepcopy(workload["spec"]["template"]["spec"]),
                    "status": {
                        "phase": "Running",
                        "conditions": [{"type": "Ready", "status": "True"}],
                    },
                }
            )
    return {"items": sets}, {"items": pods}


def fixture(number):
    if number == 129:
        workloads = [
            deployment(name, secret="successor") for name in ("dispatch", "reporter")
        ]
        contract = {
            "configurationFile": "/config/value",
            "fingerprintURL": "http://127.0.0.1:8080",
            "parentLabel": "parent-uid",
        }
        data = {"value": base64.b64encode(SECRET).decode()}
        facts = {
            "contract": contract,
            "consumers": {
                item["metadata"]["name"]: {
                    "uid": item["metadata"]["uid"],
                    "image": IMAGE,
                }
                for item in workloads
            },
            "retiredParentUID": "retired-parent",
            "retiredRecordUID": "retired-record",
            "dataHash": hashlib.sha256(
                json.dumps(data, sort_keys=True).encode()
            ).hexdigest(),
            "fingerprint": FINGERPRINT,
        }
        docs = {
            "secret/successor": {
                "metadata": {"name": "successor", "uid": "successor-uid"},
                "data": data,
            }
        }
    else:
        workloads = [
            deployment("ledger", claim="ledger"),
            deployment("summary", claim="summary"),
            deployment("client"),
            deployment("journal-writer", replicas=0),
        ]
        contract = {
            "checkpointArchive": "checkpoint.tar",
            "maximumEntryBytes": 65536,
            "marker": "synthetic",
            "routes": ["north", "south", "east"],
            "writer": "journal-writer",
            "client": "client",
            "stores": [
                {
                    "entry": "orders.tsv",
                    "deployment": "ledger",
                    "claim": "ledger",
                    "path": "/data/orders.tsv",
                    "url": "http://ledger:8080/orders.tsv",
                },
                {
                    "entry": "summary.json",
                    "deployment": "summary",
                    "claim": "summary",
                    "path": "/data/summary.json",
                    "url": "http://summary:8080/summary.json",
                },
            ],
        }
        facts = {
            "contract": contract,
            "claims": {"ledger": "ledger-pvc", "summary": "summary-pvc"},
            "deployments": {
                item["metadata"]["name"]: {
                    "uid": item["metadata"]["uid"],
                    "image": IMAGE,
                }
                for item in workloads
            },
        }
        docs = {
            "persistentvolumeclaims/": {
                "items": [
                    {"metadata": {"name": name, "uid": uid}}
                    for name, uid in facts["claims"].items()
                ]
            }
        }
    sets, pods = owned(workloads)
    docs.update(
        {"deployments/": {"items": workloads}, "replicasets/": sets, "pods/": pods}
    )
    return facts, docs


def write_archive(path, variant):
    orders, summary = ORDERS, SUMMARY
    if variant == "crlf":
        orders, summary = (
            orders.replace(b"\n", b"\r\n"),
            summary.replace(b"\n", b"\r\n"),
        )
    if variant == "wrong-generation":
        summary = summary.replace(b'"generation":7', b'"generation":8')
    elif variant == "wrong-total":
        summary = summary.replace(b'"total":31', b'"total":32')
    elif variant == "boolean-generation":
        summary = summary.replace(b'"generation":7', b'"generation":true')
    elif variant == "wrong-marker":
        orders = orders.replace(b"synthetic", b"foreign")
    elif variant == "wrong-route":
        orders = orders.replace(b"north", b"west")
    elif variant == "negative-units":
        orders = orders.replace(b"north\t7", b"north\t-7")
    elif variant == "duplicate-header":
        orders = orders.replace(b"units\n", b"units\tunits\n")
    if variant == "missing-archive":
        return
    with tarfile.open(path, "w:gz" if variant == "compressed" else "w") as archive:
        entries = [("orders.tsv", orders), ("summary.json", summary)]
        if variant == "reordered":
            entries.reverse()
        if variant == "duplicate-entry":
            entries.append(entries[0])
        if variant == "extra-entry":
            entries.append(("unexpected", b"x"))
        for name, data in entries:
            member = tarfile.TarInfo("./" + name if variant == "dot-prefix" else name)
            member.size = len(data)
            if variant == "symlink" and name == "orders.tsv":
                member.type = tarfile.SYMTYPE
                member.linkname = "elsewhere"
                archive.addfile(member)
            elif variant == "oversized" and name == "orders.tsv":
                member.size = 65537
                archive.addfile(member, io.BytesIO(b"x" * 65537))
            else:
                archive.addfile(member, io.BytesIO(data))
    if variant == "truncated":
        path.write_bytes(path.read_bytes()[:600])


def execute_probe(monkeypatch, tmp_path, number, stage, index, variant):
    code = program(number, stage, index)
    facts, docs = fixture(number)
    workloads, pods = docs["deployments/"]["items"], docs["pods/"]["items"]
    first = workloads[0]
    current = pods[0]
    if variant == "wrong-uid":
        first["metadata"]["uid"] = "recreated"
    elif variant == "wrong-image":
        first["spec"]["template"]["spec"]["containers"][0]["image"] = OTHER
    elif variant == "digest-alias":
        for item in workloads:
            item["spec"]["template"]["spec"]["containers"][0]["image"] = (
                "alias@" + IMAGE.partition("@")[2]
            )
        for item in pods:
            item["spec"]["containers"][0]["image"] = "alias@" + IMAGE.partition("@")[2]
    elif variant == "wrong-owner":
        current["metadata"]["ownerReferences"][0]["uid"] = "foreign-rs"
    elif variant == "not-ready":
        current["status"]["conditions"][0]["status"] = "False"
    elif variant == "wrong-pod-image":
        current["spec"]["containers"][0]["image"] = OTHER
    elif variant == "duplicate-pod":
        pods.append(copy.deepcopy(current))
    elif variant == "terminating-old":
        old = copy.deepcopy(current)
        old["metadata"]["deletionTimestamp"] = "now"
        old["spec"]["containers"][0]["image"] = OTHER
        pods.append(old)
    elif variant == "unrelated":
        workloads.append(deployment("unrelated"))
        pods.append(
            {
                "metadata": {"name": "foreign", "uid": "foreign"},
                "spec": {},
                "status": {"phase": "Running"},
            }
        )
    if number == 128:
        write_archive(tmp_path / "checkpoint.tar", variant)
        if variant == "wrong-pvc-uid":
            docs["persistentvolumeclaims/"]["items"][0]["metadata"]["uid"] = "recreated"
        elif variant in ("wrong-claim", "wrong-pod-claim"):
            policy = (
                first["spec"]["template"]["spec"]
                if variant == "wrong-claim"
                else current["spec"]
            )
            policy["volumes"][0]["persistentVolumeClaim"]["claimName"] = "foreign"
        elif variant == "temporary-source":
            first["spec"]["template"]["spec"]["volumes"][0] = {
                "name": "data",
                "emptyDir": {},
            }
        elif variant == "writer-active":
            workloads[-1]["spec"]["replicas"] = 1
        elif variant == "writer-pod":
            extra = deployment("journal-writer")
            _, active = owned([extra])
            pods.extend(active["items"])
    else:
        secret = docs["secret/successor"]
        if variant == "retired-uid":
            secret["metadata"]["uid"] = "retired-record"
        elif variant == "parent-label":
            secret["metadata"]["labels"] = {"parent-uid": "retired-parent"}
        elif variant == "parent-owner":
            secret["metadata"]["ownerReferences"] = [{"uid": "retired-parent"}]
        elif variant == "deleting-successor":
            secret["metadata"]["deletionTimestamp"] = "now"
        elif variant == "wrong-data":
            secret["data"]["value"] = base64.b64encode(b"other").decode()
        elif variant == "extra-data":
            secret["data"]["other"] = "eA=="
        elif variant in ("wrong-source", "wrong-pod-source"):
            policy = (
                first["spec"]["template"]["spec"]
                if variant == "wrong-source"
                else current["spec"]
            )
            policy["volumes"][0]["secret"]["secretName"] = "missing"
        elif variant == "projected":
            for item in [first["spec"]["template"]["spec"], current["spec"]]:
                item["volumes"] = [
                    {
                        "name": "data",
                        "projected": {"sources": [{"secret": {"name": "successor"}}]},
                    }
                ]
        elif variant == "subpath":
            for item in [first["spec"]["template"]["spec"], current["spec"]]:
                item["containers"][0]["volumeMounts"][0].update(
                    {"mountPath": "/config/value", "subPath": "value"}
                )
        elif variant == "extra-permitted-owner":
            secret["metadata"]["ownerReferences"] = [{"uid": "independent-parent"}]
    real_read = Path.read_text

    def read(path, *args, **kwargs):
        if str(path).startswith("/run/dq/facts/0/"):
            return json.dumps(facts)
        return real_read(path, *args, **kwargs)

    elapsed = [0.0]

    def cli(args, **kwargs):
        delay = 0.2 if variant == "moderate-api" else 6 if variant == "slow-api" else 0
        allowed = kwargs["timeout"]
        elapsed[0] += min(delay, allowed)
        if delay > allowed:
            raise subprocess.TimeoutExpired(args, allowed)
        if variant == "api-error":
            return SimpleNamespace(returncode=1, stdout="", stderr="unavailable")
        if args[1] == "get":
            key = args[2] + "/" + (args[3] if args[3] != "-o" else "")
            if key not in docs:
                return SimpleNamespace(returncode=1, stdout="", stderr="missing")
            return SimpleNamespace(
                returncode=0, stdout=json.dumps(docs[key]), stderr=""
            )
        tool = args[args.index("--") + 1]
        if number == 129:
            output = FINGERPRINT + (
                "  /config/value\n" if tool == "sha256sum" else "\n"
            )
        else:
            data = ORDERS if args[-1].endswith("orders.tsv") else SUMMARY
            if variant == "crlf":
                data = data.replace(b"\n", b"\r\n")
            output = (
                hashlib.sha256(data).hexdigest() + "  file\n"
                if tool == "sha256sum"
                else data.decode()
            )
        if variant == "wrong-file" and tool == "sha256sum":
            output = "0" * 64 + "  file\n"
        elif variant == "wrong-http" and tool == "wget":
            output = "wrong\n"
        if kwargs["text"]:
            output = output.replace("\r\n", "\n").replace("\r", "\n")
        return SimpleNamespace(
            returncode=0,
            stdout=output if kwargs["text"] else output.encode(),
            stderr="" if kwargs["text"] else b"",
        )

    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(Path, "read_text", read)
    monkeypatch.setattr(subprocess, "run", cli)
    with monkeypatch.context() as clock:
        clock.setattr(time, "monotonic", lambda: elapsed[0])
        try:
            exec(compile(code, "shipped-checkpoint-retirement", "exec"), {})
        except SystemExit as result:
            assert elapsed[0] <= 10
            return result.code or 0
    return 0


COMMON_GOOD = ["valid", "digest-alias", "unrelated", "moderate-api"]
COMMON_BAD = ["wrong-uid", "wrong-image", "slow-api", "api-error"]
ARCHIVE_BAD = [
    "wrong-generation",
    "wrong-total",
    "boolean-generation",
    "wrong-marker",
    "wrong-route",
    "negative-units",
    "duplicate-header",
    "missing-archive",
    "duplicate-entry",
    "extra-entry",
    "symlink",
    "oversized",
    "truncated",
    "wrong-pvc-uid",
]
DELIVERY_BAD = [
    "wrong-owner",
    "not-ready",
    "wrong-pod-image",
    "duplicate-pod",
    "wrong-file",
    "wrong-http",
]
CASES = [
    (
        128,
        0,
        0,
        COMMON_GOOD + ["compressed", "dot-prefix", "reordered", "crlf"],
        COMMON_BAD + ARCHIVE_BAD,
    ),
    (
        128,
        1,
        2,
        COMMON_GOOD + ["terminating-old", "compressed", "reordered", "crlf"],
        COMMON_BAD
        + ARCHIVE_BAD
        + DELIVERY_BAD
        + [
            "wrong-claim",
            "wrong-pod-claim",
            "temporary-source",
            "writer-active",
            "writer-pod",
        ],
    ),
    (
        129,
        0,
        0,
        COMMON_GOOD
        + ["terminating-old", "projected", "subpath", "extra-permitted-owner"],
        COMMON_BAD
        + DELIVERY_BAD
        + [
            "retired-uid",
            "parent-label",
            "parent-owner",
            "deleting-successor",
            "wrong-data",
            "extra-data",
            "wrong-source",
            "wrong-pod-source",
        ],
    ),
]


@pytest.mark.parametrize(
    "number,stage,index,variant,accepted",
    [
        (number, stage, index, variant, accepted)
        for number, stage, index, good, bad in CASES
        for accepted, variants in ((True, good), (False, bad))
        for variant in variants
    ],
)
def test_shipped_checkpoint_retirement_boundaries(
    monkeypatch, tmp_path, capsys, number, stage, index, variant, accepted
):
    assert (
        execute_probe(monkeypatch, tmp_path, number, stage, index, variant) == 0
    ) is accepted
    output = capsys.readouterr()
    assert "NEVER_PRINT_SECRET" not in output.out + output.err


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Explicit local sandbox opt-in required",
)
@pytest.mark.parametrize("number", [128, 129])
def test_native_checkpoint_retirement_shortcuts(number):
    runtime, catalog = Runtime(ROOT / ".state/runtime"), Catalog()
    run = {"id": secrets.token_hex(12), "level": number}
    folder = Path(
        os.environ.get("DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/checkpoint-retirement")
    )
    folder.mkdir(parents=True, exist_ok=True)
    record = {"quest": number, "commands": []}

    def execute(script, expected=0, timeout=240):
        result = runtime.exec(
            run,
            "set -euo pipefail\ncd ~/quest\n" + script,
            check=False,
            timeout=timeout,
        )
        record["commands"].append(
            {
                "script": script,
                "exit": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
            }
        )
        assert result.returncode == expected, result.stdout + result.stderr
        return result

    fixtures = ROOT / "tests/fixtures/deepen-checkpoint-retirement"
    try:
        runtime.create(run)
        execute(catalog.script(number, 0, "setup"))
        runtime.capture_facts(
            dict(run, stage=0), catalog.quests[number]["immutable"][0]
        )
        for objective in catalog.quests[number]["stages"][0]["objectives"]:
            if objective.get("keep"):
                execute(objective["check"])
        suffix = "129" if number == 129 else "128-0"
        execute((fixtures / (suffix + ".sh")).read_text())
        execute((fixtures / (suffix + "-legacy-check.sh")).read_text())
        execute(catalog.script(number, 0, "check"), 1)
        record["old_minimum"] = (
            "Complete old reference/check pass; current workflow rejects"
        )
        if number == 128:
            execute((ROOT / "solutions/128/0.sh").read_text())
            execute(catalog.script(128, 0, "check"))
            execute(catalog.script(128, 1, "setup"))
            for objective in catalog.quests[128]["stages"][1]["objectives"]:
                if objective.get("keep"):
                    execute(objective["check"])
            execute((fixtures / "128-1.sh").read_text())
            execute((fixtures / "128-1-legacy-check.sh").read_text())
            execute(catalog.script(128, 1, "check"), 1)
            execute((ROOT / "solutions/128/1.sh").read_text())
            execute(catalog.script(128, 1, "check"))
        else:
            # The exact old reference destroys the source and parent. This is
            # a terminal no-shortcut bay, not a fresh-reference fixture. The
            # regular native matrix proves the complete new solution fresh.
            source = execute("kubectl get deployment dispatch -o json").stdout
            assert (
                json.loads(source)["spec"]["template"]["spec"]["volumes"][0]["secret"][
                    "secretName"
                ]
                == "station-record"
            )
        record["result"] = "PASS"
    finally:
        try:
            runtime.teardown(run)
            record["teardown"] = "PASS"
        finally:
            (folder / f"{number}-shortcuts.json").write_text(
                json.dumps(record, indent=2) + "\n"
            )
