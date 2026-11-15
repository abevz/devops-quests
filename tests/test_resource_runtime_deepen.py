"""088/094: real startup data, finite budgets and active demand consumers."""

import copy
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


def objective(number, index):
    return yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())[
        "stages"
    ][0]["objectives"][index]["check"]


def program(number, index, marker):
    return (
        objective(number, index)
        .split("<<'" + marker + "'\n", 1)[1]
        .split("\n" + marker, 1)[0]
    )


def execute_python(monkeypatch, code, facts_path, facts, cli):
    original = Path.read_text

    def read(path, *args, **kwargs):
        if str(path) == facts_path:
            return json.dumps(facts)
        return original(path, *args, **kwargs)

    monkeypatch.setattr(Path, "read_text", read)
    monkeypatch.setattr(subprocess, "run", cli)
    monkeypatch.setattr(time, "sleep", lambda _: None)
    try:
        exec(compile(code, "shipped-resource-runtime", "exec"), {})
    except (ValueError, KeyError, TypeError, AttributeError):
        return 1
    except SystemExit as result:
        return result.code or 0
    return 0


def memory_probe(monkeypatch, index, variant, code):
    roles = [
        {"deployment": "relay", "service": "relay"},
        {"deployment": "stager", "service": "stager", "initializer": "warmer"},
        {"deployment": "reader", "service": "reader"},
    ]
    publication = {"cache_id": "current", "bytes": 83886080, "sha256": "payload-digest"}
    contract = {
        "producer": "relay",
        "roles": roles,
        "sourceConfigMap": "source",
        "memory": {"podCeiling": "96Mi"},
        "memoryPath": "/cache",
        "payloadPath": "/cache/payload",
        "dataset": {"bytes": publication["bytes"], "sha256": publication["sha256"]},
        "filesystem": "tmpfs",
        "metadataPath": "/record.json",
        "servicePort": 8080,
        "serviceType": "ClusterIP",
    }
    policy = {"CACHE_MIB": "80", "CACHE_ID": "current"}
    image = "registry/app@sha256:original"
    docs, pods, sets, identities = {}, [], [], {}

    def worker(name="worker", memory="96Mi"):
        return {
            "name": name,
            "image": image,
            "resources": {"limits": {"memory": memory}},
        }

    for role in roles:
        name = role["deployment"]
        spec = {"containers": [worker()]}
        if role.get("initializer"):
            spec["initContainers"] = [worker("warmer", "90Mi")]
        deployment = {
            "metadata": {"uid": name + "-deployment"},
            "spec": {
                "template": {
                    "metadata": {"labels": {"app": name}},
                    "spec": copy.deepcopy(spec),
                }
            },
        }
        docs["deployment/" + name] = deployment
        docs["service/" + name] = {
            "metadata": {"uid": name + "-service"},
            "spec": {"selector": {"app": name}, "ports": [{"port": 8080}]},
        }
        sets.append(
            {
                "metadata": {
                    "uid": name + "-rs",
                    "ownerReferences": [
                        {
                            "kind": "Deployment",
                            "controller": True,
                            "uid": name + "-deployment",
                        }
                    ],
                }
            }
        )
        pod = {
            "metadata": {
                "name": name + "-pod",
                "uid": name + "-pod-id",
                "ownerReferences": [
                    {"kind": "ReplicaSet", "controller": True, "uid": name + "-rs"}
                ],
            },
            "spec": copy.deepcopy(spec),
            "status": {"conditions": [{"type": "Ready", "status": "True"}]},
        }
        if role.get("initializer"):
            pod["status"]["initContainerStatuses"] = [
                {"name": "warmer", "state": {"terminated": {"exitCode": 0}}}
            ]
        pods.append(pod)
    docs["configmap/source"] = {
        "metadata": {"uid": "source-id"},
        "data": copy.deepcopy(policy),
    }
    identities = {key: value["metadata"]["uid"] for key, value in docs.items()}
    facts = {
        "contract": contract,
        "identities": identities,
        "image": image,
        "policy": policy,
        "publication": publication,
    }
    if variant == "uid":
        docs["service/reader"]["metadata"]["uid"] = "replacement"
    if variant == "source":
        docs["configmap/source"]["data"]["CACHE_MIB"] = "1"
    if variant == "image":
        docs["deployment/reader"]["spec"]["template"]["spec"]["containers"][0][
            "image"
        ] = "app@sha256:replacement"
    if variant == "image-alias":
        for doc in docs.values():
            for c in (
                doc.get("spec", {})
                .get("template", {})
                .get("spec", {})
                .get("containers", [])
            ):
                c["image"] = "alias@sha256:original"
        for pod in pods:
            pod["spec"]["containers"][0]["image"] = "alias@sha256:original"
    if variant in [
        "over-budget",
        "missing-limit",
        "boolean-limit",
        "valid-quantity",
        "phase-budget",
        "sidecar-over",
        "restartable-over",
        "pod-level",
    ]:
        spec = docs["deployment/reader"]["spec"]["template"]["spec"]
        if variant == "over-budget":
            spec["containers"][0]["resources"]["limits"]["memory"] = "128Mi"
        if variant == "missing-limit":
            spec["containers"][0]["resources"] = {}
        if variant == "boolean-limit":
            spec["containers"][0]["resources"]["limits"]["memory"] = True
        if variant == "valid-quantity":
            spec["containers"][0]["resources"]["limits"]["memory"] = "98304Ki"
        if variant == "phase-budget":
            spec["containers"][0]["resources"]["limits"]["memory"] = "80Mi"
            spec["initContainers"] = [worker("prepare", "90Mi")]
        if variant == "sidecar-over":
            spec["containers"].append(worker("sidecar", "16Mi"))
        if variant == "restartable-over":
            spec["initContainers"] = [
                dict(worker("sidecar", "16Mi"), restartPolicy="Always")
            ]
        if variant == "pod-level":
            spec["resources"] = {"limits": {"memory": "96Mi"}}
            spec["containers"][0]["resources"] = {}
    if variant == "missing-init":
        docs["deployment/stager"]["spec"]["template"]["spec"].pop("initContainers")
    if variant == "init-image":
        docs["deployment/stager"]["spec"]["template"]["spec"]["initContainers"][0][
            "image"
        ] = "app@sha256:replacement"
    if variant == "pod-over-budget":
        pods[2]["spec"]["containers"][0]["resources"]["limits"]["memory"] = "128Mi"
    if variant == "unready":
        pods[1]["status"]["conditions"][0]["status"] = "False"
    if variant == "foreign-owner":
        sets[1]["metadata"]["ownerReferences"][0]["uid"] = "foreign"
    if variant == "deleted":
        pods[1]["metadata"]["deletionTimestamp"] = "now"
    if variant == "unfinished-init":
        pods[1]["status"]["initContainerStatuses"][0]["state"] = {"running": {}}
    if variant == "service-selector":
        docs["service/reader"]["spec"]["selector"] = {"app": "foreign"}
    if variant == "service-port":
        docs["service/reader"]["spec"]["ports"][0]["port"] = 9090

    def cli(argv, **kwargs):
        if argv[:3] == ["kubectl", "get", "pods"]:
            value = json.dumps({"items": pods})
        elif argv[:3] == ["kubectl", "get", "replicasets"]:
            value = json.dumps({"items": sets})
        elif argv[:2] == ["kubectl", "get"]:
            value = json.dumps(docs[argv[2] + "/" + argv[3]])
        elif argv[:2] == ["kubectl", "rollout"]:
            value = ""
        elif "stat" in argv:
            if "-f" in argv:
                value = "ext4" if variant == "disk" else "tmpfs"
            elif "%s" in argv:
                value = str(
                    publication["bytes"] - 1
                    if variant == "size"
                    else publication["bytes"]
                )
            else:
                value = "0" if variant == "sparse" else str(publication["bytes"] // 512)
        elif "sha256sum" in argv:
            value = (
                "wrong" if variant == "checksum" else publication["sha256"]
            ) + "  /cache/payload"
        else:
            assert "-c" in argv and argv[argv.index("-c") + 1] == "worker"
            result = dict(publication)
            if variant == "record":
                result["cache_id"] = "stale"
            if variant == "extra-record-field":
                result["debug"] = "allowed"
            value = json.dumps(result)
        return SimpleNamespace(returncode=int(variant == "cli-failed"), stdout=value)

    return execute_python(
        monkeypatch, code, "/run/dq/facts/0/startup-identities.json", facts, cli
    )


@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "image-alias",
        "uid",
        "source",
        "image",
        "over-budget",
        "missing-limit",
        "boolean-limit",
        "valid-quantity",
        "phase-budget",
        "sidecar-over",
        "restartable-over",
        "pod-level",
        "missing-init",
        "init-image",
        "cli-failed",
    ],
)
def test_startup_identity_and_phase_memory_envelope(monkeypatch, variant):
    expected = variant in [
        "reference",
        "image-alias",
        "valid-quantity",
        "phase-budget",
        "pod-level",
    ]
    assert memory_probe(
        monkeypatch, 0, variant, program(88, 0, "DQ_MEMORY_BUDGET")
    ) == (0 if expected else 1)


