"""Exercise immutable handovers, independent Git access and pinned-consumer recovery."""

import ast
import base64
import hashlib
import json
import os
import secrets
import subprocess
from pathlib import Path

import pytest
import yaml

from devops_quests.catalog import ROOT, Catalog
from devops_quests.engine import Engine
from devops_quests.runtime import Runtime
from devops_quests.store import Store


def programme(number):
    index, marker = {
        54: (0, "DQ_HANDOVER"),
        61: (1, "DQ_GIT_ACCESS"),
        68: (5, "DQ_PUBLICATION"),
        95: (5, "DQ_ROLLBACK_ADOPTION"),
    }[number]
    quest = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())
    check = quest["stages"][0]["objectives"][index]["check"]
    return check.split("<<'" + marker + "'\n", 1)[1].split("\n" + marker, 1)[0]


@pytest.mark.parametrize("number", [54, 61, 68, 95])
def test_gitops_observers_compile(number):
    compile(programme(number), f"shipped-gitops-{number}", "exec")


@pytest.mark.parametrize(
    "variant,good",
    [
        ("global-private", True),
        ("local-private", True),
        ("trailing-slash", True),
        ("public-global", False),
        ("public-local", False),
        ("wrong-password", False),
        ("wrong-binding", False),
        ("replaced-secret", False),
        ("replaced-application", False),
        ("redirected-authority", False),
        ("wrong-revision", False),
        ("auth-error", False),
        ("timeout", False),
    ],
)
def test_061_authentication_authority_and_actual_private_configuration(
    tmp_path, monkeypatch, capsys, variant, good
):
    home = tmp_path / "home"
    quest = home / "quest"
    (quest / "repository/.git").mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.chdir(quest)
    password = "private-sentinel"
    repo = "http://original.example.invalid/rail/station.git"
    receipt = {
        "repoURL": repo, "username": "rail", "passwordSha256": hashlib.sha256(password.encode()).hexdigest(),
        "credentialNamespace": "controller", "credentialName": "station-repository",
        "credentialUID": "secret-original", "applicationName": "board", "applicationUID": "app-original",
        "revision": "a" * 40,
    }
    path = quest / "delivery-access.json"
    path.write_text(json.dumps(receipt))
    data = {"url": repo, "username": "rail", "password": password, "type": "git"}
    secret = {"metadata": {"uid": "secret-original", "labels": {"argocd.argoproj.io/secret-type": "repository"}}}
    app = {"metadata": {"uid": "app-original"}}
    header = base64.b64encode(("rail:" + password).encode()).decode()
    target = quest / "repository/.git/config" if "local" in variant else home / ".gitconfig"
    target.write_text("[http]\nextraHeader = Authorization: Basic " + header + "\n")
    target.chmod(0o644 if variant.startswith("public") else 0o600)
    if variant == "wrong-password":
        data["password"] = "incorrect"
    if variant == "wrong-binding":
        data["url"] = repo + "-retired"
    if variant == "replaced-secret":
        secret["metadata"]["uid"] = "replacement"
    if variant == "replaced-application":
        app["metadata"]["uid"] = "replacement"
    secret["data"] = {key: base64.b64encode(value.encode()).decode() for key, value in data.items()}

    def output(args, **kwargs):
        assert 0 < kwargs["timeout"] <= 3
        if args[0] == "kubectl":
            return json.dumps(secret if "secret" in args else app).encode()
        if "--get-url" in args:
            return (("http://other.invalid/forged.git" if variant == "redirected-authority"
                     else repo + ("/" if variant == "trailing-slash" else "")) + "\n").encode()
        if variant == "auth-error":
            raise subprocess.CalledProcessError(128, args, stderr=password.encode())
        if variant == "timeout":
            raise subprocess.TimeoutExpired(password, 3)
        revision = "b" * 40 if variant == "wrong-revision" else receipt["revision"]
        return (revision + "\trefs/heads/main\n").encode()

    monkeypatch.setattr(subprocess, "check_output", output)
    code = programme(61).replace("/run/dq/facts/0/delivery-access.json", str(path))
    with pytest.raises(SystemExit) as result:
        exec(compile(code, "shipped-git-access", "exec"), {})
    assert (result.value.code == 0) is good
    observed = capsys.readouterr().out
    assert password not in observed and header not in observed
    if not good:
        assert "[DQ:" in observed


