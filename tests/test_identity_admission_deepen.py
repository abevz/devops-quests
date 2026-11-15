"""Real policy/identity/ownership boundaries for 111/112/125/126."""

import base64
import copy
import hashlib
import io
import json
import os
import secrets
import shlex
import ssl
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime

IMAGE = "registry/app@sha256:" + "a" * 64
OTHER = "registry/app@sha256:" + "b" * 64
HASH = hashlib.sha256(b"handler\n").hexdigest()
MARKERS = {
    (111, 3): "DQ_DISCOVERY_CONSUMER",
    (112, 0): "DQ_LOAD_INPUTS",
    (112, 2): "DQ_LOAD_DEMAND",
    (125, 0): "DQ_AUTHORITY_POLICY",
    (125, 2): "DQ_AUTHORITY_REQUESTS",
    (126, 1): "DQ_ADMISSION_POLICY",
    (126, 2): "DQ_ADMISSION_CONSUMERS",
}
FACT_FILES = {111: "discovery", 112: "autoscaling", 125: "authority", 126: "admission"}


def program(number, index):
    source = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())
    check = source["stages"][0]["objectives"][index]["check"]
    marker = MARKERS[number, index]
    return check.split("<<'" + marker + "'\n", 1)[1].split("\n" + marker, 1)[0]


def deployment(name, account=None, replicas=1):
    spec = {
        "containers": [{"name": "worker", "image": IMAGE, "resources": {}}],
        "automountServiceAccountToken": False,
    }
    if account:
        spec["serviceAccountName"] = account
    return {
        "metadata": {"name": name, "uid": name + "-uid", "generation": 2},
        "spec": {"replicas": replicas, "template": {"spec": spec}},
        "status": {"readyReplicas": replicas, "observedGeneration": 2},
    }


def owned_state(workloads):
    sets, pods = [], []
    for document in workloads:
        name = document["metadata"]["name"]
        sets.append(
            {
                "metadata": {
                    "uid": name + "-rs",
                    "ownerReferences": [
                        {
                            "kind": "Deployment",
                            "uid": document["metadata"]["uid"],
                            "controller": True,
                        }
                    ],
                }
            }
        )
        for index in range(document["spec"]["replicas"]):
            pods.append(
                {
                    "metadata": {
                        "name": name + "-" + str(index),
                        "uid": name + "-pod-" + str(index),
                        "ownerReferences": [
                            {
                                "kind": "ReplicaSet",
                                "uid": name + "-rs",
                                "controller": True,
                            }
                        ],
                    },
                    "spec": copy.deepcopy(document["spec"]["template"]["spec"]),
                    "status": {
                        "phase": "Running",
                        "containerStatuses": [
                            {"name": "worker", "ready": True, "state": {"running": {}}}
                        ],
                    },
                }
            )
    return {"items": sets}, {"items": pods}


