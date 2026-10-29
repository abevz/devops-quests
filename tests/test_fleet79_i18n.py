"""Fleet playbook and live-host failures expose translated diagnostics."""

import ast
import os
import re
import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import Catalog, ROOT


@pytest.fixture(scope="module")
def catalog():
    return Catalog()


def check_markers(catalog, output):
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", output)
    assert markers and len(markers) == len(output.splitlines()), output
    for marker in markers:
        assert set(catalog.public(79)["diagnostics"][marker]) >= {
            "en",
            "pl",
            "es",
            "de",
            "ru",
        }, marker
    return markers


@pytest.mark.parametrize(
    "play",
    [
        [None],
        [{"hosts": "wrong", "tasks": [], "handlers": []}],
        [{"hosts": "fleet", "tasks": [{"shell": "true"}]}],
    ],
)
def test_malformed_or_invalid_play_has_diagnostic(tmp_path, catalog, play):
    (tmp_path / "rollout.yml").write_text(yaml.safe_dump(play))
    source = (ROOT / "quests/079/check-0.sh").read_text()
    assert source == catalog.quests[79]["stages"][0]["objectives"][0]["check"]
    code = source.split("<<'DQ_FLEET'\n", 1)[1].split("\nDQ_FLEET\n", 1)[0]
    result = subprocess.run(
        [sys.executable, "-"],
        input=code,
        cwd=tmp_path,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode != 0
    assert not result.stderr, result.stderr
    check_markers(catalog, result.stdout)
    tree = ast.parse(code)
    assignment = next(
        node
        for node in tree.body
        if isinstance(node, ast.Assign)
        and any(
            isinstance(target, ast.Name) and target.id == "DIAGNOSTIC_IDS"
            for target in node.targets
        )
    )
    for marker in ast.literal_eval(assignment.value).values():
        assert set(catalog.public(79)["diagnostics"][marker]) >= {
            "en",
            "pl",
            "es",
            "de",
            "ru",
        }


@pytest.mark.parametrize("host", [1, 2, 3])
def test_remote_file_failures_include_host_identity(tmp_path, catalog, host):
    source = (ROOT / "quests/079/check-0.sh").read_text()
    code = (
        source.split("<<'DQ_REMOTE'\n", 1)[1]
        .split("\nDQ_REMOTE\n", 1)[0]
        .replace("/srv/site", str(tmp_path / "missing"))
    )
    result = subprocess.run(
        ["bash", "-c", code],
        env={**os.environ, "HOST": f"app{host}"},
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode != 0
    markers = check_markers(catalog, result.stdout)
    assert set(markers) == {
        f"host_{host}_{key}"
        for key in (
            "dir_mode",
            "banner_mode",
            "banner_content",
            "route_mode",
            "route_content",
        )
    }


def test_many_failures_fit_the_interactive_detail_limit(tmp_path, catalog):
    home = tmp_path / "home"
    quest = home / "quest"
    quest.mkdir(parents=True)
    tasks = [
        {
            "copy": {
                "dest": "/srv/site/config",
                "mode": "600",
                "content": "wrong",
                "extra": True,
            },
            "when": False,
            "extra": 1,
            "notify": "wrong",
        },
        {
            "file": {
                "path": "/srv/site/message",
                "mode": "600",
                "state": "absent",
                "extra": True,
            },
            "when": False,
            "extra": 1,
            "notify": "wrong",
        },
        {
            "file": {
                "path": "/srv/site/config/route",
                "mode": "600",
                "state": "absent",
                "extra": True,
            },
            "when": False,
            "extra": 1,
            "notify": "wrong",
        },
    ]
    (quest / "rollout.yml").write_text(
        yaml.safe_dump(
            [
                {
                    "hosts": "nope",
                    "other": True,
                    "handlers": [{"name": "wrong", "command": "bad", "extra": "value"}],
                    "tasks": tasks + [tasks[0]] * 97,
                }
            ]
        )
    )
    binaries = tmp_path / "bin"
    binaries.mkdir()
    ssh = binaries / "ssh"
    ssh.write_text(
        "#!/usr/bin/python3\nimport os,subprocess,sys\ncommand=sys.argv[-1]; env=dict(os.environ, HOST=command.split()[0].split('=',1)[1]); source=sys.stdin.read().replace('/srv/site',os.environ['MISSING_SITE']); sys.exit(subprocess.run(['bash','-c',source],env=env).returncode)\n"
    )
    ssh.chmod(0o755)
    curl = binaries / "curl"
    curl.write_text("#!/bin/sh\nexit 1\n")
    curl.chmod(0o755)
    source = (ROOT / "quests/079/check-0.sh").read_text()
    env = {
        **os.environ,
        "HOME": str(home),
        "PATH": f"{binaries}:{os.environ['PATH']}",
        "DQ_NAMESPACE": "dq-test",
        "MISSING_SITE": str(tmp_path / "missing"),
    }
    result = subprocess.run(
        ["bash", "-c", source], env=env, text=True, capture_output=True, timeout=20
    )
    assert result.returncode != 0
    markers = check_markers(catalog, result.stdout)
    assert len(result.stdout) <= 2000
    assert len(markers) == len(set(markers))
    for host in (1, 2, 3):
        assert {
            f"host_{host}_{key}"
            for key in (
                "dir_mode",
                "banner_mode",
                "banner_content",
                "route_mode",
                "route_content",
            )
        } <= set(markers)
        assert {f"recap_{host}", f"http_{host}"} <= set(markers)


def test_empty_ssh_failures_identify_each_host(tmp_path, catalog):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    binaries = tmp_path / "bin"
    binaries.mkdir()
    for name in ("ssh", "curl"):
        binary = binaries / name
        binary.write_text("#!/bin/sh\nexit 1\n")
        binary.chmod(0o755)
    source = (ROOT / "quests/079/check-0.sh").read_text()
    env = {
        **os.environ,
        "HOME": str(home),
        "PATH": f"{binaries}:{os.environ['PATH']}",
        "DQ_NAMESPACE": "dq-test",
    }
    result = subprocess.run(
        ["bash", "-c", source], env=env, text=True, capture_output=True, timeout=20
    )
    assert result.returncode != 0
    markers = check_markers(catalog, result.stdout)
    assert {f"ssh_{host}" for host in (1, 2, 3)} <= set(markers)
    assert not any(marker.startswith("host_") for marker in markers)