@pytest.mark.parametrize("layout", ["configmap", "projected", "subpath", "unrelated-token-volume"])
def test_publication_resolves_actual_file_projection_without_fixed_names(layout):
    tree = ast.parse(programme(68))
    node = next(item for item in tree.body if isinstance(item, ast.FunctionDef) and item.name == "projection")
    namespace = {"posixpath": __import__("posixpath")}
    from dq_check import workload_worker

    namespace["workload_worker"] = workload_worker
    exec(compile(ast.Module(body=[node], type_ignores=[]), "shipped-projection", "exec"), namespace)
    source = {"name": "chosen-name", "items": [{"key": "metadata", "path": "contract.json"}]}
    volume = {"name": "chosen-volume", "configMap": source}
    mount = {"name": "chosen-volume", "mountPath": "/chosen-root"}
    if layout == "projected":
        volume = {"name": "chosen-volume", "projected": {"sources": [{"configMap": source}]}}
    if layout == "subpath":
        mount = {"name": "chosen-volume", "mountPath": "/chosen-root/contract.json", "subPath": "contract.json"}
    worker = {"name": "worker", "volumeMounts": [mount]}
    volumes = [volume]
    if layout == "unrelated-token-volume":
        volumes.append({"name": "token", "projected": {"sources": [{"configMap": {"name": "unrelated-ca"}}]}})
        worker["volumeMounts"].append({"name": "token", "mountPath": "/var/run/secrets/kubernetes.io"})
    document = {"spec": {"template": {"spec": {"containers": [worker], "volumes": volumes}}}}
    maps = {"chosen-name": {"data": {"metadata": "{}"}}}
    assert namespace["projection"](document, "/chosen-root/contract.json", maps) == [("chosen-name", "metadata")]
    assert namespace["projection"](document, "/different-root/contract.json", maps) == []


@pytest.mark.parametrize(
    "variant,good",
    [
        ("reference", True), ("json-layout", True), ("observer-first", True),
        ("wrong-image", False), ("replaced-uid", False), ("wrong-metadata", False),
        ("outside-docroot", False), ("missing-git-source", False), ("projection-bypassed", False),
    ],
)
def test_068_requires_actual_approved_source_and_preserved_identity(
    tmp_path, monkeypatch, capsys, variant, good
):
    import copy

    revision = "a" * 40
    image = "fixture.invalid/provided@sha256:" + "a" * 64
    approved = {"generation": "approved", "route": "north", "consumer": "board"}
    receipt = {
        "applicationUID": "app-original", "deploymentUID": "deployment-original",
        "repoURL": "http://source.invalid/rail/station.git", "image": image,
        "index": "north\n", "contract": approved,
    }
    path = tmp_path / "publication-contract.json"
    path.write_text(json.dumps(receipt))
    published = dict(approved)
    if variant == "wrong-metadata":
        published["generation"] = "retired"
    body = json.dumps(published, indent=2 if variant == "json-layout" else None)
    cm = {"kind": "ConfigMap", "metadata": {"name": "chosen-publication"},
          "data": {"index.html": "north\n", "contract.json": body}}
    worker = {"name": "worker", "image": image,
              "volumeMounts": [{"name": "bundle", "mountPath": "/publication", "readOnly": True}]}
    live = {
        "kind": "Deployment", "metadata": {"name": "board", "uid": "deployment-original"},
        "spec": {"template": {"spec": {"containers": [worker],
                                      "volumes": [{"name": "bundle", "configMap": {"name": "chosen-publication"}}]}}},
    }
    if variant == "wrong-image":
        worker["image"] = "fixture.invalid/replacement@sha256:" + "b" * 64
    if variant == "observer-first":
        live["spec"]["template"]["spec"]["containers"].insert(0, {"name": "observer", "image": "unrelated"})
    if variant == "replaced-uid":
        live["metadata"]["uid"] = "replacement"
    if variant == "projection-bypassed":
        live["spec"]["template"]["spec"]["volumes"] = []
        worker["volumeMounts"] = []
    app = {"kind": "Application", "metadata": {"name": "board", "uid": "app-original"},
           "spec": {"source": {"repoURL": receipt["repoURL"]}},
           "status": {"sync": {"revision": revision}}}
    declared = copy.deepcopy(live)
    declared_cm = copy.deepcopy(cm)
    if variant == "missing-git-source":
        declared_cm["data"]["contract.json"] = "{}"

    def output(args, **kwargs):
        assert 0 < kwargs["timeout"] <= 3
        if args[0] == "git":
            if "rev-parse" in args:
                return (revision + "\n").encode()
            if "ls-tree" in args:
                return b"manifests/board.yaml\nmanifests/publication.yaml\n"
            return yaml.safe_dump(declared if args[-1].endswith("board.yaml") else declared_cm).encode()
        if "application/board" in args:
            return json.dumps({"items": [app, live]}).encode()
        if "configmap" in args:
            return json.dumps(cm).encode()
        if "sh" in args:
            return b"/other-root\n" if variant == "outside-docroot" else b"/publication\n"
        return body.encode()

    monkeypatch.setattr(subprocess, "check_output", output)
    code = programme(68).replace("/run/dq/facts/0/publication-contract.json", str(path))
    with pytest.raises(SystemExit) as result:
        exec(compile(code, "shipped-publication", "exec"), {})
    assert (result.value.code == 0) is good
    if not good:
        assert "[DQ:" in capsys.readouterr().out