def state(number):
    docs = {}
    if number == 111:
        consumer = deployment("inspector")
        sets, pods = owned_state([consumer])
        facts = {
            "contract": {
                "consumer": "inspector",
                "container": "worker",
                "port": 8080,
                "response": "ledger-111",
            },
            "source": {"pod": "shelf-0", "service": "shelf", "claim": "original"},
            "image": IMAGE,
        }
        docs = {"deployment/inspector": consumer, "replicasets/": sets, "pods/": pods}
    elif number == 112:
        server, client = deployment("board", replicas=2), deployment("client")
        sets, pods = owned_state([server])
        facts = {
            "contract": {
                "server": "board",
                "client": "client",
                "hpa": "board",
                "replicas": {"max": 2},
                "handler": {
                    "configMap": "work-handler",
                    "key": "process",
                    "path": "/tmp/handler",
                    "progress": "/tmp/completed",
                },
            },
            "images": {"board": IMAGE, "client": IMAGE},
            "handlerSHA256": HASH,
            "identities": {
                "deployment/board": "board-uid",
                "deployment/client": "client-uid",
                "hpa/board": "hpa-uid",
                "configmap/work-handler": "handler-uid",
            },
        }
        docs = {
            "deployment/board": server,
            "deployment/client": client,
            "configmap/work-handler": {
                "metadata": {"uid": "handler-uid"},
                "data": {"process": "handler\n"},
            },
            "hpa/board": {
                "metadata": {"uid": "hpa-uid"},
                "spec": {
                    "scaleTargetRef": {
                        "apiVersion": "apps/v1",
                        "kind": "Deployment",
                        "name": "board",
                    }
                },
            },
            "replicasets/": sets,
            "pods/": pods,
        }
    elif number == 126:
        client, server = deployment("client"), deployment("board")
        sets, pods = owned_state([client])
        budget = {
            "requests": {"cpu": "100m", "memory": "16Mi"},
            "limits": {"cpu": "200m", "memory": "32Mi"},
        }
        pods["items"][0]["spec"]["containers"][0]["resources"] = copy.deepcopy(budget)
        used = {
            "requests.cpu": "200m",
            "limits.cpu": "400m",
            "requests.memory": "32Mi",
            "limits.memory": "64Mi",
            "pods": "2",
        }
        facts = {
            "contract": {
                "quota": "station",
                "workloads": ["client", "board"],
                "replicas": 1,
                "admitted": budget,
            },
            "identities": {
                "resourcequota/station": "quota-uid",
                "deployment/client": "client-uid",
                "deployment/board": "board-uid",
            },
            "images": {"client": IMAGE, "board": IMAGE},
        }
        docs = {
            "deployment/client": client,
            "deployment/board": server,
            "resourcequota/station": {
                "metadata": {"uid": "quota-uid"},
                "status": {"used": used},
            },
            "replicasets/": sets,
            "pods/": pods,
        }
    else:
        consumers = [
            {
                "deployment": "publisher",
                "configMap": "release-plan",
                "key": "route",
                "response": "release-public",
            },
            {
                "deployment": "sampler",
                "configMap": "sampling",
                "key": "route",
                "response": "sample-public",
            },
        ]
        workloads = [
            deployment(name, account)
            for name, account in [
                ("controller", "controller"),
                ("observer", "observer"),
                ("publisher", "publisher-access"),
                ("sampler", "sampler-access"),
            ]
        ]
        accounts = [
            {"metadata": {"name": name, "uid": name + "-uid"}}
            for name in ("controller", "observer", "publisher-access", "sampler-access")
        ]
        roles, bindings = [], []
        for item in consumers:
            account = item["deployment"] + "-access"
            roles.append(
                {
                    "metadata": {"name": account},
                    "rules": [
                        {
                            "apiGroups": [""],
                            "resources": ["configmaps"],
                            "resourceNames": [item["configMap"]],
                            "verbs": ["get"],
                        }
                    ],
                }
            )
            bindings.append(
                {
                    "subjects": [
                        {
                            "kind": "ServiceAccount",
                            "name": account,
                            "namespace": "synthetic",
                        }
                    ],
                    "roleRef": {"kind": "Role", "name": account},
                }
            )
        sets, pods = owned_state(workloads)
        facts = {
            "contract": {
                "control": {"deployment": "controller"},
                "observer": {"deployment": "observer"},
                "consumers": consumers,
                "credential": {"container": "worker", "path": "/credential/token"},
                "reservedServiceAccounts": [
                    "controller",
                    "observer",
                    "player",
                    "default",
                ],
            },
            "identities": {
                "deployment/" + v["metadata"]["name"]: v["metadata"]["uid"]
                for v in workloads
            },
            "images": {v["metadata"]["name"]: IMAGE for v in workloads},
            "originalAccounts": {"controller": "controller", "observer": "observer"},
        }
        facts["identities"].update(
            {
                "serviceaccount/" + name: name + "-uid"
                for name in ("controller", "observer")
            }
        )
        docs = {
            "deployments/": {"items": workloads},
            "serviceaccounts/": {"items": accounts},
            "roles/": {"items": roles},
            "rolebindings/": {"items": bindings},
            "replicasets/": sets,
            "pods/": pods,
        }
    return facts, docs


