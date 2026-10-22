"""Player input cannot turn a static-Pod exercise into node administration."""

import copy
import json
from types import SimpleNamespace

import pytest

from devops_quests.static_pods import control, manifest

RUN = {"id": "a" * 24, "level": 117}


class Runtime:
    def __init__(self):
        self.images = {"app": "busybox@sha256:pinned"}

    def namespace(self, run):
        return "dq-" + run["id"]


@pytest.mark.parametrize(
    "mutate",
    ["privileged", "hostPath", "hostNetwork", "image", "namespace", "extra-command"],
)
def test_rejects_entire_unsafe_manifest_before_any_node_access(mutate):
    r = Runtime()
    value = copy.deepcopy(manifest(r, RUN, 8080))
    if mutate == "privileged":
        value["spec"]["containers"][0]["securityContext"]["privileged"] = True
    if mutate == "hostPath":
        value["spec"]["volumes"] = [{"name": "escape", "hostPath": {"path": "/"}}]
    if mutate == "hostNetwork":
        value["spec"]["hostNetwork"] = True
    if mutate == "image":
        value["spec"]["containers"][0]["image"] = "foreign:latest"
    if mutate == "namespace":
        value["metadata"]["namespace"] = "kube-system"
    if mutate == "extra-command":
        value["spec"]["containers"][0]["command"][-1] += "; cat /etc/shadow"
    r.exec = lambda *a, **k: SimpleNamespace(returncode=0, stdout=json.dumps(value))
    # No inspect/docker/state exists: a rejected request must never reach them.
    control(r, RUN)


def test_malformed_control_is_ignored():
    r = Runtime()
    r.exec = lambda *a, **k: SimpleNamespace(returncode=0, stdout="not json")
    control(r, RUN)


def origin_fixture():
    from devops_quests.static_pods import file_origin

    r = Runtime()
    expected = manifest(r, RUN, 8080)
    owned = "devops-quests-control-plane"
    fingerprint = "b" * 32
    pod = copy.deepcopy(expected)
    pod["metadata"].update(
        name="static-board-" + owned,
        uid=fingerprint,
        annotations={
            "kubernetes.io/config.source": "file",
            "kubernetes.io/config.hash": fingerprint,
        },
    )
    pod["spec"]["nodeName"] = owned
    mirror = {
        "metadata": {
            "uid": "api-mirror-uuid",
            "annotations": {"kubernetes.io/config.mirror": fingerprint},
        }
    }
    cri = {
        "metadata": {
            "uid": fingerprint,
            "name": "static-board-" + owned,
            "namespace": r.namespace(RUN),
        },
        "state": "SANDBOX_READY",
    }
    return file_origin, pod, cri, mirror, expected, owned


def test_file_origin_requires_kubelet_source_and_matching_real_runtime():
    verify, pod, cri, mirror, expected, owned = origin_fixture()
    assert verify([pod], [cri], mirror, expected, owned)


@pytest.mark.parametrize(
    "spoof",
    [
        "api-source",
        "mirror-only",
        "self-uid",
        "wrong-namespace",
        "wrong-name",
        "old-command",
        "wrong-image",
        "not-ready",
    ],
)
def test_api_annotation_or_unrelated_runtime_cannot_forge_file_origin(spoof):
    verify, pod, cri, mirror, expected, owned = origin_fixture()
    if spoof == "api-source":
        pod["metadata"]["annotations"]["kubernetes.io/config.source"] = "api"
    if spoof == "mirror-only":
        pod = None
    if spoof == "self-uid":
        mirror["metadata"]["uid"] = pod["metadata"]["uid"]
    if spoof == "wrong-namespace":
        cri["metadata"]["namespace"] = "foreign"
    if spoof == "wrong-name":
        cri["metadata"]["name"] = "api-counterfeit"
    if spoof == "old-command":
        pod["spec"]["containers"][0]["command"][-1] = pod["spec"]["containers"][0][
            "command"
        ][-1].replace("8080", "8099")
    if spoof == "wrong-image":
        pod["spec"]["containers"][0]["image"] = "foreign"
    if spoof == "not-ready":
        cri["state"] = "SANDBOX_NOTREADY"
    assert not verify([pod] if pod else [], [cri], mirror, expected, owned)
