"""067: retained release identity and functional, deterministic chart parameters."""

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


def program(index):
    source = yaml.safe_load((ROOT / "quests/067/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][index]["check"]
    marker = "DQ_RELEASE_BUNDLE" if index == 3 else "DQ_PROPERTY"
    return source.split("<<'" + marker + "'\n", 1)[1].split("\n" + marker, 1)[0]


def probe(monkeypatch, index, variant, code):
    facts = {
        "release_id": "original-release",
        "image": "registry/app@sha256:original",
        "deployment_uid": "deployment-original",
        "source_uid": "configmap-original",
        "service_uid": "service-original",
    }
    contract = {
        "release": "board",
        "deployment": "board",
        "configMap": "board-data",
        "service": "board",
        "servicePort": 8080,
        "response": "north-67",
        "metadataPath": "/release.json",
        "renderCases": [
            {"readinessPort": 8080, "routeMessage": "north-67"},
            {"readinessPort": 8081, "routeMessage": "canary-67"},
        ],
    }
    values = {
        "image": facts["image"],
        "releaseId": facts["release_id"],
        "routeMessage": "north-67",
        "readinessPort": 8080,
    }

    def bundle(message="north-67", port=8080):
        container = {
            "name": "worker",
            "image": facts["image"],
            "ports": [{"name": "web", "containerPort": port}],
            "readinessProbe": {"httpGet": {"port": port}},
            "volumeMounts": [{"name": "source", "mountPath": "/srv"}],
        }
        deployment = {
            "kind": "Deployment",
            "metadata": {"name": "board", "uid": facts["deployment_uid"]},
            "spec": {
                "template": {
                    "metadata": {"labels": {"app": "board"}},
                    "spec": {
                        "containers": [container],
                        "volumes": [
                            {"name": "source", "configMap": {"name": "board-data"}}
                        ],
                    },
                }
            },
        }
        cm = {
            "kind": "ConfigMap",
            "metadata": {"name": "board-data", "uid": facts["source_uid"]},
            "data": {
                "index.html": message + "\n",
                "release.json": json.dumps(
                    {"release_id": facts["release_id"], "route": message}
                ),
            },
        }
        service = {
            "kind": "Service",
            "metadata": {"name": "board", "uid": facts["service_uid"]},
            "spec": {
                "selector": {"app": "board"},
                "ports": [{"port": 8080, "targetPort": "web"}],
            },
        }
        if variant == "static":
            container["readinessProbe"]["httpGet"]["port"] = 8080
            cm["data"]["index.html"] = "north-67\n"
            cm["data"]["release.json"] = json.dumps(
                {"release_id": facts["release_id"], "route": "north-67"}
            )
        elif variant == "named":
            container["readinessProbe"]["httpGet"]["port"] = "web"
        elif variant == "tcp":
            container["readinessProbe"] = {"tcpSocket": {"port": "web"}}
        elif variant == "projected":
            deployment["spec"]["template"]["spec"]["volumes"] = [
                {
                    "name": "source",
                    "projected": {"sources": [{"configMap": {"name": "board-data"}}]},
                }
            ]
        elif variant == "image-alias":
            container["image"] = "another/name@sha256:original"
        elif variant == "wrong-image":
            container["image"] = "app@sha256:replacement"
        elif variant == "unmounted":
            container["volumeMounts"] = []
        elif variant == "wrong-source":
            deployment["spec"]["template"]["spec"]["volumes"][0]["configMap"][
                "name"
            ] = "foreign"
        elif variant == "wrong-record":
            cm["data"]["release.json"] = json.dumps(
                {"release_id": "stale", "route": message}
            )
        elif variant == "wrong-message":
            cm["data"]["index.html"] = "retired\n"
        elif variant == "wrong-selector":
            service["spec"]["selector"] = {"app": "foreign"}
        elif variant == "empty-selector":
            service["spec"]["selector"] = {}
        elif variant == "bad-target":
            service["spec"]["ports"][0]["targetPort"] = "missing"
        elif variant == "wrong-protocol":
            service["spec"]["ports"][0]["protocol"] = "UDP"
        elif variant == "wrong-type":
            service["spec"]["type"] = "NodePort"
        elif variant == "wrong-namespace":
            cm["metadata"]["namespace"] = "foreign"
        elif variant.endswith("-uid"):
            {"deployment-uid": deployment, "configmap-uid": cm, "service-uid": service}[
                variant
            ]["metadata"]["uid"] = "replacement"
        docs = [deployment, cm, service]
        if variant == "duplicate":
            docs.append(copy.deepcopy(cm))
        return docs

    def read(path, *args, **kwargs):
        if str(path) == "/run/dq/facts/0/helm-identities.json":
            return json.dumps(facts)
        if str(path) == "/run/dq/facts/0/helm-contract.json":
            return json.dumps(contract)
        return original_read(path, *args, **kwargs)

    original_read = Path.read_text
    count = 0

    def cli(argv, **kwargs):
        nonlocal count
        if argv[:3] == ["helm", "get", "values"]:
            observed = dict(values)
            if variant == "wrong-values":
                observed["releaseId"] = "replacement"
            value = json.dumps(observed)
        elif argv[:2] == ["helm", "template"]:
            assert "--is-upgrade" in argv
            supplied = json.loads(original_read(Path(argv[-1])))
            docs = bundle(supplied["routeMessage"], supplied["readinessPort"])
            value = yaml.safe_dump_all(docs)
            if variant == "random":
                count += 1
                value += "\n# random " + str(count)
        elif argv[:3] == ["helm", "get", "manifest"]:
            value = yaml.safe_dump_all(bundle())
        elif argv[:2] == ["kubectl", "get"]:
            value = json.dumps(
                next(d for d in bundle() if d["kind"].lower() == argv[2])
            )
        else:
            assert argv[:3] == ["kubectl", "exec", "deployment/board"]
            value = json.dumps(
                {
                    "release_id": "stale"
                    if variant == "stale-http"
                    else facts["release_id"],
                    "route": "north-67",
                }
            )
        if variant == "cli-failed" and kwargs.get("check"):
            raise subprocess.CalledProcessError(1, argv)
        return SimpleNamespace(
            returncode=1 if variant == "cli-failed" else 0, stdout=value
        )

    monkeypatch.setattr(Path, "read_text", read)
    monkeypatch.setattr(subprocess, "run", cli)
    monkeypatch.setenv("DQ_NAMESPACE", "own-namespace")
    try:
        exec(compile(code, "067-shipped-release", "exec"), {})
    except (ValueError, KeyError, subprocess.CalledProcessError):
        return 1  # The shipped shell guard translates malformed properties.
    except SystemExit as result:
        return result.code or 0
    return 0


@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "named",
        "tcp",
        "projected",
        "image-alias",
        "static",
        "wrong-image",
        "unmounted",
        "wrong-source",
        "wrong-record",
        "wrong-message",
        "wrong-selector",
        "empty-selector",
        "bad-target",
        "wrong-protocol",
        "wrong-type",
        "wrong-namespace",
        "duplicate",
        "random",
        "wrong-values",
        "cli-failed",
    ],
)
def test_functional_render_contract(monkeypatch, variant):
    assert probe(monkeypatch, 0, variant, program(0)) == (
        0 if variant in ["reference", "named", "tcp", "projected", "image-alias"] else 1
    )


