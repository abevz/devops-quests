"""The private registry setup handles only its generated bay credentials."""

import base64
import json
import os
import shlex
import stat
import subprocess

import pytest

from devops_quests.catalog import ROOT


@pytest.mark.parametrize("existing", ["regular", "symlink"])
def test_registry_secret_is_private_and_no_password_in_arguments(tmp_path, existing):
    home = tmp_path / "home"
    quest = home / "quest"
    quest.mkdir(parents=True)
    binary = tmp_path / "bin"
    binary.mkdir()
    capture = tmp_path / "kubectl-argv.json"
    stub = binary / "kubectl"
    stub.write_text(
        '#!/usr/bin/python3\nimport json,os,sys\nopen(os.environ["ARGV_CAPTURE"],"w").write(json.dumps(sys.argv[1:]))\n'
    )
    stub.chmod(0o755)
    secret = 'synthetic & not-a-real-secret " with space'
    environment_values = {
        "REGISTRY": "registry-example:5000",
        "REGISTRY_USER": "synthetic-user",
        "REGISTRY_PASSWORD": secret,
        "PRIVATE_IMAGE": "registry-example:5000/image@sha256:abc",
    }
    (quest / "platform.env").write_text(
        "\n".join(
            f"export {key}={shlex.quote(value)}"
            for key, value in environment_values.items()
        )
        + "\n"
    )
    target = quest / "registry-pull.json"
    sentinel = tmp_path / "sentinel"
    sentinel.write_text("leave unchanged")
    if existing == "symlink":
        target.symlink_to(sentinel)
    else:
        target.write_text("stale")
        target.chmod(0o666)
    source = (
        (ROOT / "quests/080/setup-0.sh")
        .read_text()
        .split("mkdir -p repository/manifests", 1)[0]
    )
    env = {
        **os.environ,
        "HOME": str(home),
        "PATH": f"{binary}:{os.environ['PATH']}",
        "ARGV_CAPTURE": str(capture),
    }
    result = subprocess.run(
        ["bash", "-c", source], env=env, text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, result.stderr
    assert not target.is_symlink()
    assert sentinel.read_text() == "leave unchanged"
    assert stat.S_IMODE(target.stat().st_mode) == 0o600
    args = json.loads(capture.read_text())
    assert args == ["apply", "-f", "registry-pull.json"]
    assert secret not in result.stdout + result.stderr + " ".join(args)
    document = json.loads(target.read_text())
    assert document["type"] == "kubernetes.io/dockerconfigjson"
    config = json.loads(base64.b64decode(document["data"][".dockerconfigjson"]))
    auth = config["auths"][environment_values["REGISTRY"]]
    assert (
        base64.b64decode(auth["auth"]).decode()
        == f"{environment_values['REGISTRY_USER']}:{secret}"
    )
    assert not list(quest.glob(".registry-pull-*"))


def test_registry_secret_temporary_file_is_removed_when_replace_fails(tmp_path):
    home = tmp_path / "home"
    quest = home / "quest"
    quest.mkdir(parents=True)
    target = quest / "registry-pull.json"
    target.write_text("previous")
    (quest / "platform.env").write_text(
        "export REGISTRY=registry-example REGISTRY_USER=demo REGISTRY_PASSWORD=synthetic PRIVATE_IMAGE=example\n"
    )
    hook = tmp_path / "hook"
    hook.mkdir()
    (hook / "sitecustomize.py").write_text(
        "import os\n"
        "def fail_replace(*args, **kwargs):\n"
        "    raise OSError('synthetic replace failure')\n"
        "os.replace = fail_replace\n"
    )
    source = (
        (ROOT / "quests/080/setup-0.sh")
        .read_text()
        .split("mkdir -p repository/manifests", 1)[0]
    )
    env = {**os.environ, "HOME": str(home), "PYTHONPATH": str(hook)}
    result = subprocess.run(
        ["bash", "-c", source], env=env, text=True, capture_output=True, timeout=10
    )
    assert result.returncode != 0
    assert target.read_text() == "previous"
    assert not list(quest.glob(".registry-pull-*"))