@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "image-alias",
        "extra-record-field",
        "pod-over-budget",
        "unready",
        "foreign-owner",
        "deleted",
        "unfinished-init",
        "service-selector",
        "service-port",
        "disk",
        "size",
        "sparse",
        "checksum",
        "record",
        "cli-failed",
    ],
)
def test_actual_allocated_startup_payload_and_published_dataset(monkeypatch, variant):
    expected = variant in ["reference", "image-alias", "extra-record-field"]
    assert memory_probe(monkeypatch, 1, variant, program(88, 1, "DQ_MEMORY_DATA")) == (
        0 if expected else 1
    )


def performance_probe(monkeypatch, index, variant, code):
    consumers = [
        {"deployment": n, "service": n, "replicas": 1} for n in ["scan-a", "scan-b"]
    ]
    contract = {
        "producer": {"deployment": "board", "response": "north-94"},
        "consumers": consumers,
        "policyConfigMap": "policy",
        "servicePort": 8080,
        "progressPath": "/progress.json",
    }
    policy = {"POLL_DELAY": "1", "POLICY_ID": "current"}
    image = "app@sha256:original"
    docs = {}
    for name in ["board", "scan-a", "scan-b"]:
        docs["deployment/" + name] = {
            "metadata": {"uid": name + "-deployment"},
            "spec": {
                "replicas": 1,
                "template": {
                    "metadata": {"labels": {"app": name}},
                    "spec": {"containers": [{"name": "worker", "image": image}]},
                },
            },
            "status": {"readyReplicas": 1},
        }
        docs["service/" + name] = {
            "metadata": {"uid": name + "-service"},
            "spec": {"selector": {"app": name}, "ports": [{"port": 8080}]},
        }
    docs["configmap/policy"] = {
        "metadata": {"uid": "policy-id"},
        "data": copy.deepcopy(policy),
    }
    facts = {
        "contract": contract,
        "policy": policy,
        "image": image,
        "identities": {key: doc["metadata"]["uid"] for key, doc in docs.items()},
    }
    if variant == "uid":
        docs["service/scan-b"]["metadata"]["uid"] = "replacement"
    if variant == "policy":
        docs["configmap/policy"]["data"]["POLL_DELAY"] = "0"
    if variant == "image":
        docs["deployment/scan-a"]["spec"]["template"]["spec"]["containers"][0][
            "image"
        ] = "app@sha256:replacement"
    if variant == "image-alias":
        for name in ["board", "scan-a", "scan-b"]:
            docs["deployment/" + name]["spec"]["template"]["spec"]["containers"][0][
                "image"
            ] = "alias@sha256:original"
    if variant == "replicas":
        docs["deployment/scan-b"]["spec"]["replicas"] = 0
    if variant == "unready":
        docs["deployment/scan-b"]["status"]["readyReplicas"] = 0
    if variant == "selector":
        docs["service/scan-b"]["spec"]["selector"] = {"app": "foreign"}
    reads = {n: 0 for n in ["scan-a", "scan-b"]}

    def cli(argv, **kwargs):
        if argv[:2] == ["kubectl", "get"]:
            value = json.dumps(docs[argv[2] + "/" + argv[3]])
        elif argv[:2] == ["kubectl", "rollout"]:
            value = ""
        elif "printenv" in argv:
            value = (
                "current"
                if argv[-1] == "POLICY_ID"
                else (
                    "0"
                    if variant == "old-input"
                    else "1.0"
                    if variant == "decimal-cadence"
                    else "1"
                )
            )
        else:
            name = argv[2].removeprefix("deployment/")
            assert (
                name in reads
                and "-c" in argv
                and argv[argv.index("-c") + 1] == "worker"
            )
            reads[name] += 1
            sequence = (
                10 if variant == "frozen" and name == "scan-b" else 10 + reads[name]
            )
            if variant == "boolean-sequence":
                sequence = True
            result = {
                "sequence": sequence,
                "route": "wrong" if variant == "route" else "north-94",
                "policy_id": "old" if variant == "record-policy" else "current",
                "delay": "0"
                if variant == "record-delay"
                else "1.0"
                if variant == "decimal-cadence"
                else "1",
            }
            value = json.dumps(result)
        return SimpleNamespace(returncode=int(variant == "cli-failed"), stdout=value)

    return execute_python(
        monkeypatch, code, "/run/dq/facts/0/performance-identities.json", facts, cli
    )


