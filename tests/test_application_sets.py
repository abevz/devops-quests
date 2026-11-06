"""ApplicationSet YAML submission retains the existing bounded control boundary."""

import copy
import json
import os
import subprocess
from types import SimpleNamespace

import pytest
import yaml

from devops_quests.application_sets import ApplicationSets
from devops_quests.sandbox_evidence import bounded_yaml_reader

RUN = {"id": "a" * 24, "level": 123}


@pytest.fixture
def submission(tmp_path):
    home = tmp_path / "home"
    quest = home / "quest"
    quest.mkdir(parents=True)
    target = quest / "applicationset.yaml"

    class Runtime:
        installation = "synthetic-installation"
        state = tmp_path / "runtime"

        def __init__(self):
            self.commands = []
            self.calls = []
            self.applied = None
            (self.state / "bays" / RUN["id"]).mkdir(parents=True)

        def namespace(self, run):
            return "dq-" + run["id"]

        def exec(self, run, command, **kwargs):
            self.commands.append((command, kwargs))
            return subprocess.run(
                ["bash", "-c", command],
                env={**os.environ, "HOME": str(home)},
                capture_output=True,
                text=True,
                timeout=5,
            )

        def kube(self, *args, input=None, **kwargs):
            self.calls.append((args, input))
            if "apply" in args:
                self.applied = json.loads(input)
                return SimpleNamespace(stdout="")
            return SimpleNamespace(
                stdout=json.dumps({"metadata": {"uid": "owned-appset"}})
                if self.applied else ""
            )

    runtime = Runtime()
    return target, runtime, ApplicationSets(runtime)


@pytest.mark.parametrize("repaired", [False, True])
def test_123_accepts_both_allowed_yaml_manifests_and_keeps_json_transport(submission, repaired):
    target, runtime, adapter = submission
    expected = adapter.manifest(RUN, repaired)
    target.write_text(yaml.safe_dump(expected, sort_keys=False))
    adapter.control(RUN)
    wanted = copy.deepcopy(expected)
    wanted["metadata"]["labels"] = adapter.labels(RUN)
    assert runtime.applied == wanted
    command, options = runtime.commands[0]
    assert command == (
        "/usr/bin/python3 - applicationset.yaml <<'APPSET_CONTROL'\n"
        + bounded_yaml_reader()
        + "\nAPPSET_CONTROL\n"
    )
    assert options == {"check": False, "timeout": 3}
    receipt = runtime.state / "bays" / RUN["id"] / "appset-identity.json"
    assert json.loads(receipt.read_text()) == {"uid": "owned-appset"}
    assert receipt.stat().st_mode & 0o777 == 0o600


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
def test_123_rejects_invalid_yaml_before_any_cluster_access(submission, content):
    target, runtime, adapter = submission
    target.write_bytes(content)
    adapter.control(RUN)
    assert runtime.calls == []
    assert runtime.applied is None


@pytest.mark.parametrize("kind", ["symlink", "fifo", "missing"])
def test_123_refuses_nonregular_or_missing_inputs_without_blocking(submission, tmp_path, kind):
    target, runtime, adapter = submission
    outside = tmp_path / "outside.yaml"
    if kind == "symlink":
        outside.write_text("credential: must-not-be-read")
        target.symlink_to(outside)
    elif kind == "fifo":
        os.mkfifo(target)
    adapter.control(RUN)
    assert runtime.calls == []
    assert runtime.applied is None
    if kind == "symlink":
        assert outside.read_text() == "credential: must-not-be-read"


def test_123_yaml_does_not_expand_the_allowed_application_scope(submission):
    target, runtime, adapter = submission
    value = adapter.manifest(RUN, True)
    value["spec"]["template"]["spec"]["destination"]["namespace"] = "foreign"
    target.write_text(yaml.safe_dump(value))
    adapter.control(RUN)
    assert runtime.calls == []
