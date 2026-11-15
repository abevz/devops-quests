"""Exercise the shipped adoption probe and the old complete solution in a real bay."""

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


def program():
    check = yaml.safe_load((ROOT / "quests/121/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][3]["check"]
    return check.split("<<'DQ_ADOPTION_CURRENT'\n", 1)[1].split(
        "\nDQ_ADOPTION_CURRENT", 1
    )[0]


def fixture():
    deployments, sets, pods, identities = [], [], [], {}
    for name in ["board", "client", "route-env", "route-file"]:
        worker = {
            "name": "worker",
            "image": "app:provided",
            "command": ["sh", "provided"],
        }
        spec = {"containers": [worker]}
        if name == "route-env":
            worker["env"] = [
                {
                    "name": "ROUTE",
                    "valueFrom": {"configMapKeyRef": {"name": "route", "key": "route"}},
                }
            ]
        elif name == "route-file":
            worker["volumeMounts"] = [
                {
                    "name": "input",
                    "mountPath": "/config/route",
                    "subPath": "route",
                    "readOnly": True,
                }
            ]
            spec["volumes"] = [{"name": "input", "configMap": {"name": "route"}}]
        dep = {
            "metadata": {"name": name, "uid": name + "-uid"},
            "spec": {"template": {"spec": spec}},
        }
        deployments.append(dep)
        identities[name] = {
            "uid": name + "-uid",
            "image": "app:provided",
            "command": ["sh", "provided"],
            "args": [],
        }
        sets.append(
            {
                "metadata": {
                    "uid": name + "-rs",
                    "ownerReferences": [
                        {"kind": "Deployment", "uid": name + "-uid", "controller": True}
                    ],
                }
            }
        )
        pods.append(
            {
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
        )
    staged = {
        "metadata": {"name": "staged-route", "uid": "staged-uid"},
        "data": {"route": "retired"},
    }
    facts = {
        "deployments": identities,
        "staging": copy.deepcopy(staged),
        "contract": {
            "consumers": [
                {
                    "deployment": "route-env",
                    "mode": "environment",
                    "input": "ROUTE",
                    "output": "http://127.0.0.1:8080",
                },
                {
                    "deployment": "route-file",
                    "mode": "mounted-file",
                    "input": "/config/route",
                    "output": "http://127.0.0.1:8080",
                },
            ]
        },
    }
    docs = {
        "deployments/": {"items": deployments},
        "replicasets/": {"items": sets},
        "pods/": {"items": pods},
        "configmap/staged-route": staged,
        "configmap/route": {"data": {"route": "north-121"}},
    }
    return facts, docs


GOOD = [
    "valid",
    "volume-alias",
    "whole-volume",
    "projected",
    "implicit-readonly",
    "terminating-old",
    "unrelated",
    "moderate-api",
]
BAD = [
    "shadowed-projection",
    "staged-desired-env",
    "staged-current-env",
    "literal-env",
    "wrong-env-key",
    "duplicate-env",
    "staged-desired-file",
    "staged-current-file",
    "wrong-file-key",
    "wrong-program",
    "wrong-current-program",
    "wrong-image",
    "wrong-current-image",
    "wrong-uid",
    "staged-mutation",
    "staged-recreated",
    "wrong-record",
    "wrong-process-input",
    "wrong-http",
    "no-current",
    "unready",
    "foreign-owner",
    "duplicate-current",
    "slow-api",
    "api-error",
]


@pytest.mark.parametrize("variant", GOOD + BAD)
def test_shipped_adoption_boundaries(monkeypatch, capsys, variant):
    code = program()
    facts, docs = fixture()
    env = docs["deployments/"]["items"][2]["spec"]["template"]["spec"]["containers"][0]
    file_spec = docs["deployments/"]["items"][3]["spec"]["template"]["spec"]
    env_pod = docs["pods/"]["items"][2]
    file_pod = docs["pods/"]["items"][3]
    if variant in {"staged-desired-env", "staged-current-env"}:
        target = (
            env if variant == "staged-desired-env" else env_pod["spec"]["containers"][0]
        )
        target["env"][0]["valueFrom"]["configMapKeyRef"]["name"] = "staged-route"
    elif variant == "literal-env":
        env["env"] = [{"name": "ROUTE", "value": "north-121"}]
    elif variant == "wrong-env-key":
        env["env"][0]["valueFrom"]["configMapKeyRef"]["key"] = "unvalidated"
    elif variant == "duplicate-env":
        env["env"] *= 2
    elif variant in {"staged-desired-file", "staged-current-file"}:
        target = file_spec if variant == "staged-desired-file" else file_pod["spec"]
        target["volumes"][0]["configMap"]["name"] = "staged-route"
    elif variant == "wrong-file-key":
        file_spec["volumes"][0]["configMap"]["items"] = [
            {"key": "unvalidated", "path": "route"}
        ]
    elif variant == "shadowed-projection":
        file_spec["volumes"][0] = {
            "name": "input",
            "projected": {
                "sources": [
                    {"configMap": {"name": "route"}},
                    {
                        "secret": {
                            "name": "copied",
                            "items": [{"key": "route", "path": "route"}],
                        }
                    },
                ]
            },
        }
    elif variant in {"wrong-program", "wrong-current-program"}:
        target = env if variant == "wrong-program" else env_pod["spec"]["containers"][0]
        target["command"] = ["sh", "hardcoded"]
    elif variant in {"wrong-image", "wrong-current-image"}:
        target = env if variant == "wrong-image" else env_pod["spec"]["containers"][0]
        target["image"] = "unrelated"
    elif variant == "wrong-uid":
        docs["deployments/"]["items"][2]["metadata"]["uid"] = "recreated"
    elif variant == "staged-mutation":
        docs["configmap/staged-route"]["data"]["route"] = "north-121"
    elif variant == "staged-recreated":
        docs["configmap/staged-route"]["metadata"]["uid"] = "replacement"
    elif variant == "wrong-record":
        docs["configmap/route"]["data"]["route"] = "retired"
    elif variant == "no-current":
        docs["pods/"]["items"].remove(env_pod)
    elif variant == "unready":
        env_pod["status"]["conditions"][0]["status"] = "False"
    elif variant == "foreign-owner":
        env_pod["metadata"]["ownerReferences"][0]["uid"] = "foreign"
    elif variant == "duplicate-current":
        docs["pods/"]["items"].append(copy.deepcopy(env_pod))
    elif variant == "terminating-old":
        old = copy.deepcopy(env_pod)
        old["metadata"]["deletionTimestamp"] = "now"
        old["spec"]["containers"][0]["image"] = "older"
        docs["pods/"]["items"].append(old)
    elif variant == "unrelated":
        docs["pods/"]["items"].append({"metadata": {}, "status": {"phase": "Running"}})
    elif variant in {"volume-alias", "whole-volume", "projected", "implicit-readonly"}:
        for spec in [file_spec, file_pod["spec"]]:
            mount = spec["containers"][0]["volumeMounts"][0]
            if variant == "volume-alias":
                mount["name"] = "other"
                spec["volumes"][0]["name"] = "other"
            elif variant == "whole-volume":
                mount["mountPath"] = "/config"
                mount.pop("subPath")
            elif variant == "projected":
                spec["volumes"][0] = {
                    "name": "input",
                    "projected": {
                        "sources": [
                            {
                                "configMap": {
                                    "name": "route",
                                    "items": [{"key": "route", "path": "route"}],
                                }
                            }
                        ]
                    },
                }
            else:
                mount.pop("readOnly")
    elapsed = [0.0]
    real_read = Path.read_text

    def read(path, *args, **kwargs):
        return (
            json.dumps(facts)
            if str(path).startswith("/run/dq/facts/0/")
            else real_read(path, *args, **kwargs)
        )

    def cli(args, **kwargs):
        delay = 6 if variant == "slow-api" else 0.2 if variant == "moderate-api" else 0
        allowed = kwargs["timeout"]
        elapsed[0] += min(delay, allowed)
        if delay > allowed:
            raise subprocess.TimeoutExpired(args, allowed)
        if variant == "api-error":
            return SimpleNamespace(returncode=1, stdout="", stderr="private-sentinel")
        if args[1] == "get":
            key = args[2] + "/" + (args[3] if args[3] != "-o" else "")
            output = json.dumps(docs[key])
        else:
            tool = args[args.index("--") + 1]
            output = (
                "retired"
                if (variant == "wrong-process-input" and tool != "wget")
                or (variant == "wrong-http" and tool == "wget")
                else "north-121"
            )
        return SimpleNamespace(returncode=0, stdout=output, stderr="")

    monkeypatch.setenv("DQ_NAMESPACE", "synthetic")
    monkeypatch.setattr(Path, "read_text", read)
    monkeypatch.setattr(subprocess, "run", cli)
    monkeypatch.setattr(time, "monotonic", lambda: elapsed[0])
    with pytest.raises(SystemExit) as result:
        exec(compile(code, "shipped-adoption", "exec"), {})
    assert bool(result.value.code) == (variant in BAD)
    assert elapsed[0] <= 10
    assert "private-sentinel" not in capsys.readouterr().out


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1", reason="Explicit real sandbox opt-in"
)
def test_native_admission_adoption_shortcuts(tmp_path):
    runtime = Runtime(ROOT / ".state/runtime")
    catalog = Catalog()
    run = {"id": secrets.token_hex(12), "level": 121}
    folder = Path(os.environ.get("DQ_EVIDENCE_DIR", str(tmp_path)))
    folder.mkdir(parents=True, exist_ok=True)
    record = {"quest": 121, "commands": []}

    def execute(script, expected=0):
        result = runtime.exec(
            run, "set -euo pipefail\ncd ~/quest\n" + script, check=False, timeout=180
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

    def reference(script):
        stop = threading.Event()
        errors = []

        def observer():
            while not stop.wait(2.5):
                try:
                    runtime.game_controls(run)
                except Exception as error:
                    errors.append(str(error))

        thread = threading.Thread(target=observer)
        thread.start()
        try:
            execute(script)
        finally:
            stop.set()
            thread.join(15)
            assert not thread.is_alive() and not errors, errors

    try:
        runtime.create(run)
        execute(catalog.script(121, 0, "setup"))
        runtime.capture_facts(
            dict(run, stage=0), catalog.quests[121].get("immutable", {}).get(0, [])
        )
        old = ROOT / "tests/fixtures/deepen-adoption"
        reference((old / "121.sh").read_text())
        execute((old / "121-legacy-check.sh").read_text())
        current = catalog.script(121, 0, "check")
        execute(current, 1)
        for name in ["route-env", "route-file"]:
            assert (
                execute(
                    "kubectl exec deployment/"
                    + name
                    + " -- wget -qO- http://127.0.0.1:8080"
                ).stdout.strip()
                == "retired"
            )
        reference((ROOT / "solutions/121/0.sh").read_text())
        execute(current)
        execute(
            'kubectl patch deployment route-file --type=json -p \'[{"op":"remove","path":"/spec/template/spec/containers/0/volumeMounts/0/subPath"},{"op":"replace","path":"/spec/template/spec/containers/0/volumeMounts/0/mountPath","value":"/config"}]\'\nkubectl rollout status deployment/route-file --timeout=90s'
        )
        execute(current)
        # A desired-only stale reference must fail while the running process is correct.
        execute("kubectl rollout pause deployment/route-env")
        execute(
            'kubectl patch deployment route-env --type=strategic -p \'{"spec":{"template":{"spec":{"containers":[{"name":"worker","env":[{"name":"ROUTE","valueFrom":{"configMapKeyRef":{"name":"staged-route","key":"route"}}}]}]}}}}\''
        )
        assert (
            execute(
                "kubectl exec deployment/route-env -- printenv ROUTE"
            ).stdout.strip()
            == "north-121"
        )
        execute((old / "121-legacy-check.sh").read_text())
        execute(current, 1)
        record.update(
            result="PASS",
            old_complete_fix="rejected by adoption guard",
            whole_volume="accepted",
            desired_only_stale_source="rejected",
        )
    except BaseException as error:
        record["error"] = repr(error)
        raise
    finally:
        try:
            runtime.teardown(run)
            record["teardown"] = "PASS"
        finally:
            (folder / "121-shortcuts.json").write_text(
                json.dumps(record, indent=2) + "\n"
            )