def execute_probe(monkeypatch, number, index, variant):
    code = program(number, index)
    facts, docs = state(number)
    pod = docs["pods/"]["items"][0]
    if variant == "wrong-owner":
        pod["metadata"]["ownerReferences"][0]["uid"] = "unrelated"
    elif variant == "not-ready":
        pod["status"]["containerStatuses"][0]["ready"] = False
    elif variant == "wrong-image":
        pod["spec"]["containers"][0]["image"] = OTHER
    elif variant == "extra-unrelated":
        extra = copy.deepcopy(pod)
        extra["metadata"]["ownerReferences"][0]["uid"] = "unrelated"
        docs["pods/"]["items"].append(extra)
    elif variant == "retiring-old":
        extra = copy.deepcopy(pod)
        extra["metadata"]["deletionTimestamp"] = "now"
        extra["spec"]["containers"][0]["image"] = OTHER
        docs["pods/"]["items"].append(extra)
    elif variant == "wrong-identity":
        key = "deployment/inspector" if number == 111 else "deployment/client"
        if number == 125:
            docs["deployments/"]["items"][0]["metadata"]["uid"] = "replacement"
        else:
            docs[key]["metadata"]["uid"] = "replacement"
    if number == 111:
        if variant == "direct-volume":
            pod["spec"]["volumes"] = [
                {"name": "data", "persistentVolumeClaim": {"claimName": "original"}}
            ]
            pod["spec"]["containers"][0]["volumeMounts"] = [
                {"name": "data", "mountPath": "/other"}
            ]
        elif variant == "init-volume":
            pod["spec"]["volumes"] = [
                {"name": "data", "persistentVolumeClaim": {"claimName": "original"}}
            ]
            pod["spec"]["initContainers"] = [
                {
                    "name": "copy",
                    "volumeMounts": [{"name": "data", "mountPath": "/data"}],
                }
            ]
        elif variant == "unrelated-volume":
            pod["spec"]["volumes"] = [
                {"name": "scratch", "persistentVolumeClaim": {"claimName": "other"}}
            ]
            pod["spec"]["containers"][0]["volumeMounts"] = [
                {"name": "scratch", "mountPath": "/scratch"}
            ]
    elif number == 112:
        if variant == "wrong-template-image":
            docs["deployment/client"]["spec"]["template"]["spec"]["containers"][0][
                "image"
            ] = OTHER
        elif variant == "changed-provider":
            docs["configmap/work-handler"]["data"]["process"] = "different"
        elif variant == "replaced-provider":
            docs["configmap/work-handler"]["metadata"]["uid"] = "replacement"
        elif variant == "wrong-target":
            docs["hpa/board"]["spec"]["scaleTargetRef"]["name"] = "retired"
        elif variant == "replaced-hpa":
            docs["hpa/board"]["metadata"]["uid"] = "replacement"
    elif number == 126:
        if variant == "explicit-budget":
            docs["deployment/client"]["spec"]["template"]["spec"]["containers"][0][
                "resources"
            ] = {"requests": {"cpu": "150m"}}
        elif variant == "wrong-admitted":
            pod["spec"]["containers"][0]["resources"]["requests"]["cpu"] = "150m"
        elif variant == "wrong-memory":
            pod["spec"]["containers"][0]["resources"]["requests"]["memory"] = "8Mi"
        elif variant == "stale-generation":
            docs["deployment/client"]["status"]["observedGeneration"] = 1
        elif variant == "replaced-quota":
            docs["resourcequota/station"]["metadata"]["uid"] = "replacement"
        elif variant == "wrong-usage":
            docs["resourcequota/station"]["status"]["used"]["requests.cpu"] = "250m"
        elif variant == "equivalent-quantity":
            pod["spec"]["containers"][0]["resources"]["requests"]["cpu"] = "1e-1"
    else:
        actor = docs["deployments/"]["items"][2]
        if variant == "shared-identity":
            actor["spec"]["template"]["spec"]["serviceAccountName"] = "controller"
        elif variant == "automount":
            actor["spec"]["template"]["spec"]["automountServiceAccountToken"] = True
        elif variant == "broad-role":
            docs["roles/"]["items"][0]["rules"][0]["verbs"] = ["*"]
        elif variant == "wrong-record":
            docs["roles/"]["items"][0]["rules"][0]["resourceNames"] = ["route"]
        elif variant == "cluster-role":
            docs["rolebindings/"]["items"][0]["roleRef"]["kind"] = "ClusterRole"
        elif variant == "group-grant":
            docs["rolebindings/"]["items"][0]["subjects"] = [
                {"kind": "Group", "name": "system:serviceaccounts"}
            ]
        elif variant == "equivalent-user":
            docs["rolebindings/"]["items"][0]["subjects"] = [
                {
                    "kind": "User",
                    "name": "system:serviceaccount:synthetic:publisher-access",
                }
            ]
        elif variant == "duplicate-rule":
            docs["roles/"]["items"][0]["rules"] *= 2
        elif variant == "unrelated-grant":
            docs["rolebindings/"]["items"].append(
                {
                    "subjects": [{"kind": "ServiceAccount", "name": "elsewhere"}],
                    "roleRef": {"kind": "ClusterRole", "name": "admin"},
                }
            )
    elapsed = [0.0]
    real_read = Path.read_text
    budget = 12 if (number, index) == (112, 2) else 10

    def read(path, *args, **kwargs):
        if str(path).endswith(FACT_FILES[number] + "-identities.json"):
            return json.dumps(facts)
        if str(path) == "/run/dq/facts/0/api-endpoint":
            return "https://fixture.invalid"
        return real_read(path, *args, **kwargs)

    def cli(args, **kwargs):
        delay = 1 if variant == "moderate-api" else 6 if variant == "slow-api" else 0
        allowed = kwargs["timeout"]
        elapsed[0] += min(delay, allowed)
        if delay > allowed:
            raise subprocess.TimeoutExpired(args, allowed)
        if variant == "api-error":
            return SimpleNamespace(returncode=1, stdout="", stderr="unavailable")
        if args[1] == "get":
            name = args[3] if args[3] != "-o" else ""
            value = docs[args[2] + "/" + name]
            return SimpleNamespace(returncode=0, stdout=json.dumps(value), stderr="")
        command_index = args.index("--") + 1
        if number == 111:
            tool = args[command_index]
            if tool == "nslookup":
                return SimpleNamespace(
                    returncode=int(variant == "dns-error"), stdout="A record", stderr=""
                )
            value = "ledger-111\n"
            if variant == "wrong-source" and "127.0.0.1" not in args[-1]:
                value = "wrong\n"
            if variant == "wrong-publication" and "127.0.0.1" in args[-1]:
                value = "wrong\n"
            return SimpleNamespace(returncode=0, stdout=value, stderr="")
        if number == 112:
            first = "sha256sum" in args[-1]
            checksum = "0" * 64 if variant == "wrong-handler-file" else HASH
            count = 1 if first or variant == "stalled-work" else 3
            if variant == "counter-reset" and not first:
                count = 0
            value = (
                checksum + "  handler\n" + str(count) + "\n"
                if first
                else str(count) + "\n"
            )
            return SimpleNamespace(returncode=0, stdout=value, stderr="")
        name = args[3]
        selected = next(
            p for p in docs["pods/"]["items"] if p["metadata"]["name"] == name
        )
        account = selected["spec"].get("serviceAccountName", "default")
        claims = {
            "sub": "system:serviceaccount:synthetic:" + account,
            "kubernetes.io": {"pod": {"uid": selected["metadata"]["uid"]}},
        }
        if variant == "wrong-bound-pod":
            claims["kubernetes.io"]["pod"]["uid"] = "retired"
        payload = (
            base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip("=")
        )
        return SimpleNamespace(
            returncode=0, stdout="header." + payload + ".signature", stderr=""
        )

    class Response(io.StringIO):
        status = 200

    def http(request, **kwargs):
        token = request.get_header("Authorization").split()[1]
        claims = json.loads(base64.urlsafe_b64decode(token.split(".")[1] + "==="))
        principal = claims["sub"].rsplit(":", 1)[1]
        path = request.full_url.split("/namespaces/synthetic/", 1)[1]
        allowed = {
            "controller": ("configmaps/route", "north-125"),
            "publisher-access": ("configmaps/release-plan", "release-public"),
            "sampler-access": ("configmaps/sampling", "sample-public"),
        }
        expected = allowed.get(principal)
        if expected and path == expected[0]:
            value = "wrong" if variant == "wrong-response" else expected[1]
            return Response(json.dumps({"data": {"route": value}}))
        if (
            variant == "extra-permission"
            and principal == "publisher-access"
            and path == "secrets"
        ):
            return Response(json.dumps({"data": {"password": "NEVER_PRINT_SECRET"}}))
        raise urllib.error.HTTPError(
            request.full_url, 403, "Forbidden", {}, io.BytesIO(b"private")
        )

    monkeypatch.setenv("DQ_NAMESPACE", "synthetic")
    monkeypatch.setattr(Path, "read_text", read)
    monkeypatch.setattr(subprocess, "run", cli)
    monkeypatch.setattr(ssl, "create_default_context", lambda **kwargs: object())
    monkeypatch.setattr(urllib.request, "urlopen", http)
    with monkeypatch.context() as clock:
        clock.setattr(time, "monotonic", lambda: elapsed[0])
        clock.setattr(
            time, "sleep", lambda seconds: elapsed.__setitem__(0, elapsed[0] + seconds)
        )
        try:
            exec(compile(code, "shipped-identity-admission", "exec"), {})
        except SystemExit as result:
            assert elapsed[0] <= budget
            return result.code or 0
    return 0


