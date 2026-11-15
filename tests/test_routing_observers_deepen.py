"""Run shipped network-state and query-consumer probes against real API shapes."""

import base64
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
CODE = "set -eu\nprovided program\n"
HASH = hashlib.sha256(CODE.encode()).hexdigest()
MARKERS = {
    (62, 0): "ISOLATION_MEMBERSHIP",
    (113, 1): "ATTACHMENT_CURRENT",
    (118, 1): "VIP_ENDPOINTS",
    (127, 0): "OBSERVER_INPUTS",
    (127, 1): "OBSERVER_DELIVERY",
}


def program(number, index):
    quest = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())
    marker = "DQ_" + MARKERS[number, index]
    return (
        quest["stages"][0]["objectives"][index]["check"]
        .split("<<'" + marker + "'\n", 1)[1]
        .split("\n" + marker, 1)[0]
    )


def workload(name, role=None):
    labels = {"app": name}
    if role:
        labels["role"] = role
    return {
        "metadata": {"name": name, "uid": name + "-uid"},
        "spec": {
            "replicas": 1,
            "template": {
                "metadata": {"labels": labels},
                "spec": {"containers": [{"name": "worker", "image": IMAGE}]},
            },
        },
    }


def owned(workloads):
    sets, pods = [], []
    for index, document in enumerate(workloads):
        name = document["metadata"]["name"]
        sets.append(
            {
                "metadata": {
                    "name": name + "-rs",
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
        pods.append(
            {
                "metadata": {
                    "name": name + "-pod",
                    "uid": name + "-pod",
                    "labels": copy.deepcopy(
                        document["spec"]["template"]["metadata"]["labels"]
                    ),
                    "ownerReferences": [
                        {"kind": "ReplicaSet", "uid": name + "-rs", "controller": True}
                    ],
                },
                "spec": copy.deepcopy(document["spec"]["template"]["spec"]),
                "status": {
                    "phase": "Running",
                    "podIP": f"10.1.0.{index + 1}",
                    "conditions": [{"type": "Ready", "status": "True"}],
                },
            }
        )
    return {"items": sets}, {"items": pods}


def fixture(number):
    names = ["board", "dispatcher", "visitor"] if number == 62 else ["board", "client"]
    if number == 127:
        names += ["observer-count", "observer-total"]
    workloads = [
        workload(
            name,
            "dispatcher"
            if name == "dispatcher"
            else "guest"
            if name == "visitor"
            else None,
        )
        for name in names
    ]
    docs = {}
    if number == 127:
        intent = {
            "PROMETHEUS_URL": "http://prometheus.synthetic.svc:9090",
            "METRIC": "station_queue_depth",
            "ROUTE": "north",
            "JOB": "board",
        }
        roles = [
            {"deployment": "observer-count", "operation": "count", "expected": 2},
            {"deployment": "observer-total", "operation": "sum", "expected": 7},
        ]
        for role in roles:
            worker = next(
                item
                for item in workloads
                if item["metadata"]["name"] == role["deployment"]
            )["spec"]["template"]["spec"]["containers"][0]
            worker["command"] = ["sh", "/opt/observer/poll.sh"]
            worker["env"] = [
                {"name": key, "value": value}
                for key, value in dict(intent, OPERATION=role["operation"]).items()
            ]
        contract = {
            "consumers": roles,
            "programConfigMap": "observer-program",
            "programKey": "poll.sh",
            "programPath": "/opt/observer/poll.sh",
            "counterPath": "/tmp/observations",
            "snapshotURL": "http://127.0.0.1:8080",
        }
        facts = {
            "contract": contract,
            "intent": intent,
            "serviceUID": "service-uid",
            "metricsUID": "metrics-uid",
            "programUID": "program-uid",
            "programHash": HASH,
        }
        docs["configmaps/"] = {
            "items": [
                {
                    "metadata": {"name": "board-metrics", "uid": "metrics-uid"},
                    "data": {},
                },
                {
                    "metadata": {"name": "observer-program", "uid": "program-uid"},
                    "data": {"poll.sh": CODE},
                },
            ]
        }
    elif number == 62:
        facts = {
            "contract": {"policy": "board-ingress", "permittedCaller": "dispatcher"},
            "policyUID": "policy-uid",
        }
        docs["networkpolicy/board-ingress"] = {
            "metadata": {"uid": "policy-uid"},
            "spec": {
                "ingress": [
                    {"from": [{"podSelector": {"matchLabels": {"role": "dispatcher"}}}]}
                ]
            },
        }
    elif number == 113:
        listeners = [
            {
                "name": "web",
                "protocol": "HTTP",
                "port": 8000,
                "hostname": "north.station.internal",
            }
        ]
        facts = {
            "contract": {
                "gateway": "station",
                "route": "board",
                "backendService": "board",
            },
            "gatewayUID": "gateway-uid",
            "routeUID": "route-uid",
            "serviceUID": "service-uid",
            "listeners": copy.deepcopy(listeners),
            "controller": "traefik.io/gateway-controller",
        }
        docs["gateway/station"] = {
            "metadata": {"uid": "gateway-uid"},
            "spec": {"listeners": listeners},
        }
        docs["httproute/board"] = {
            "metadata": {"uid": "route-uid", "generation": 5},
            "spec": {"parentRefs": [{"name": "station", "sectionName": "web"}]},
            "status": {
                "parents": [
                    {
                        "controllerName": facts["controller"],
                        "parentRef": {"name": "station", "sectionName": "web"},
                        "conditions": [
                            {"type": kind, "status": "True", "observedGeneration": 5}
                            for kind in ("Accepted", "ResolvedRefs")
                        ],
                    }
                ]
            },
        }
    else:
        facts = {
            "contract": {
                "service": "board",
                "protectedWorkload": "board",
                "servicePort": 8080,
                "applicationPort": 8080,
            },
            "serviceUID": "service-uid",
            "vip": "10.96.0.9",
        }
    docs["service/board"] = {
        "metadata": {"uid": "service-uid"},
        "spec": {
            "clusterIP": "10.96.0.9",
            "ports": [
                {"name": "http", "port": 8080, "targetPort": 8080, "protocol": "TCP"}
            ],
        },
    }
    facts["deployments"] = {
        item["metadata"]["name"]: {"uid": item["metadata"]["uid"], "image": IMAGE}
        for item in workloads
    }
    sets, pods = owned(workloads)
    docs.update(
        {"deployments/": {"items": workloads}, "replicasets/": sets, "pods/": pods}
    )
    if number == 118:
        docs["endpointslices/"] = {
            "items": [
                {
                    "metadata": {
                        "name": "board-slice",
                        "labels": {"kubernetes.io/service-name": "board"},
                        "ownerReferences": [
                            {
                                "kind": "Service",
                                "uid": "service-uid",
                                "controller": True,
                            }
                        ],
                    },
                    "ports": [{"name": "http", "port": 8080, "protocol": "TCP"}],
                    "endpoints": [
                        {
                            "addresses": ["10.1.0.1"],
                            "conditions": {"ready": True, "terminating": False},
                            "targetRef": {
                                "kind": "Pod",
                                "uid": "board-pod",
                                "namespace": "synthetic",
                            },
                        }
                    ],
                }
            ]
        }
    return facts, docs


def execute_probe(monkeypatch, number, index, variant):
    code = program(number, index)
    facts, docs = fixture(number)
    deployments = docs["deployments/"]["items"]
    pods = docs["pods/"]["items"]
    selected = next(
        item
        for item in deployments
        if item["metadata"]["name"]
        == (
            "dispatcher"
            if number == 62
            else "observer-count"
            if number == 127
            else "board"
        )
    )
    pod = next(
        item
        for item in pods
        if item["metadata"]["name"] == selected["metadata"]["name"] + "-pod"
    )
    if variant == "wrong-workload-uid":
        selected["metadata"]["uid"] = "recreated"
    elif variant == "wrong-image":
        selected["spec"]["template"]["spec"]["containers"][0]["image"] = OTHER
    elif variant == "wrong-pod-image":
        pod["spec"]["containers"][0]["image"] = OTHER
    elif variant == "digest-alias":
        for item in deployments:
            item["spec"]["template"]["spec"]["containers"][0]["image"] = (
                "alias@" + IMAGE.partition("@")[2]
            )
        for item in pods:
            item["spec"]["containers"][0]["image"] = "alias@" + IMAGE.partition("@")[2]
    elif variant == "not-ready":
        pod["status"]["conditions"][0]["status"] = "False"
    elif variant == "wrong-owner":
        pod["metadata"]["ownerReferences"][0]["uid"] = "foreign"
    elif variant == "terminating-old":
        old = copy.deepcopy(pod)
        old["metadata"]["deletionTimestamp"] = "now"
        old["metadata"]["name"] += "-old"
        old["metadata"]["uid"] += "-old"
        old["spec"]["containers"][0]["image"] = OTHER
        pods.append(old)
    elif variant == "unrelated":
        deployments.append(workload("unrelated"))
        pods.append(
            {
                "metadata": {"name": "unrelated", "uid": "unrelated"},
                "spec": {},
                "status": {"phase": "Running"},
            }
        )
    if number == 62:
        policy = docs["networkpolicy/board-ingress"]
        if variant == "wrong-policy-uid":
            policy["metadata"]["uid"] = "recreated"
        elif variant == "template-mismatch":
            selected["spec"]["template"]["metadata"]["labels"]["role"] = "retired"
        elif variant == "current-mismatch":
            pod["metadata"]["labels"]["role"] = "retired"
        elif variant == "selector-expression":
            policy["spec"]["ingress"][0]["from"][0]["podSelector"] = {
                "matchExpressions": [
                    {"key": "role", "operator": "In", "values": ["dispatcher"]}
                ]
            }
    elif number == 113:
        route, gateway = docs["httproute/board"], docs["gateway/station"]
        parent = route["status"]["parents"][0]
        if variant == "wrong-route-uid":
            route["metadata"]["uid"] = "recreated"
        elif variant == "wrong-gateway-uid":
            gateway["metadata"]["uid"] = "recreated"
        elif variant == "changed-listener":
            gateway["spec"]["listeners"][0]["name"] = "retired"
        elif variant == "wrong-controller":
            parent["controllerName"] = "foreign/controller"
        elif variant == "wrong-parent":
            route["spec"]["parentRefs"][0]["sectionName"] = "retired"
        elif variant == "foreign-namespace":
            parent["parentRef"]["namespace"] = "foreign"
        elif variant == "stale-generation":
            parent["conditions"][0]["observedGeneration"] = 4
        elif variant == "missing-generation":
            parent["conditions"][0].pop("observedGeneration")
        elif variant == "unresolved":
            parent["conditions"][1]["status"] = "False"
        elif variant == "split-parents":
            other = copy.deepcopy(parent)
            parent["conditions"][1]["status"] = "False"
            other["conditions"][0]["status"] = "False"
            route["status"]["parents"].append(other)
        elif variant == "default-parent":
            route["spec"]["parentRefs"][0].pop("sectionName")
            parent["parentRef"].pop("sectionName")
        elif variant == "status-default":
            parent["parentRef"].pop("sectionName")
        elif variant == "explicit-parent":
            route["spec"]["parentRefs"][0].update(
                {
                    "namespace": "synthetic",
                    "group": "gateway.networking.k8s.io",
                    "kind": "Gateway",
                    "port": 8000,
                }
            )
        elif variant == "wrong-parent-port":
            route["spec"]["parentRefs"][0]["port"] = 9000
    elif number == 118:
        item = docs["endpointslices/"]["items"][0]
        endpoint = item["endpoints"][0]
        if variant == "wrong-vip":
            docs["service/board"]["spec"]["clusterIP"] = "10.96.0.8"
        elif variant == "wrong-service-uid":
            docs["service/board"]["metadata"]["uid"] = "recreated"
        elif variant == "wrong-endpoint-owner":
            item["metadata"]["ownerReferences"][0]["uid"] = "foreign"
        elif variant == "wrong-target":
            endpoint["targetRef"]["uid"] = "client-pod"
        elif variant == "wrong-address":
            endpoint["addresses"] = ["10.1.0.99"]
        elif variant == "wrong-target-namespace":
            endpoint["targetRef"]["namespace"] = "foreign"
        elif variant == "wrong-port":
            item["ports"][0]["port"] = 8099
        elif variant == "wrong-protocol":
            item["ports"][0]["protocol"] = "UDP"
        elif variant == "no-endpoints":
            item["endpoints"] = []
        elif variant == "named-target":
            docs["service/board"]["spec"]["ports"][0]["targetPort"] = "web"
            selected["spec"]["template"]["spec"]["containers"][0]["ports"] = [
                {"name": "web", "containerPort": 8080}
            ]
            pod["spec"]["containers"][0]["ports"] = [
                {"name": "web", "containerPort": 8080}
            ]
        elif variant == "desired-target-mismatch":
            docs["service/board"]["spec"]["ports"][0]["targetPort"] = 8099
        elif variant == "missing-named-template":
            docs["service/board"]["spec"]["ports"][0]["targetPort"] = "web"
            pod["spec"]["containers"][0]["ports"] = [
                {"name": "web", "containerPort": 8080}
            ]
        elif variant == "unrelated-slice":
            other = copy.deepcopy(item)
            other["metadata"]["labels"]["kubernetes.io/service-name"] = "foreign"
            other["endpoints"][0]["addresses"] = ["10.1.0.99"]
            docs["endpointslices/"]["items"].append(other)
    else:
        worker = selected["spec"]["template"]["spec"]["containers"][0]
        cms = docs["configmaps/"]["items"]
        if variant == "wrong-code-config":
            cms[1]["data"]["poll.sh"] = "changed"
        elif variant == "wrong-code-uid":
            cms[1]["metadata"]["uid"] = "recreated"
        elif variant == "wrong-metrics-uid":
            cms[0]["metadata"]["uid"] = "recreated"
        elif variant == "wrong-template-input":
            next(item for item in worker["env"] if item["name"] == "ROUTE")["value"] = (
                "retired"
            )
        elif variant == "wrong-launch":
            worker["command"] = ["sleep", "3600"]
        elif variant == "wrong-pod-launch":
            pod["spec"]["containers"][0]["command"] = ["sleep", "3600"]
        elif variant == "duplicate-pod":
            pods.append(copy.deepcopy(pod))
        elif variant in ("configmap-input", "wrong-input-map"):
            cms.append(
                {
                    "metadata": {"name": "inputs"},
                    "data": {
                        "ROUTE": "north" if variant == "configmap-input" else "retired"
                    },
                }
            )
            worker["env"] = [
                entry
                if entry["name"] != "ROUTE"
                else {
                    "name": "ROUTE",
                    "valueFrom": {
                        "configMapKeyRef": {"name": "inputs", "key": "ROUTE"}
                    },
                }
                for entry in worker["env"]
            ]
        elif variant == "envfrom-input":
            cms.append({"metadata": {"name": "inputs"}, "data": {"ROUTE": "north"}})
            worker["env"] = [
                entry for entry in worker["env"] if entry["name"] != "ROUTE"
            ]
            worker["envFrom"] = [{"configMapRef": {"name": "inputs"}}]
        elif variant == "expanded-input":
            worker["env"].insert(0, {"name": "FAMILY", "value": "station_queue"})
            next(item for item in worker["env"] if item["name"] == "METRIC")[
                "value"
            ] = "$(FAMILY)_depth"
        elif variant == "field-input":
            selected["spec"]["template"]["metadata"]["annotations"] = {
                "query-route": "north"
            }
            worker["env"] = [
                entry
                if entry["name"] != "ROUTE"
                else {
                    "name": "ROUTE",
                    "valueFrom": {
                        "fieldRef": {"fieldPath": "metadata.annotations['query-route']"}
                    },
                }
                for entry in worker["env"]
            ]
        elif variant == "secret-input":
            docs["secret/inputs"] = {
                "data": {
                    "ROUTE": base64.b64encode(b"north").decode(),
                    "private": base64.b64encode(b"NEVER_PRINT_SECRET").decode(),
                }
            }
            worker["env"] = [
                entry
                if entry["name"] != "ROUTE"
                else {
                    "name": "ROUTE",
                    "valueFrom": {"secretKeyRef": {"name": "inputs", "key": "ROUTE"}},
                }
                for entry in worker["env"]
            ]
    elapsed, counters = [0.0], {}
    real_read = Path.read_text

    def read(path, *args, **kwargs):
        return (
            json.dumps(facts)
            if str(path).startswith("/run/dq/facts/0/")
            else real_read(path, *args, **kwargs)
        )

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
            return SimpleNamespace(
                returncode=0, stdout=json.dumps(docs[key]), stderr=""
            )
        name = args[2]
        role = next(
            item
            for item in facts["contract"]["consumers"]
            if item["deployment"] + "-pod" == name
        )
        tool = args[args.index("--") + 1]
        if tool == "sh":
            values = dict(facts["intent"], OPERATION=role["operation"])
            if variant == "wrong-current-input":
                values["ROUTE"] = "retired"
            checksum = "0" * 64 if variant == "wrong-code-file" else HASH
            output = (
                "\n".join(
                    [
                        values[key]
                        for key in (
                            "PROMETHEUS_URL",
                            "METRIC",
                            "ROUTE",
                            "JOB",
                            "OPERATION",
                        )
                    ]
                    + [checksum + "  program"]
                )
                + "\n"
            )
        elif tool == "cat":
            count = counters.get(name, 0)
            counters[name] = count + 1
            output = (
                str(
                    1
                    if count == 0 or variant == "stalled"
                    else 0
                    if variant == "counter-reset"
                    else 3
                )
                + "\n"
            )
        else:
            value = str(role["expected"])
            if variant == "numeric-equivalent":
                value = "2.0" if role["expected"] == 2 else "7e0"
            elif variant == "wrong-value":
                value = "9"
            elif variant == "invalid-number":
                value = "NaN"
            results = (
                []
                if variant == "empty-result"
                else [{"metric": {}, "value": [123, value]}]
            )
            if variant == "multiple-results":
                results *= 2
            output = json.dumps(
                {
                    "status": "error" if variant == "query-error" else "success",
                    "data": {
                        "resultType": "matrix"
                        if variant == "wrong-result-type"
                        else "vector",
                        "result": results,
                    },
                }
            )
        return SimpleNamespace(returncode=0, stdout=output, stderr="")

    monkeypatch.setenv("DQ_NAMESPACE", "synthetic")
    monkeypatch.setattr(Path, "read_text", read)
    monkeypatch.setattr(subprocess, "run", cli)
    with monkeypatch.context() as clock:
        clock.setattr(time, "monotonic", lambda: elapsed[0])
        clock.setattr(
            time, "sleep", lambda seconds: elapsed.__setitem__(0, elapsed[0] + seconds)
        )
        try:
            exec(compile(code, "shipped-routing-observers", "exec"), {})
        except SystemExit as result:
            assert elapsed[0] <= 10
            return result.code or 0
    return 0


GOOD = ["valid", "digest-alias", "terminating-old", "unrelated", "moderate-api"]
BAD = ["wrong-workload-uid", "wrong-image", "wrong-pod-image", "slow-api", "api-error"]
CASES = [
    (
        62,
        0,
        GOOD + ["selector-expression"],
        BAD
        + [
            "wrong-policy-uid",
            "template-mismatch",
            "current-mismatch",
            "not-ready",
            "wrong-owner",
        ],
    ),
    (
        113,
        1,
        GOOD + ["default-parent", "status-default", "explicit-parent"],
        BAD
        + [
            "wrong-route-uid",
            "wrong-gateway-uid",
            "changed-listener",
            "wrong-controller",
            "wrong-parent",
            "foreign-namespace",
            "stale-generation",
            "missing-generation",
            "unresolved",
            "split-parents",
            "wrong-parent-port",
        ],
    ),
    (
        118,
        1,
        GOOD + ["named-target", "unrelated-slice"],
        BAD
        + [
            "wrong-vip",
            "wrong-service-uid",
            "wrong-endpoint-owner",
            "wrong-target",
            "wrong-address",
            "wrong-target-namespace",
            "wrong-port",
            "desired-target-mismatch",
            "missing-named-template",
            "wrong-protocol",
            "no-endpoints",
            "not-ready",
            "wrong-owner",
        ],
    ),
    (
        127,
        0,
        GOOD
        + [
            "configmap-input",
            "envfrom-input",
            "expanded-input",
            "field-input",
            "secret-input",
        ],
        BAD
        + [
            "wrong-code-config",
            "wrong-code-uid",
            "wrong-metrics-uid",
            "wrong-template-input",
            "wrong-launch",
            "wrong-pod-launch",
            "duplicate-pod",
            "wrong-input-map",
            "wrong-current-input",
            "wrong-code-file",
            "not-ready",
            "wrong-owner",
        ],
    ),
    (
        127,
        1,
        GOOD + ["numeric-equivalent"],
        [
            "wrong-workload-uid",
            "wrong-pod-image",
            "slow-api",
            "api-error",
            "not-ready",
            "wrong-owner",
            "duplicate-pod",
            "stalled",
            "counter-reset",
            "wrong-value",
            "invalid-number",
            "empty-result",
            "multiple-results",
            "query-error",
            "wrong-result-type",
        ],
    ),
]


@pytest.mark.parametrize(
    "number,index,variant,accepted",
    [
        (number, index, variant, accepted)
        for number, index, good, bad in CASES
        for accepted, variants in ((True, good), (False, bad))
        for variant in variants
    ],
)
def test_shipped_routing_observer_boundaries(
    monkeypatch, capsys, number, index, variant, accepted
):
    assert (execute_probe(monkeypatch, number, index, variant) == 0) is accepted
    output = capsys.readouterr()
    assert "NEVER_PRINT_SECRET" not in output.out + output.err


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Explicit local sandbox opt-in required",
)
@pytest.mark.parametrize("number", [62, 113, 118, 127])
def test_native_routing_observer_shortcuts(number):
    runtime, catalog = Runtime(ROOT / ".state/runtime"), Catalog()
    run = {"id": secrets.token_hex(12), "level": number}
    folder = Path(
        os.environ.get("DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/routing-observers")
    )
    folder.mkdir(parents=True, exist_ok=True)
    record = {"quest": number, "commands": []}

    def execute(script, expected=0, timeout=180):
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
        if expected is not None:
            assert result.returncode == expected, result.stdout + result.stderr
        return result

    def patch(kind, name, body, mode="json"):
        return execute(
            "kubectl patch "
            + kind
            + " "
            + name
            + " --type="
            + mode
            + " -p "
            + shlex.quote(json.dumps(body))
        )

    def wait_check(script):
        deadline = time.monotonic() + 45
        while True:
            result = execute(script, None, timeout=max(1, deadline - time.monotonic()))
            if result.returncode == 0:
                return
            assert time.monotonic() < deadline, result.stdout + result.stderr
            time.sleep(1)

    fixtures = ROOT / "tests/fixtures/deepen-routing-observers"
    old_check = (fixtures / f"{number:03}-legacy-check.sh").read_text()
    current = catalog.script(number, 0, "check")
    try:
        runtime.create(run)
        execute(catalog.script(number, 0, "setup"))
        runtime.capture_facts(
            dict(run, stage=0), catalog.quests[number]["immutable"][0]
        )
        for objective in catalog.quests[number]["stages"][0]["objectives"]:
            if objective.get("keep"):
                execute(objective["check"])
        execute((fixtures / f"{number:03}.sh").read_text())
        if number == 118:
            execute("""for i in $(seq 1 30); do
 if kubectl get endpointslices -l kubernetes.io/service-name=board -o json | jq -e 'any(.items[]; any(.endpoints[]?;.conditions.ready==true) and any(.ports[]?;.port==8099))' >/dev/null; then exit 0; fi
 sleep 1
done; exit 1""")
        execute(old_check, 0 if number == 127 else 1)
        execute(current, 1)
        record["old_minimum"] = (
            "Actual complete old reference rejected by expanded workflow"
        )
        if number == 62:
            execute("kubectl label pod -l app=dispatcher role=dispatcher --overwrite")
            wait_check(old_check)
            execute(current, 1)
            observed = json.loads(
                execute("kubectl get deployment dispatcher -o json").stdout
            )
            assert (
                observed["spec"]["template"]["metadata"]["labels"]["role"] == "retired"
            )
            record["pod_only_shortcut"] = (
                "Old whole check passes but desired caller template remains outside scope"
            )
        execute((ROOT / f"solutions/{number:03}/0.sh").read_text())
        execute(current)
        if number == 113:
            patch(
                "httproute",
                "board",
                [{"op": "remove", "path": "/spec/parentRefs/0/sectionName"}],
            )
            wait_check(current)
            record["default_parent"] = (
                "Omitted sectionName accepted after real controller convergence"
            )
        elif number == 118:
            patch(
                "deployment",
                "board",
                [
                    {
                        "op": "add",
                        "path": "/spec/template/spec/containers/0/ports",
                        "value": [
                            {"name": "web", "containerPort": 8080, "protocol": "TCP"}
                        ],
                    }
                ],
            )
            execute("kubectl rollout status deployment/board --timeout=90s")
            patch(
                "service",
                "board",
                [{"op": "replace", "path": "/spec/ports/0/targetPort", "value": "web"}],
            )
            wait_check(current)
            record["named_target"] = (
                "Real named targetPort accepted through current Pod and EndpointSlice mapping"
            )
        elif number == 127:
            execute(
                "kubectl create configmap observer-inputs --from-literal=METRIC=station_queue_depth --from-literal=ROUTE=north"
            )
            for name in ("observer-count", "observer-total"):
                deployment = json.loads(
                    execute("kubectl get deployment " + name + " -o json").stdout
                )
                entries = deployment["spec"]["template"]["spec"]["containers"][0]["env"]
                entries = [
                    entry
                    if entry["name"] not in ("METRIC", "ROUTE")
                    else {
                        "name": entry["name"],
                        "valueFrom": {
                            "configMapKeyRef": {
                                "name": "observer-inputs",
                                "key": entry["name"],
                            }
                        },
                    }
                    for entry in entries
                ]
                patch(
                    "deployment",
                    name,
                    [
                        {
                            "op": "replace",
                            "path": "/spec/template/spec/containers/0/env",
                            "value": entries,
                        }
                    ],
                )
                execute("kubectl rollout status deployment/" + name + " --timeout=90s")
            wait_check(current)
            patch(
                "configmap", "observer-inputs", {"data": {"ROUTE": "retired"}}, "merge"
            )
            execute(old_check)
            execute(current, 1)
            patch("configmap", "observer-inputs", {"data": {"ROUTE": "north"}}, "merge")
            execute(current)
            record["input_lifetime"] = (
                "ConfigMap-backed desired inputs accepted; drift rejected while current process still returns correct values"
            )
        record["result"] = "PASS"
    except BaseException as error:
        record["error"] = repr(error)
        try:
            execute(
                "kubectl get deployments,pods,services,endpointslices -o json",
                None,
                timeout=15,
            )
        except Exception as observation:
            record["observation_error"] = repr(observation)
        raise
    finally:
        try:
            runtime.teardown(run)
            record["teardown"] = "PASS"
        finally:
            (folder / f"{number:03}-shortcuts.json").write_text(
                json.dumps(record, indent=2) + "\n"
            )
