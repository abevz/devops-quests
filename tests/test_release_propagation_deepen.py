"""082: release input adoption and real consumer snapshot propagation."""

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
    source = yaml.safe_load((ROOT / "quests/082/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][index]["check"]
    return source.split("<<'DQ_RELEASE'\n", 1)[1].split("\nDQ_RELEASE", 1)[0]


def probe(monkeypatch, index, variant, code):
    producer = {
        "release": "board",
        "deployment": "relay",
        "service": "board",
        "configMap": "source",
    }
    consumers = [
        {"release": name, "deployment": name, "service": name}
        for name in ["dispatcher", "archive"]
    ]
    contract = {
        "producer": producer,
        "consumers": consumers,
        "servicePort": 8080,
        "metadataPath": "/release.json",
    }
    publication = {"publication_id": "current", "route": "signalrail"}
    image = "registry/app@sha256:original"
    identities = {
        kind + "/" + name: kind + "-" + name
        for kind, name in [
            ("deployment", "relay"),
            ("configmap", "source"),
            ("service", "board"),
            ("deployment", "dispatcher"),
            ("service", "dispatcher"),
            ("deployment", "archive"),
            ("service", "archive"),
        ]
    }
    data = {"index.html": "signalrail\n", "release.json": json.dumps(publication)}
    facts = {
        "contract": contract,
        "identities": identities,
        "image": image,
        "data": copy.deepcopy(data),
        "publication": publication,
    }
    live = {}
    for key, uid in identities.items():
        kind, name = key.split("/")
        value = {"metadata": {"uid": uid}, "spec": {}}
        if kind == "deployment":
            value["spec"] = {
                "template": {
                    "spec": {"containers": [{"name": "worker", "image": image}]}
                }
            }
        if kind == "configmap":
            value["data"] = data
        if kind == "service":
            value["spec"] = {"clusterIP": "10.96.0.10"}
        live[key] = value
    if variant.endswith("-uid"):
        name = {
            "producer-uid": "deployment/relay",
            "source-uid": "configmap/source",
            "consumer-uid": "deployment/archive",
            "service-uid": "service/dispatcher",
        }[variant]
        live[name]["metadata"]["uid"] = "replacement"
    if variant == "changed-source":
        data["index.html"] = "retired\n"
    for endpoint in [producer] + consumers:
        if variant in ["wrong-image", "image-alias"]:
            live["deployment/" + endpoint["deployment"]]["spec"]["template"]["spec"][
                "containers"
            ][0]["image"] = "alias/app@sha256:" + (
                "replacement" if variant == "wrong-image" else "original"
            )

    def read(path, *args, **kwargs):
        assert str(path) == "/run/dq/facts/0/release-identities.json"
        return json.dumps(facts)

    def cli(argv, **kwargs):
        if argv[:2] == ["kubectl", "get"]:
            value = json.dumps(live[argv[2] + "/" + argv[3]])
        elif argv[:3] == ["helm", "get", "values"]:
            values = {"image": image}
            if argv[3] == "board":
                values.update(
                    port=8080,
                    publicationId="stale"
                    if variant == "old-producer-values"
                    else "current",
                )
            else:
                values.update(
                    upstreamPort=9090 if variant == "old-consumer-port" else 8080,
                    expectedPublication="stale"
                    if variant == "old-consumer-values"
                    else "current",
                )
            if variant == "wrong-image":
                values["image"] = "registry/app@sha256:replacement"
            if variant == "image-alias":
                values["image"] = "alias/app@sha256:original"
            value = json.dumps(values)
        elif "printenv" in argv:
            assert (
                argv[:2] == ["kubectl", "exec"]
                and "-c" in argv
                and argv[argv.index("-c") + 1] == "worker"
            )
            host = {
                "fqdn": "board.own.svc.cluster.local",
                "short-qualified": "board.own",
                "svc-qualified": "board.own.svc",
                "cluster-ip": "10.96.0.10",
                "foreign-host": "foreign",
                "foreign-namespace": "board.other.svc",
            }.get(variant, "board")
            value = (
                "http://"
                + host
                + (":9090" if variant == "wrong-upstream-port" else ":8080")
                + ("/other.json" if variant == "wrong-path" else "/release.json")
            )
            if variant == "userinfo":
                value = "http://user@board:8080/release.json"
            if variant == "query":
                value += "?cached=1"
            if variant == "fragment":
                value += "#cached"
            if variant == "wrong-scheme":
                value = value.replace("http:", "https:")
            if argv[-1] == "EXPECTED_PUBLICATION":
                value = "stale" if variant == "old-running-input" else "current"
        else:
            assert (
                argv[:3] == ["kubectl", "exec", "deployment/relay"]
                and "-c" in argv
                and argv[argv.index("-c") + 1] == "worker"
            )
            uri = argv[-1]
            response = dict(publication)
            if variant == "stale-producer-http" and "http://board:" in uri:
                response["publication_id"] = "stale"
            if variant == "stale-consumer-http" and "http://archive:" in uri:
                response["publication_id"] = "stale"
            if variant == "wrong-route":
                response["route"] = "retired"
            value = json.dumps(response)
        return SimpleNamespace(returncode=int(variant == "cli-failed"), stdout=value)

    monkeypatch.setattr(Path, "read_text", read)
    monkeypatch.setattr(subprocess, "run", cli)
    monkeypatch.setenv("DQ_NAMESPACE", "own")
    try:
        exec(compile(code, "082-shipped-propagation", "exec"), {})
    except (ValueError, KeyError):
        return 1
    except SystemExit as result:
        return result.code or 0
    return 0


@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "fqdn",
        "short-qualified",
        "svc-qualified",
        "cluster-ip",
        "image-alias",
        "old-producer-values",
        "old-consumer-port",
        "old-consumer-values",
        "old-running-input",
        "foreign-host",
        "foreign-namespace",
        "wrong-upstream-port",
        "wrong-path",
        "userinfo",
        "query",
        "fragment",
        "wrong-scheme",
        "wrong-image",
        "cli-failed",
    ],
)
def test_current_release_values_and_effective_consumer_inputs(monkeypatch, variant):
    assert probe(monkeypatch, 1, variant, program(1)) == (
        0
        if variant
        in [
            "reference",
            "fqdn",
            "short-qualified",
            "svc-qualified",
            "cluster-ip",
            "image-alias",
        ]
        else 1
    )