CASES = [
    (
        111,
        3,
        [
            "valid",
            "extra-unrelated",
            "retiring-old",
            "unrelated-volume",
            "moderate-api",
        ],
        [
            "wrong-owner",
            "not-ready",
            "wrong-image",
            "direct-volume",
            "init-volume",
            "dns-error",
            "wrong-source",
            "wrong-publication",
            "slow-api",
            "api-error",
        ],
    ),
    (
        112,
        0,
        ["valid", "moderate-api"],
        [
            "wrong-identity",
            "wrong-template-image",
            "changed-provider",
            "replaced-provider",
            "slow-api",
            "api-error",
        ],
    ),
    (
        112,
        2,
        ["valid", "extra-unrelated", "retiring-old", "moderate-api"],
        [
            "wrong-owner",
            "not-ready",
            "wrong-image",
            "wrong-target",
            "replaced-hpa",
            "wrong-handler-file",
            "stalled-work",
            "counter-reset",
            "slow-api",
            "api-error",
        ],
    ),
    (
        125,
        0,
        [
            "valid",
            "equivalent-user",
            "duplicate-rule",
            "unrelated-grant",
            "moderate-api",
        ],
        [
            "wrong-identity",
            "shared-identity",
            "automount",
            "broad-role",
            "wrong-record",
            "cluster-role",
            "group-grant",
            "slow-api",
            "api-error",
        ],
    ),
    (
        125,
        2,
        ["valid", "extra-unrelated", "retiring-old", "moderate-api"],
        [
            "wrong-owner",
            "not-ready",
            "wrong-image",
            "wrong-bound-pod",
            "wrong-response",
            "extra-permission",
            "slow-api",
            "api-error",
        ],
    ),
    (
        126,
        1,
        ["valid", "moderate-api"],
        [
            "wrong-identity",
            "explicit-budget",
            "replaced-quota",
            "slow-api",
            "api-error",
        ],
    ),
    (
        126,
        2,
        [
            "valid",
            "extra-unrelated",
            "retiring-old",
            "equivalent-quantity",
            "moderate-api",
        ],
        [
            "wrong-owner",
            "not-ready",
            "wrong-image",
            "wrong-admitted",
            "wrong-memory",
            "stale-generation",
            "wrong-usage",
            "slow-api",
            "api-error",
        ],
    ),
]


