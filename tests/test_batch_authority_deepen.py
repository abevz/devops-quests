"""Bound current/future batch failures and separate API identity from authority."""

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
OTHER = "registry/app@sha256:" + "b" * 64


def batch_program(index):
    marker = "DQ_BATCH_POLICY" if index == 1 else "DQ_BATCH_EVIDENCE"
    source = yaml.safe_load((ROOT / "quests/072/quest.yaml").read_text())[
        "stages"
    ][0]["objectives"][index]["check"]
    return source.split("<<'" + marker + "'\n", 1)[1].split("\n" + marker, 1)[0]


def batch_state():
    execution = {
        "backoffLimit": 1, "activeDeadlineSeconds": 30, "parallelism": 1,
        "completions": 1, "restartPolicy": "Never",
    }
    facts = {
        "contract": {
            "currentJob": "importer", "recurringValidator": "validation-cycle",
            "schedule": "* * * * *", "execution": execution,
        },
        "originalJobUID": "original", "workerImage": IMAGE,
        "workerCommand": ["sh", "-c", "echo invalid-route >&2; exit 1"],
    }
    spec = {k: v for k, v in execution.items() if k != "restartPolicy"}
    spec["template"] = {"spec": {
        "restartPolicy": "Never",
        "containers": [{"name": "worker", "image": IMAGE, "command": facts["workerCommand"]}],
    }}
    current = {"metadata": {"uid": "original"}, "spec": copy.deepcopy(spec)}
    cron = {"metadata": {"uid": "cron"}, "spec": {
        "schedule": "* * * * *", "suspend": False, "concurrencyPolicy": "Forbid",
        "jobTemplate": {"spec": copy.deepcopy(spec)},
    }}
    child = {"metadata": {"uid": "child", "ownerReferences": [
        {"uid": "cron", "kind": "CronJob", "controller": True},
    ]}, "spec": copy.deepcopy(spec), "status": {
        "failed": 1, "conditions": [{"type": "Failed", "status": "True"}],
    }}
    pod = {"metadata": {"ownerReferences": [
        {"uid": "child", "kind": "Job", "controller": True},
    ]}, "spec": copy.deepcopy(spec["template"]["spec"]), "status": {
        "phase": "Failed", "containerStatuses": [
            {"name": "worker", "state": {"terminated": {"exitCode": 1}}},
        ],
    }}
    docs = {"job/importer": current, "cronjob/validation-cycle": cron,
            "jobs/": {"items": [child]}, "pods/": {"items": [pod]}}
    return facts, docs


