"""A finite static-Pod lab adapter, confined to the owned kind container."""

import json
import re

from .sandbox_evidence import CONTROL_READER, record


def manifest(runtime, run, port):
    return {
        "apiVersion": "v1",
        "kind": "Pod",
        "metadata": {
            "name": "static-board",
            "namespace": runtime.namespace(run),
            "labels": {"app": "static-board"},
        },
        "spec": {
            "automountServiceAccountToken": False,
            "terminationGracePeriodSeconds": 1,
            "securityContext": {
                "runAsNonRoot": True,
                "runAsUser": 1000,
                "seccompProfile": {"type": "RuntimeDefault"},
            },
            "containers": [
                {
                    "name": "board",
                    "image": runtime.images["app"],
                    "imagePullPolicy": "Never",
                    "command": [
                        "sh",
                        "-c",
                        f"mkdir -p /tmp/site; echo north-117 > /tmp/site/index.html; exec httpd -f -p {port} -h /tmp/site",
                    ],
                    "securityContext": {
                        "allowPrivilegeEscalation": False,
                        "capabilities": {"drop": ["ALL"]},
                    },
                    "resources": {
                        "requests": {"cpu": "10m", "memory": "8Mi"},
                        "limits": {"cpu": "200m", "memory": "32Mi"},
                    },
                }
            ],
        },
    }


def node(runtime, run):
    if not re.fullmatch(r"[a-f0-9]{24}", run["id"]) or run["level"] != 117:
        raise ValueError("Invalid static-Pod bay")
    from .owned_kind import owned_node

    return owned_node(runtime, run)


def paths(run):
    identifier = run["id"]
    return (
        f"/tmp/dq-static-{identifier}.json",
        f"/etc/kubernetes/manifests/dq-{identifier}.json",
    )


def control(runtime, run):
    if run["level"] != 117:
        return
    result = runtime.exec(
        run,
        "python3 - static-pod.json <<'STATIC_REQUEST'\n"
        + CONTROL_READER
        + "\nSTATIC_REQUEST\n",
        check=False,
        timeout=3,
    )
    if result.returncode:
        return
    try:
        value = json.loads(result.stdout)
    except ValueError:
        return
    if value not in [manifest(runtime, run, 8080), manifest(runtime, run, 8099)]:
        return
    owned = node(runtime, run)
    temporary, destination = paths(run)
    content = json.dumps(value, sort_keys=True) + "\n"
    current = runtime.docker("exec", owned, "cat", destination, check=False)
    if current.returncode or current.stdout != content:
        runtime.docker(
            "exec",
            "-i",
            owned,
            "sh",
            "-c",
            f"set -eu; umask 077; cat > {temporary}; mv -- {temporary} {destination}",
            input=content,
        )
    mirror = runtime.kube(
        "-n",
        runtime.namespace(run),
        "get",
        "pod",
        "static-board-" + owned,
        "--ignore-not-found",
        "-o",
        "json",
    ).stdout.strip()
    if not mirror:
        return
    mirror = json.loads(mirror)
    cri = json.loads(
        runtime.docker(
            "exec",
            owned,
            "crictl",
            "pods",
            "--name",
            "static-board",
            "--namespace",
            runtime.namespace(run),
            "-o",
            "json",
        ).stdout
    )
    desired = json.loads(
        runtime.kube(
            "get",
            "--raw=/api/v1/nodes/" + owned + "/proxy/pods",
            "--request-timeout=3s",
            timeout=5,
        ).stdout
    )
    # Only the backend's existing admin client uses this fixed read endpoint.
    # No nodes/proxy permission or kubelet endpoint is exposed to the player.
    verified = file_origin(
        desired.get("items", []),
        cri.get("items", []),
        mirror,
        manifest(runtime, run, 8080),
        owned,
    )
    if verified and value == manifest(runtime, run, 8080):
        record(
            runtime,
            run,
            "static-pod.json",
            {
                "verified": True,
                "source": "file",
                "configHash": mirror["metadata"]["annotations"][
                    "kubernetes.io/config.mirror"
                ],
                "mirrorUID": mirror["metadata"]["uid"],
                "node": owned,
                "path": destination,
            },
        )


def file_origin(pods, sandboxes, mirror, expected, owned):
    """Join kubelet's source-owned Pod view to CRI, never API annotations alone.

    Kubernetes v1.37 config/config.go overwrites config.source from the real
    channel. PodManager.GetPods excludes mirrors; the kubelet's /pods endpoint
    exposes that internal view. The runtime uses the internal UID in CRI.
    """
    name = "static-board-" + owned
    namespace = expected["metadata"]["namespace"]
    fingerprint = (
        mirror["metadata"].get("annotations", {}).get("kubernetes.io/config.mirror")
    )
    if not isinstance(fingerprint, str) or not re.fullmatch(
        r"[a-f0-9]{32}", fingerprint
    ):
        return False
    if fingerprint == mirror["metadata"]["uid"]:
        return False
    for pod in pods:
        meta = pod.get("metadata", {})
        annotations = meta.get("annotations", {})
        spec = pod.get("spec", {})
        if not (
            meta.get("namespace") == namespace
            and meta.get("name") == name
            and meta.get("uid") == fingerprint
            and annotations.get("kubernetes.io/config.source") == "file"
            and annotations.get("kubernetes.io/config.hash") == fingerprint
        ):
            continue
        if spec.get("nodeName") != owned or any(
            spec.get(k)
            for k in (
                "hostNetwork",
                "hostPID",
                "hostIPC",
                "volumes",
                "initContainers",
                "ephemeralContainers",
            )
        ):
            continue
        if (
            spec.get("automountServiceAccountToken") is not False
            or spec.get("securityContext") != expected["spec"]["securityContext"]
        ):
            continue
        containers = spec.get("containers", [])
        if len(containers) != 1:
            continue
        actual = containers[0]
        wanted = expected["spec"]["containers"][0]
        if any(
            actual.get(k) != wanted[k]
            for k in (
                "name",
                "image",
                "imagePullPolicy",
                "command",
                "securityContext",
                "resources",
            )
        ) or actual.get("args"):
            continue
        return any(
            item.get("metadata", {}).get("namespace") == namespace
            and item.get("metadata", {}).get("name") == name
            and item.get("metadata", {}).get("uid") == fingerprint
            and item.get("state") == "SANDBOX_READY"
            for item in sandboxes
        )
    return False


def teardown(runtime, run):
    owned = node(runtime, run)
    temporary, destination = paths(run)
    runtime.docker("exec", owned, "rm", "-f", "--", destination, temporary)