@pytest.mark.parametrize(
    "variant", ["reference", "image-alias", "uid", "policy", "image", "cli-failed"]
)
def test_retained_capacity_resources_and_source(monkeypatch, variant):
    assert performance_probe(
        monkeypatch, 3, variant, program(94, 3, "DQ_PERFORMANCE")
    ) == (0 if variant in ["reference", "image-alias"] else 1)


@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "decimal-cadence",
        "replicas",
        "unready",
        "selector",
        "old-input",
        "frozen",
        "boolean-sequence",
        "route",
        "record-policy",
        "record-delay",
        "cli-failed",
    ],
)
def test_active_consumer_inputs_and_progress(monkeypatch, variant):
    assert performance_probe(
        monkeypatch, 5, variant, program(94, 5, "DQ_PERFORMANCE")
    ) == (0 if variant in ["reference", "decimal-cadence"] else 1)


@pytest.mark.parametrize("index", [3, 5])
@pytest.mark.parametrize(
    "value,exit_code", [("0", 1), ("5", 1), ("6", 0), ("-1", 0), ("malformed", 0)]
)
def test_original_failed_numeric_sampler_is_not_masked_by_wrapper(
    tmp_path, index, value, exit_code
):
    tool = tmp_path / "kubectl"
    tool.write_text(
        "#!/bin/bash\ncase \" $* \" in *' sh -c '*) printf '%s\\n' \"$DQ_TEST_SAMPLE\";exit \"$DQ_TEST_EXIT\";; *' wget '*) printf 'north-94\\n';; *) exit 9;; esac\n"
    )
    tool.chmod(0o755)
    (tmp_path / "measure.sh").write_text(
        "printf '%s\\n' " + shlex.quote(value) + "\nexit " + str(exit_code) + "\n"
    )
    legacy = (
        (ROOT / "tests/fixtures/deepen-performance/094-legacy-check.sh")
        .read_text()
        .split("(\nset -e\n")[index + 1]
        .split("\n)\n[ $? -eq 0 ] || failed=1\n", 1)[0]
    )
    env = {
        **os.environ,
        "PATH": str(tmp_path) + os.pathsep + os.environ["PATH"],
        "DQ_TEST_SAMPLE": value,
        "DQ_TEST_EXIT": str(exit_code),
    }
    before = subprocess.run(
        ["bash", "-euo", "pipefail", "-c", legacy],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert before.returncode != 0
    after = subprocess.run(
        ["bash", "-euo", "pipefail", "-c", objective(94, index)],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert after.returncode != 0 and "[DQ:performance_sample]" in after.stdout


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Explicit local sandbox opt-in required",
)
@pytest.mark.parametrize("number", [88, 94])
def test_native_resource_runtime_shortcuts(number):
    catalog, runtime = Catalog(), Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": number}
    folder = Path(
        os.environ.get("DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/resource-runtime")
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

    def patch(name, changes):
        value = {
            "spec": {
                "template": {"spec": {"containers": [{"name": "worker", **changes}]}}
            }
        }
        execute(
            "kubectl patch deployment "
            + name
            + " --type=strategic -p "
            + shlex.quote(json.dumps(value))
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
        kind = "deepen-startup-memory" if number == 88 else "deepen-performance"
        legacy = (
            ROOT / f"tests/fixtures/{kind}/{number:03}-legacy-check.sh"
        ).read_text()
        if number == 94:
            worksheet = (
                ROOT / "tests/fixtures/deepen-performance/094-measure.sh"
            ).read_text()
            execute("cat > measure.sh <<'WORKSHEET'\n" + worksheet + "WORKSHEET")
        execute((ROOT / f"tests/fixtures/{kind}/{number:03}.sh").read_text())
        if number == 88:
            execute(legacy)
            assert (
                "[DQ:startup_payload"
                in execute(catalog.script(number, 0, "check"), 1).stdout
            )
            log["old_whole_quest"] = (
                "PASS; current startup data/other phases remain unmet"
            )
        else:
            assert int(execute("bash measure.sh").stdout.strip()) > 5
            execute(legacy, 1)
            assert (
                "[DQ:performance_sample]"
                in execute(catalog.script(number, 0, "check"), 1).stdout
            )
            log["stronger_old_fix_plus_original_worksheet"] = (
                "FAIL from actual demand pressure, not merely absent worksheet"
            )
        execute((ROOT / f"solutions/{number:03}/0.sh").read_text())
        execute(catalog.script(number, 0, "check"))
        if number == 88:
            execute(
                'kubectl patch deployment stager --type=json -p \'[{"op":"replace","path":"/spec/template/spec/initContainers/0/resources/limits/memory","value":"128Mi"}]\'\nkubectl rollout status deployment/stager --timeout=90s'
            )
            execute(legacy)
            assert (
                "[DQ:startup_budget]"
                in execute(catalog.script(number, 0, "check"), 1).stdout
            )
            execute(
                'kubectl patch deployment stager --type=json -p \'[{"op":"replace","path":"/spec/template/spec/initContainers/0/resources/limits/memory","value":"90Mi"}]\'\nkubectl rollout status deployment/stager --timeout=90s'
            )
            execute(catalog.script(number, 0, "check"))
            execute(
                "kubectl exec deployment/relay -c worker -- sh -c ': > /cache/payload; truncate -s 83886080 /cache/payload'"
            )
            execute(legacy)
            assert (
                "[DQ:startup_payload_relay]"
                in execute(catalog.script(number, 0, "check"), 1).stdout
            )
            log["sparse_zero_hash_is_not_allocated_RAM"] = "PASS rejection"
        else:
            execute(
                "kubectl set env deployment/scan-a POLL_DELAY=1.0\nkubectl rollout status deployment/scan-a --timeout=90s"
            )
            execute(catalog.script(number, 0, "check"))
            log["decimal_cadence_equivalence"] = "PASS"
            original = json.loads(
                execute("kubectl get deployment scan-b -o json").stdout
            )["spec"]["template"]["spec"]["containers"][0]["command"]
            record = json.loads(
                execute(
                    "kubectl exec deployment/scan-b -c worker -- wget -qO- -T 3 http://127.0.0.1:8080/progress.json"
                ).stdout
            )
            frozen = (
                "mkdir -p /tmp/progress; printf %s "
                + shlex.quote(json.dumps(record))
                + " > /tmp/progress/progress.json; exec httpd -f -p 8080 -h /tmp/progress"
            )
            patch("scan-b", {"command": ["sh", "-c", frozen]})
            execute(legacy)
            assert (
                "[DQ:performance_progress_scan_b]"
                in execute(catalog.script(number, 0, "check"), 1).stdout
            )
            patch("scan-b", {"command": original})
            execute((ROOT / "solutions/094/0.sh").read_text())
            execute(catalog.script(number, 0, "check"))
            execute("printf 'printf 0\\nexit 1\\n' > measure.sh")
            execute(legacy, 1)
            assert (
                "[DQ:performance_sample]"
                in execute(catalog.script(number, 0, "check"), 1).stdout
            )
            log["nonzero_numeric_worksheet_and_frozen_consumer"] = "PASS rejection"
        log["result"] = "PASS"
    finally:
        try:
            runtime.teardown(run)
            log["teardown"] = "PASS"
        finally:
            (folder / f"{number:03}-shortcuts.json").write_text(
                json.dumps(log, indent=2) + "\n"
            )