def run_batch(monkeypatch, index, variant):
    code = batch_program(index)
    facts, docs = batch_state()
    current = docs["job/importer"]
    cron = docs["cronjob/validation-cycle"]
    template = cron["spec"]["jobTemplate"]["spec"]
    child = docs["jobs/"]["items"][0]
    pod = docs["pods/"]["items"][0]
    if variant == "current-uid":
        current["metadata"]["uid"] = "replacement"
    elif variant == "current-image":
        current["spec"]["template"]["spec"]["containers"][0]["image"] = OTHER
    elif variant == "suspended":
        cron["spec"]["suspend"] = True
    elif variant == "cancels-active":
        cron["spec"]["concurrencyPolicy"] = "Replace"
    elif variant == "wrong-schedule":
        cron["spec"]["schedule"] = "*/2 * * * *"
    elif variant == "template-image":
        template["template"]["spec"]["containers"][0]["image"] = OTHER
    elif variant == "template-command":
        template["template"]["spec"]["containers"][0]["command"] = ["true"]
    elif variant == "template-restart":
        template["template"]["spec"]["restartPolicy"] = "OnFailure"
    elif variant.startswith("template-"):
        key = variant.removeprefix("template-")
        template[key] = {"backoffLimit": 9, "activeDeadlineSeconds": 300,
                         "parallelism": 2, "completions": 2}[key]
    elif variant == "no-child":
        docs["jobs/"]["items"] = []
    elif variant == "child-owner":
        child["metadata"]["ownerReferences"][0]["uid"] = "another-cron"
    elif variant == "not-controller":
        child["metadata"]["ownerReferences"][0]["controller"] = False
    elif variant == "wrong-owner-kind":
        child["metadata"]["ownerReferences"][0]["kind"] = "Job"
    elif variant == "child-policy":
        child["spec"]["backoffLimit"] = 99
    elif variant == "child-not-failed":
        child["status"]["conditions"][0]["status"] = "False"
    elif variant == "no-failed-attempt":
        child["status"]["failed"] = 0
    elif variant == "boolean-failed":
        child["status"]["failed"] = True
    elif variant == "no-pod":
        docs["pods/"]["items"] = []
    elif variant == "pod-owner":
        pod["metadata"]["ownerReferences"][0]["uid"] = "another-job"
    elif variant == "pod-running":
        pod["status"]["phase"] = "Running"
    elif variant == "exit-zero":
        pod["status"]["containerStatuses"][0]["state"]["terminated"]["exitCode"] = 0
    elif variant == "boolean-exit":
        pod["status"]["containerStatuses"][0]["state"]["terminated"]["exitCode"] = True
    elif variant == "pod-image":
        pod["spec"]["containers"][0]["image"] = OTHER
    elif variant == "pod-command":
        pod["spec"]["containers"][0]["command"] = ["false"]
    elif variant == "same-digest":
        alias = "mirror/app@" + IMAGE.partition("@")[2]
        for spec in (current["spec"], template, child["spec"]):
            spec["template"]["spec"]["containers"][0]["image"] = alias
        pod["spec"]["containers"][0]["image"] = alias
    elif variant == "unrelated-failure":
        extra = copy.deepcopy(child)
        extra["metadata"]["ownerReferences"][0]["uid"] = "unrelated"
        extra["spec"]["backoffLimit"] = 100
        docs["jobs/"]["items"].insert(0, extra)
    real_read = Path.read_text
    elapsed = [0.0]

    def read(path, *args, **kwargs):
        if str(path) == "/run/dq/facts/0/batch-identities.json":
            return json.dumps(facts)
        return real_read(path, *args, **kwargs)

    def cli(args, **kwargs):
        if variant in ("moderate-api", "slow-api"):
            delay = 3 if variant == "moderate-api" else 6
            allowed = kwargs["timeout"]
            elapsed[0] += min(delay, allowed)
            if delay > allowed:
                raise subprocess.TimeoutExpired(args, allowed)
        if variant == "api-fails":
            return SimpleNamespace(returncode=1, stdout="", stderr="unavailable")
        if variant == "invalid-json":
            return SimpleNamespace(returncode=0, stdout="{", stderr="")
        name = args[3] if args[3] != "-o" else ""
        return SimpleNamespace(returncode=0, stdout=json.dumps(docs[args[2]+"/"+name]), stderr="")

    monkeypatch.setattr(Path, "read_text", read)
    monkeypatch.setattr(subprocess, "run", cli)
    with monkeypatch.context() as clock:
        if variant in ("moderate-api", "slow-api"):
            clock.setattr(time, "monotonic", lambda: elapsed[0])
        try:
            exec(compile(code, "shipped-batch-probe", "exec"), {})
        except SystemExit as result:
            if variant == "slow-api":
                assert elapsed[0] <= 10
            return result.code or 0
    return 0


@pytest.mark.parametrize("variant", [
    "valid", "same-digest", "moderate-api",
    "current-uid", "current-image", "suspended", "cancels-active", "wrong-schedule",
    "template-image", "template-command", "template-restart", "template-backoffLimit",
    "template-activeDeadlineSeconds", "template-parallelism", "template-completions",
    "slow-api", "api-fails", "invalid-json",
])
def test_current_and_future_policy(monkeypatch, variant):
    assert (run_batch(monkeypatch, 1, variant) == 0) is (
        variant in {"valid", "same-digest", "moderate-api"}
    )