def resources(runtime):
    result = {"containers": {}, "pod_oom": [], "oom": False}
    names = runtime.docker(
        "ps", "-aq", "--filter", "label=" + runtime.label
    ).stdout.split()
    for name in names:
        item = runtime.inspect(name)
        assert item["Config"]["Labels"]["devops-quests.installation"] == runtime.installation
        state = item["State"]
        result["containers"][item["Name"]] = {
            "id": item["Id"],
            "oom_killed": state["OOMKilled"],
        }
        result["oom"] |= state["OOMKilled"]
    pods = json.loads(runtime.kube("get", "pods", "-A", "-o", "json").stdout)
    for pod in pods["items"]:
        for status in pod.get("status", {}).get("containerStatuses", []):
            for field in ("state", "lastState"):
                if status.get(field, {}).get("terminated", {}).get("reason") == "OOMKilled":
                    result["pod_oom"].append(pod["metadata"]["namespace"] + "/" + pod["metadata"]["name"])
    result["oom"] |= bool(result["pod_oom"])
    return result


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1", reason="Explicit native sandbox opt-in"
)
@pytest.mark.parametrize("number", [54, 61, 68, 95])
async def test_native_gitops_handover_shortcut_and_engine(number, tmp_path):
    catalog = Catalog()
    runtime = Runtime(ROOT / ".state/runtime")
    fixture = ROOT / "tests/fixtures/deepen-gitops-handover"
    evidence = Path(os.environ.get("DQ_EVIDENCE_DIR", str(tmp_path)))
    evidence.mkdir(parents=True, exist_ok=True)
    record = {
        "quest": number,
        "installation": runtime.installation,
        "sources": {
            str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for folder in (ROOT / f"quests/{number:03}", ROOT / f"solutions/{number:03}")
            for path in folder.rglob("*")
            if path.is_file()
        },
        "bays": [],
    }

    def execute(run, item, script, expected=0, timeout=180):
        result = runtime.exec(
            run, "set -euo pipefail\ncd ~/quest\n" + script, check=False, timeout=timeout
        )
        item["commands"].append(
            {"script": script, "exit": result.returncode, "stdout": result.stdout, "stderr": result.stderr}
        )
        assert result.returncode == expected, result.stdout + result.stderr
        return result

    try:
        run = {"id": secrets.token_hex(12), "level": number}
        item = {"scenario": "old-shortcut", "commands": []}
        record["bays"].append(item)
        try:
            runtime.create(run)
            execute(run, item, catalog.script(number, 0, "setup"))
            runtime.capture_facts(
                dict(run, stage=0), catalog.quests[number].get("immutable", {}).get(0, [])
            )
            for goal in catalog.quests[number]["stages"][0]["objectives"]:
                if goal.get("keep"):
                    execute(run, item, goal["check"])
            current = catalog.script(number, 0, "check")
            execute(run, item, current, 1)
            old = (fixture / f"{number:03}.sh").read_text()
            # The old corrective action is unchanged. Its polling loop is not a
            # correction and cannot make the newly coupled faults recover.
            if number == 54:
                old = old.split("for _ in", 1)[0]
            elif number == 61:
                old = old.split("for i in", 1)[0]
            execute(run, item, old)
            if number in (68, 95):
                execute(run, item, (fixture / f"{number:03}-legacy-check.sh").read_text())
            result = execute(run, item, current, 1)
            marker = {
                54: "handover_binding",
                61: "credential_binding",
                68: "publication_projection",
                95: "rollback_source_a",
            }[number]
            assert "[DQ:" + marker + "]" in result.stdout
            item["resources"] = resources(runtime)
            assert not item["resources"]["oom"]
            item["result"] = "PASS"
        finally:
            runtime.teardown(run)
            item["teardown"] = "PASS"

        store = Store(tmp_path / "synthetic/progress.db")
        token = store.login("admin", store.bootstrap().read_text().strip(), "fixture")
        user = store.session(token)["user_id"]
        engine = Engine(store, catalog, runtime)
        item = {"scenario": "fresh-engine-reference", "commands": []}
        record["bays"].append(item)
        try:
            run = await engine.start(user, number, "free", minutes=120)
            initial = await engine.poll(run)
            item["initial"] = {"status": initial["status"], "goals": initial["goals"]}
            assert initial["status"] == "active"
            assert initial["goals"] == [
                bool(goal.get("keep"))
                for goal in catalog.quests[number]["stages"][0]["objectives"]
            ], initial.get("check_result")
            execute(run, item, (ROOT / f"solutions/{number:03}/0.sh").read_text(), timeout=240)
            solved = await engine.poll(run)
            item["solved"] = {"status": solved["status"], "goals": solved["goals"]}
            assert all(solved["goals"]), solved.get("check_result")
            item["resources"] = resources(runtime)
            assert not item["resources"]["oom"]
            item["result"] = "PASS"
        finally:
            await engine.stop(user)
            item["teardown"] = "PASS"
        record["result"] = "PASS"
    except BaseException as error:
        record["error"] = repr(error)
        raise
    finally:
        (evidence / f"{number:03}-gitops-native.json").write_text(
            json.dumps(record, indent=2) + "\n"
        )
