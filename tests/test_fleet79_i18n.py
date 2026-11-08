"""Fleet playbook and live-host failures expose translated diagnostics."""

import os
import re
import subprocess

import pytest
import yaml

from devops_quests.catalog import Catalog, ROOT


@pytest.fixture(scope="module")
def catalog():
    return Catalog()


def write_remote_transport(binaries):
    """Execute the actual inline SSH payload; map file arguments, not diagnostics."""
    ssh = binaries / "ssh"
    ssh.write_text(
        "#!/usr/bin/python3\n"
        "import os,subprocess,sys\n"
        "host=next(arg for arg in sys.argv[1:] if arg.startswith('root@app')).split('@',1)[1].split('-',1)[0]\n"
        "selected=os.environ.get('ONLY_HOST')\n"
        "if selected and host != selected: sys.exit(0)\n"
        "sys.exit(subprocess.run(['bash','-c',sys.argv[-1]],env=dict(os.environ,HOST=host)).returncode)\n"
    )
    ssh.chmod(0o755)
    for command in ("cat", "stat"):
        binary = binaries / command
        binary.write_text(
            "#!/usr/bin/python3\nimport os,sys\n"
            "args=[os.environ['MISSING_SITE']+a[len('/srv/site'):] if a=='/srv/site' or a.startswith('/srv/site/') else a for a in sys.argv[1:]]\n"
            f"os.execv('/usr/bin/{command}',['/usr/bin/{command}',*args])\n"
        )
        binary.chmod(0o755)


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




@pytest.mark.parametrize("host", [1, 2, 3])
def test_remote_file_failures_include_host_identity(tmp_path, catalog, host):
    (tmp_path / "quest").mkdir()
    binaries = tmp_path / "bin"
    binaries.mkdir()
    write_remote_transport(binaries)
    checks = [
        goal["check"]
        for goal in catalog.quests[79]["stages"][0]["objectives"]
        if re.search(r"\bssh\b", goal["check"])
    ]
    assert checks, "The fleet's remote conditions must be exercised"
    env = {
        **os.environ,
        "HOME": str(tmp_path),
        "PATH": f"{binaries}:{os.environ['PATH']}",
        "DQ_NAMESPACE": "dq-test",
        "ONLY_HOST": f"app{host}",
        "MISSING_SITE": str(tmp_path / "missing"),
    }
    output = []
    for check in checks:
        result = subprocess.run(
            ["bash", "-c", "set -euo pipefail\ncd ~/quest\n" + check],
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode != 0
        output.append(result.stdout)
    markers = check_markers(catalog, "".join(output))
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
    write_remote_transport(binaries)
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
