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


@pytest.fixture
def static_request(tmp_path):
    import os
    import subprocess
    import sys

    from devops_quests.static_pods import _STATIC_CONTROL_READER

    home = tmp_path / "home"
    quest = home / "quest"
    quest.mkdir(parents=True)
    target = quest / "static-pod.yaml"

    def read():
        return subprocess.run(
            [sys.executable, "-c", _STATIC_CONTROL_READER, target.name],
            env={**os.environ, "HOME": str(home)},
            capture_output=True,
            text=True,
            timeout=5,
        )

    return target, read


def test_yaml_control_reader_accepts_the_supplied_manifest(static_request):
    import yaml

    target, read = static_request
    expected = manifest(Runtime(), RUN, 8080)
    target.write_text(yaml.safe_dump(expected, sort_keys=False))
    result = read()
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == expected


@pytest.mark.parametrize(
    "content",
    [
        b"\xff",
        b"key: [unterminated",
        b"!!python/object/apply:os.system ['exit 0']",
        b"a: &a [*a]",
        b"a: &a [1, 2]\nb: [*a, *a]",
        b"[" * 65 + b"0" + b"]" * 65,
        b"value: " + b"x" * 4096,
        b"date: 2026-11-06",
    ],
    ids=["encoding", "syntax", "unsafe-tag", "recursive-alias", "alias-expansion",
         "depth", "size", "non-json-type"],
)
def test_yaml_control_reader_rejects_unbounded_or_invalid_input(static_request, content):
    target, read = static_request
    target.write_bytes(content)
    result = read()
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "null"


def test_yaml_control_reader_does_not_follow_symlinks(static_request, tmp_path):
    target, read = static_request
    outside = tmp_path / "outside.yaml"
    outside.write_text("secret: must-not-be-read")
    target.symlink_to(outside)
    result = read()
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "null"
    assert outside.read_text() == "secret: must-not-be-read"


def test_yaml_control_reader_rejects_fifo_without_blocking(static_request):
    import os

    target, read = static_request
    os.mkfifo(target)
    result = read()
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "null"


def test_yaml_control_reader_missing_file_is_not_a_request(static_request):
    _, read = static_request
    result = read()
    assert result.returncode == 1
    assert not result.stdout


def test_control_reads_yaml_player_input_and_keeps_json_transport():
    r = Runtime()
    commands = []

    def execute(run, command, **kwargs):
        commands.append((command, kwargs))
        return SimpleNamespace(returncode=0, stdout="null")

    r.exec = execute
    control(r, RUN)
    assert len(commands) == 1
    command, options = commands[0]
    assert command.startswith("python3 - static-pod.yaml <<'STATIC_REQUEST'\n")
    assert "static-pod.json" not in command
    assert options == {"check": False, "timeout": 3}