@pytest.mark.parametrize(
    "number,index,variant,accepted",
    [
        (number, index, variant, accepted)
        for number, index, positive, negative in CASES
        for accepted, variants in ((True, positive), (False, negative))
        for variant in variants
    ],
)
def test_identity_admission_boundaries(
    monkeypatch, capsys, number, index, variant, accepted
):
    assert (execute_probe(monkeypatch, number, index, variant) == 0) is accepted
    output = capsys.readouterr()
    assert "NEVER_PRINT_SECRET" not in output.out + output.err


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Explicit local sandbox opt-in required",
)
@pytest.mark.parametrize("number", [111, 112, 125, 126])
def test_native_identity_admission_shortcuts(number):
    runtime, catalog = Runtime(ROOT / ".state/runtime"), Catalog()
    run = {"id": secrets.token_hex(12), "level": number}
    folder = Path(
        os.environ.get("DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/identity-admission")
    )
    folder.mkdir(parents=True, exist_ok=True)
    record = {"quest": number, "commands": []}

    def execute(script, expected=0, timeout=240):
        value = runtime.exec(
            run,
            "set -euo pipefail\ncd ~/quest\n" + script,
            check=False,
            timeout=timeout,
        )
        record["commands"].append(
            {
                "script": script,
                "exit": value.returncode,
                "stdout": value.stdout,
                "stderr": value.stderr,
            }
        )
        if expected is not None:
            assert value.returncode == expected, value.stdout + value.stderr
        return value

    try:
        runtime.create(run)
        execute(catalog.script(number, 0, "setup"))
        runtime.capture_facts(
            dict(run, stage=0), catalog.quests[number]["immutable"][0]
        )
        for objective in catalog.quests[number]["stages"][0]["objectives"]:
            if objective.get("keep"):
                execute(objective["check"])
        if number == 125:
            execute("kubectl get rolebinding station-reader -o json > binding.yaml")
        elif number == 126:
            execute("kubectl get limitrange defaults -o json > defaults.yaml")
        legacy = (
            ROOT / f"tests/fixtures/deepen-identity-admission/{number:03}.sh"
        ).read_text()
        if number == 112:
            legacy = legacy.split("for i in $(seq 1 90); do", 1)[0]
            execute(legacy)
        elif number == 126:
            result = execute(legacy.replace("--timeout=90s", "--timeout=8s"), None)
            assert result.returncode != 0
            observed = execute("kubectl get replicasets -l app=board -o json").stdout
            assert "exceeded quota" in observed and "requests.cpu" in observed
        else:
            execute(legacy)
            execute(
                (
                    ROOT
                    / f"tests/fixtures/deepen-identity-admission/{number:03}-legacy-check.sh"
                ).read_text()
            )
        execute(catalog.script(number, 0, "check"), 1)
        record["old_minimum"] = (
            "Executed actual repair actions; rejected by current workflow"
        )
        execute((ROOT / f"solutions/{number:03}/0.sh").read_text())
        execute(catalog.script(number, 0, "check"))
        if number == 125:
            account = execute(
                "kubectl get deployment publisher -o jsonpath='{.spec.template.spec.serviceAccountName}'"
            ).stdout
            execute(
                "kubectl create rolebinding excessive --role=player --serviceaccount="
                + shlex.quote(runtime.namespace(run) + ":" + account)
            )
            execute(catalog.script(number, 0, "check"), 1)
            execute("kubectl delete rolebinding excessive")
        elif number == 126:
            execute(
                "kubectl patch deployment client --type=json -p "
                + shlex.quote(
                    json.dumps(
                        [
                            {
                                "op": "add",
                                "path": "/spec/template/spec/containers/0/resources",
                                "value": {"requests": {"cpu": "150m"}},
                            }
                        ]
                    )
                )
            )
            execute(catalog.quests[number]["stages"][0]["objectives"][1]["check"], 1)
            execute((ROOT / f"solutions/{number:03}/0.sh").read_text())
        execute(catalog.script(number, 0, "check"))
        record["result"] = "PASS"
    finally:
        try:
            runtime.teardown(run)
            record["teardown"] = "PASS"
        finally:
            (folder / f"{number:03}-shortcuts.json").write_text(
                json.dumps(record, indent=2) + "\n"
            )
