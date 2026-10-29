"""Workflow and scheduling failures have translated condition messages."""

import os
import re
import subprocess

import pytest

from devops_quests.catalog import Catalog, ROOT


@pytest.fixture(scope="module")
def catalog():
    return Catalog()


@pytest.mark.parametrize(
    ("number", "stage"), [(41, 0), (72, 0), (100, 0), (100, 1), (104, 0), (121, 0)]
)
def test_missing_resources_report_localized_conditions(
    tmp_path, catalog, number, stage
):
    home = tmp_path / "home"
    quest = home / "quest"
    quest.mkdir(parents=True)
    (quest / "platform.env").write_text(
        "export GIT_URL=unused VAULT_ADDR=http://unused VAULT_READER_TOKEN=synthetic\n"
    )
    binaries = tmp_path / "bin"
    binaries.mkdir()
    for name in ("kubectl", "git", "curl"):
        binary = binaries / name
        binary.write_text("#!/bin/sh\nexit 1\n")
        binary.chmod(0o755)
    source = (ROOT / f"quests/{number:03}/check-{stage}.sh").read_text()
    assert source == catalog.quests[number]["stages"][stage]["objectives"][0]["check"]
    source = source.replace("/run/dq/facts/0", str(tmp_path / "missing-facts"))
    env = {
        **os.environ,
        "HOME": str(home),
        "PATH": f"{binaries}:{os.environ['PATH']}",
        "DQ_NAMESPACE": "dq-test",
    }
    result = subprocess.run(
        ["bash", "-c", source], text=True, capture_output=True, env=env, timeout=20
    )
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
    assert result.returncode != 0
    assert markers and len(markers) == len(result.stdout.splitlines()), (
        result.stdout + result.stderr
    )
    assert len(result.stdout) <= 2000, (
        number,
        stage,
        len(result.stdout),
        result.stdout,
    )
    for marker in markers:
        assert set(catalog.public(number)["diagnostics"][marker]) >= {
            "en",
            "pl",
            "es",
            "de",
            "ru",
        }


@pytest.mark.parametrize(
    ("case", "expected"),
    [("allow", "denial"), ("wrong_message", "denial_text"), ("proper_denial", None)],
)
def test_webhook_dry_run_denial_diagnostics(tmp_path, catalog, case, expected):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    binaries = tmp_path / "bin"
    binaries.mkdir()
    kubectl = binaries / "kubectl"
    kubectl.write_text(
        "#!/usr/bin/python3\n"
        "import json,os,sys\n"
        "args=sys.argv[1:]\n"
        'if args[:3]==["get","configmap","route"]:\n'
        '    print(json.dumps({"data":{"route":"north-121"}})); sys.exit(0)\n'
        'if args[:2]==["apply","--dry-run=server"]:\n'
        '    route=json.load(open(args[-1]))["data"]["route"]\n'
        '    if route != "closed": sys.exit(0)\n'
        '    if os.environ["DENIAL_CASE"]=="allow": sys.exit(0)\n'
        '    print("Station route must be north-121" if os.environ["DENIAL_CASE"]=="proper_denial" else "wrong denial",file=sys.stderr); sys.exit(1)\n'
        "sys.exit(1)\n"
    )
    kubectl.chmod(0o755)
    source = (ROOT / "quests/121/check-0.sh").read_text()
    env = {
        **os.environ,
        "HOME": str(home),
        "PATH": f"{binaries}:{os.environ['PATH']}",
        "DQ_NAMESPACE": "dq-test",
        "DENIAL_CASE": case,
    }
    result = subprocess.run(
        ["bash", "-c", source], text=True, capture_output=True, env=env, timeout=20
    )
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
    if expected is None:
        assert "denial" not in markers and "denial_text" not in markers
    else:
        assert expected in markers, result.stdout + result.stderr
        assert set(catalog.public(121)["diagnostics"][expected]) >= {
            "en",
            "pl",
            "es",
            "de",
            "ru",
        }