@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "image-alias",
        "producer-uid",
        "source-uid",
        "consumer-uid",
        "service-uid",
        "changed-source",
        "wrong-image",
        "stale-producer-http",
        "stale-consumer-http",
        "wrong-route",
        "cli-failed",
    ],
)
def test_retained_resources_and_current_public_records(monkeypatch, variant):
    assert probe(monkeypatch, 3, variant, program(3)) == (
        0 if variant in ["reference", "image-alias"] else 1
    )


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Explicit local sandbox opt-in required",
)
@pytest.mark.parametrize(
    "variant", ["old-minimal", "upstream-only", "recreated-service"]
)
def test_native_release_propagation_shortcuts(variant):
    catalog, runtime = Catalog(), Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": 82}
    folder = Path(
        os.environ.get("DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/release-propagation")
    )
    folder.mkdir(parents=True, exist_ok=True)
    log = {"quest": 82, "variant": variant, "commands": []}

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

    try:
        runtime.create(run)
        execute(catalog.script(82, 0, "setup"))
        runtime.capture_facts(dict(run, stage=0), catalog.quests[82]["immutable"][0])
        legacy = (
            ROOT / "tests/fixtures/deepen-release-propagation/082-legacy-check.sh"
        ).read_text()
        execute((ROOT / "tests/fixtures/deepen-release-propagation/082.sh").read_text())
        execute(legacy)
        # The standard aggregate prelude collects failing objectives even
        # when its workstation caller enables errexit. Both markers prove
        # that later goals were evaluated after the first failing objective.
        result = execute(catalog.script(82, 0, "check"), 1)
        assert (
            "[DQ:release_values]" in result.stdout
            and "[DQ:release_publication]" in result.stdout
        )
        log["whole_old_quest"] = (
            "PASS; both native consumer snapshots still older than current producer"
        )
        if variant == "upstream-only":
            execute(
                "helm upgrade dispatcher ./dispatcher --reuse-values --set upstreamPort=8080"
            )
            execute(legacy)
            assert (
                "[DQ:release_values]"
                in execute(catalog.script(82, 0, "check"), 1).stdout
            )
            log["upstream_only"] = (
                "Retained expectedPublication remains old; endpoint repair alone is insufficient"
            )
        execute((ROOT / "solutions/082/0.sh").read_text())
        execute(catalog.script(82, 0, "check"))
        if variant == "old-minimal":
            execute(
                "python3 -I - <<'PYTHON'\nimport os\nfrom pathlib import Path\np=Path('dispatcher/templates/resources.yaml')\np.write_text(p.read_text().replace('http://board:', 'http://board.'+os.environ['DQ_NAMESPACE']+'.svc.cluster.local:'))\nPYTHON\nhelm upgrade dispatcher ./dispatcher --reset-values -f dispatcher/values.yaml --wait --timeout=90s"
            )
            # Reuse the reference's actual Service propagation wait.
            reference = (ROOT / "solutions/082/0.sh").read_text()
            execute(reference[reference.index("python3 -I - <<'DQ_PUBLICATION'") :])
            execute(catalog.script(82, 0, "check"))
            log["fully_qualified_source_service"] = "PASS"
        elif variant == "recreated-service":
            execute(
                "kubectl get service archive -o json > service.json\npython3 -I - <<'PYTHON'\nimport json\nfrom pathlib import Path\np=Path('service.json');v=json.loads(p.read_text());v['metadata']={k:w for k,w in v['metadata'].items() if k in ['name','namespace','labels','annotations']};v.pop('status',None);p.write_text(json.dumps(v))\nPYTHON\nkubectl delete service archive\nkubectl create -f service.json"
            )
            execute(legacy)
            assert (
                "[DQ:release_identity]"
                in execute(catalog.script(82, 0, "check"), 1).stdout
            )
        log["result"] = "PASS"
    finally:
        try:
            runtime.teardown(run)
            log["teardown"] = "PASS"
        finally:
            (folder / ("082-" + variant + ".json")).write_text(
                json.dumps(log, indent=2) + "\n"
            )