@pytest.mark.parametrize("variant", [
    "valid", "same-digest", "unrelated-failure", "moderate-api",
    "no-child", "child-owner", "not-controller", "wrong-owner-kind", "child-policy",
    "child-not-failed", "no-failed-attempt", "boolean-failed", "no-pod", "pod-owner",
    "pod-running", "exit-zero", "boolean-exit", "pod-image", "pod-command",
    "slow-api", "api-fails", "invalid-json",
])
def test_current_scheduled_failure(monkeypatch, variant):
    assert (run_batch(monkeypatch, 2, variant) == 0) is (
        variant in {"valid", "same-digest", "unrelated-failure", "moderate-api"}
    )


@pytest.mark.skipif(os.environ.get("DQ_INTEGRATION") != "1",
                    reason="Explicit local sandbox opt-in required")
@pytest.mark.parametrize("number", [72, 114])
def test_native_batch_authority_shortcuts(number):
    catalog, runtime = Catalog(), Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": number}
    folder = Path(os.environ.get("DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/batch-authority"))
    folder.mkdir(parents=True, exist_ok=True)
    record = {"quest": number, "installation": runtime.installation, "commands": [],
              "sources": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                          for sub in (f"quests/{number:03}", f"solutions/{number:03}")
                          for p in (ROOT/sub).rglob("*") if p.is_file()}}

    def execute(script, expected=0):
        result = runtime.exec(run, "set -euo pipefail\ncd ~/quest\n"+script,
                              check=False, timeout=210)
        record["commands"].append({"script": script, "exit": result.returncode,
                                   "stdout": result.stdout, "stderr": result.stderr})
        assert result.returncode == expected, result.stdout+result.stderr
        return result

    try:
        runtime.create(run)
        execute(catalog.script(number, 0, "setup"))
        runtime.capture_facts(dict(run, stage=0), catalog.quests[number]["immutable"][0])
        keep = 0 if number == 72 else 1
        execute(catalog.quests[number]["stages"][0]["objectives"][keep]["check"])
        execute((ROOT/f"tests/fixtures/deepen-batch-authority/{number:03}.sh").read_text())
        if number == 72:
            execute((ROOT/"tests/fixtures/deepen-batch-authority/072-legacy-check.sh").read_text())
        marker = "[DQ:batch_recurrence]" if number == 72 else "[DQ:allowed]"
        assert marker in execute(catalog.script(number, 0, "check"), 1).stdout
        execute((ROOT/f"solutions/{number:03}/0.sh").read_text())
        execute(catalog.script(number, 0, "check"))
        if number == 72:
            contract = execute("cat batch-contract.json").stdout
            execute("kubectl patch cronjob validation-cycle --type=merge -p "+
                    shlex.quote(json.dumps({"spec":{"jobTemplate":{"spec":{"backoffLimit":9}}}})))
            execute("python3 -I -c 'import json; from pathlib import Path; "
                    "p=Path(\"batch-contract.json\"); v=json.loads(p.read_text()); "
                    "v[\"execution\"][\"backoffLimit\"]=9; p.write_text(json.dumps(v))'")
            assert "[DQ:batch_template]" in execute(catalog.script(number, 0, "check"), 1).stdout
            execute("kubectl patch cronjob validation-cycle --type=merge -p "+
                    shlex.quote(json.dumps({"spec":{"jobTemplate":{"spec":{"backoffLimit":1}}}})))
            execute("printf '%s' "+shlex.quote(contract)+" > batch-contract.json")
        else:
            execute('kubectl create rolebinding overbroad --role=player --serviceaccount="$DQ_NAMESPACE:reader"')
            assert "[DQ:denied_" in execute(catalog.script(number, 0, "check"), 1).stdout
            execute("kubectl delete rolebinding overbroad")
        execute(catalog.script(number, 0, "check"))
        execute(catalog.quests[number]["stages"][0]["objectives"][keep]["check"])
        record["result"] = "PASS"
    finally:
        try:
            runtime.teardown(run)
            record["teardown"] = "PASS"
        finally:
            (folder/f"{number:03}-shortcuts.json").write_text(json.dumps(record, indent=2)+"\n")