@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "named",
        "tcp",
        "projected",
        "image-alias",
        "wrong-image",
        "unmounted",
        "wrong-source",
        "wrong-record",
        "wrong-message",
        "wrong-selector",
        "empty-selector",
        "bad-target",
        "wrong-protocol",
        "wrong-type",
        "wrong-namespace",
        "duplicate",
        "stale-http",
        "cli-failed",
    ],
)
def test_released_and_live_bundle(monkeypatch, variant):
    assert probe(monkeypatch, 3, variant, program(3)) == (
        0 if variant in ["reference", "named", "tcp", "projected", "image-alias"] else 1
    )


@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "image-alias",
        "deployment-uid",
        "configmap-uid",
        "service-uid",
        "wrong-image",
        "cli-failed",
    ],
)
def test_retained_release_identities(monkeypatch, variant):
    assert probe(monkeypatch, 2, variant, program(2)) == (
        0 if variant in ["reference", "image-alias"] else 1
    )


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Explicit local sandbox opt-in required",
)
@pytest.mark.parametrize("variant", ["old-minimal", "static-manifest"])
def test_native_helm_shortcuts(variant):
    catalog, runtime = Catalog(), Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": 67}
    folder = Path(
        os.environ.get("DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/helm-shortcuts")
    )
    folder.mkdir(parents=True, exist_ok=True)
    log = {"quest": 67, "variant": variant, "commands": []}

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
        if expected is not None:
            assert p.returncode == expected, p.stdout + p.stderr
        return p

    try:
        runtime.create(run)
        execute(catalog.script(67, 0, "setup"))
        runtime.capture_facts(dict(run, stage=0), catalog.quests[67]["immutable"][0])
        if variant == "old-minimal":
            result = execute(
                (ROOT / "tests/fixtures/deepen-helm/067.sh").read_text(), None
            )
            assert (
                result.returncode != 0
            )  # Helm validates the new required input before upgrade.
            assert "routeMessage" in result.stderr + result.stdout
        else:
            execute(
                "cp chart/templates/board.yaml saved-board.yaml\nhelm get manifest board --revision 1 > chart/templates/recovered.yaml\nrm chart/templates/board.yaml\nhelm upgrade board ./chart --reset-values -f chart/values.yaml --set readinessPort=8080 --wait --timeout=90s"
            )
            execute(
                (ROOT / "tests/fixtures/deepen-helm/067-legacy-check.sh").read_text()
            )
            log["whole_legacy_quest"] = (
                "PASS; static chart does not propagate alternate input profile"
            )
        result = execute(catalog.script(67, 0, "check"), 1)
        # A missing required object is translated by the same objective's
        # outer guard; malformed bundles need not reach a property marker.
        assert any(
            marker in result.stdout
            for marker in [
                "[DQ:helm_values_contract]",
                "[DQ:helm_bundle]",
                "[DQ:probe_0_0]",
                "[DQ:probe_0_3]",
            ]
        )
        if variant == "static-manifest":
            execute(
                "mv saved-board.yaml chart/templates/board.yaml\nrm chart/templates/recovered.yaml"
            )
        execute((ROOT / "solutions/067/0.sh").read_text())
        execute(catalog.script(67, 0, "check"))
        log["result"] = "PASS"
    finally:
        try:
            runtime.teardown(run)
            log["teardown"] = "PASS"
        finally:
            (folder / ("067-" + variant + ".json")).write_text(
                json.dumps(log, indent=2) + "\n"
            )
