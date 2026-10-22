"""Bounded backend observations for book exercises; no player node access."""

import json
import re

from .platform import Platform


def proxy_observation(runtime, run):
    raw = runtime.kube(
        "-n", "kube-system", "get", "daemonset", "kube-proxy", "-o", "json"
    ).stdout
    ds = json.loads(raw)
    logs = runtime.kube(
        "-n", "kube-system", "logs", "daemonset/kube-proxy", "--tail=100"
    ).stdout
    mode = re.search(r"Using (iptables|nftables|ipvs) Proxier", logs, re.IGNORECASE)
    if not mode:
        raise RuntimeError("Cannot establish actual kube-proxy mode from its log")
    Platform(runtime).put(
        run,
        "proxy-observation.json",
        json.dumps(
            {
                "mode": mode.group(1).lower(),
                "ready": ds["status"].get("numberReady")
                == ds["status"].get("desiredNumberScheduled")
                == 1,
                "source": "live kube-proxy DaemonSet and log",
            }
        ),
    )


def install_operator(runtime, run):
    """Install only the inert namespaced training API, not a cluster operator."""
    import yaml

    item = yaml.safe_load((runtime.root / "vendor/station-board-crd.yaml").read_text())
    name = item["metadata"]["name"]
    existing = runtime.kube(
        "get", "crd", name, "--ignore-not-found", "-o", "json"
    ).stdout.strip()
    if existing:
        if (
            json.loads(existing)["metadata"]
            .get("labels", {})
            .get("devops-quests.installation")
            != runtime.installation
        ):
            raise RuntimeError("Refusing a foreign training CRD")
    else:
        item["metadata"]["labels"] = {
            "devops-quests.installation": runtime.installation
        }
        runtime.kube("create", "-f", "-", input=json.dumps(item))
    runtime.kube("wait", "--for=condition=Established", "crd/" + name, "--timeout=30s")


def reconcile(runtime, run):
    """One desired-state loop; exact owned namespace/name and finite route enum."""
    if run["level"] != 116:
        return
    namespace = runtime.namespace(run)
    raw = runtime.kube(
        "-n",
        namespace,
        "get",
        "stationboard",
        "station",
        "--ignore-not-found",
        "-o",
        "json",
    ).stdout.strip()
    if not raw:
        return
    board = json.loads(raw)
    value = board.get("spec", {}).get("route")
    if value not in {"closed", "north-116"} or board["metadata"].get(
        "deletionTimestamp"
    ):
        return
    owner = [
        {
            "apiVersion": board["apiVersion"],
            "kind": "StationBoard",
            "name": "station",
            "uid": board["metadata"]["uid"],
            "controller": True,
            "blockOwnerDeletion": False,
        }
    ]
    labels = {
        "devops-quests.controller": "station-board",
        "devops-quests.run": run["id"],
    }

    def obj(kind, name, api="v1", **fields):
        return {
            "apiVersion": api,
            "kind": kind,
            "metadata": {
                "name": name,
                "namespace": namespace,
                "labels": labels,
                "ownerReferences": owner,
            },
            **fields,
        }

    objects = [
        obj("ConfigMap", "board-route", data={"index.html": value + "\n"}),
        obj(
            "Service",
            "board",
            spec={
                "selector": {"app": "board"},
                "ports": [{"port": 8080, "targetPort": 8080}],
            },
        ),
        obj(
            "Deployment",
            "board",
            "apps/v1",
            spec={
                "replicas": 1,
                "selector": {"matchLabels": {"app": "board"}},
                "template": {
                    "metadata": {"labels": {"app": "board"}},
                    "spec": {
                        "automountServiceAccountToken": False,
                        "terminationGracePeriodSeconds": 1,
                        "securityContext": {
                            "runAsNonRoot": True,
                            "runAsUser": 1000,
                            "fsGroup": 1000,
                            "seccompProfile": {"type": "RuntimeDefault"},
                        },
                        "volumes": [
                            {"name": "route", "configMap": {"name": "board-route"}}
                        ],
                        "containers": [
                            {
                                "name": "board",
                                "image": runtime.images["app"],
                                "imagePullPolicy": "Never",
                                "command": ["httpd", "-f", "-p", "8080", "-h", "/site"],
                                "volumeMounts": [
                                    {
                                        "name": "route",
                                        "mountPath": "/site",
                                        "readOnly": True,
                                    }
                                ],
                                "securityContext": {
                                    "allowPrivilegeEscalation": False,
                                    "capabilities": {"drop": ["ALL"]},
                                    "readOnlyRootFilesystem": True,
                                },
                                "resources": {
                                    "requests": {"cpu": "10m", "memory": "8Mi"},
                                    "limits": {"cpu": "200m", "memory": "32Mi"},
                                },
                                "readinessProbe": {
                                    "httpGet": {"path": "/", "port": 8080},
                                    "periodSeconds": 1,
                                },
                            }
                        ],
                    },
                },
            },
        ),
    ]
    for item in objects:
        current = runtime.kube(
            "-n",
            namespace,
            "get",
            item["kind"],
            item["metadata"]["name"],
            "--ignore-not-found",
            "-o",
            "json",
        ).stdout.strip()
        if current and not any(
            o.get("uid") == owner[0]["uid"]
            for o in json.loads(current)["metadata"].get("ownerReferences", [])
        ):
            raise RuntimeError("Refusing to adopt a foreign operator workload")
        runtime.kube("apply", "-f", "-", input=json.dumps(item))
    deployment = json.loads(
        runtime.kube("-n", namespace, "get", "deployment", "board", "-o", "json").stdout
    )
    status = {
        "observedGeneration": board["metadata"]["generation"],
        "ready": deployment.get("status", {}).get("readyReplicas") == 1,
    }
    if board.get("status") != status:
        runtime.kube(
            "-n",
            namespace,
            "patch",
            "stationboard",
            "station",
            "--subresource=status",
            "--type=merge",
            "-p",
            json.dumps({"status": status}),
        )


def metrics_route(runtime, run, address):
    """The internal Docker network has no default route in the kind node.

    A host-network apiserver needs an initial route before OUTPUT Service DNAT.
    Add only this APIService's /32 inside the owned kind container; never a
    default route or a route on the workstation/VM host.
    """
    import ipaddress

    from .owned_kind import owned_node

    address = str(ipaddress.IPv4Address(address))
    node = owned_node(runtime, run)
    prefix = address + "/32"
    existing = runtime.docker(
        "exec", node, "ip", "-j", "route", "show", "exact", prefix
    ).stdout
    if json.loads(existing):
        raise RuntimeError("Refusing an existing metrics VIP route")
    folder = runtime.state / "bays" / run["id"]
    path = folder / "metrics-route.json"
    path.write_text(
        json.dumps(
            {"address": address, "installation": runtime.installation, "run": run["id"]}
        )
    )
    path.chmod(0o600)
    runtime.docker(
        "exec", node, "ip", "route", "add", prefix, "dev", "eth0", "proto", "static"
    )


def remove_metrics_route(runtime, run):
    import ipaddress

    from .owned_kind import owned_node

    path = runtime.state / "bays" / run["id"] / "metrics-route.json"
    if not path.exists():
        return
    data = json.loads(path.read_text())
    if data.get("installation") != runtime.installation or data.get("run") != run["id"]:
        raise RuntimeError("Refusing a foreign metrics route receipt")
    prefix = str(ipaddress.IPv4Address(data["address"])) + "/32"
    node = owned_node(runtime, run)
    entries = json.loads(
        runtime.docker(
            "exec", node, "ip", "-j", "route", "show", "exact", prefix
        ).stdout
    )
    if entries:
        if (
            len(entries) != 1
            or entries[0].get("dev") != "eth0"
            or entries[0].get("protocol") != "static"
            or entries[0].get("gateway")
        ):
            raise RuntimeError("Refusing a changed metrics VIP route")
        runtime.docker(
            "exec", node, "ip", "route", "del", prefix, "dev", "eth0", "proto", "static"
        )
    path.unlink()
