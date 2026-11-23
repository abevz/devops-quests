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
    checks = [goal["check"] for goal in catalog.quests[number]["stages"][stage]["objectives"]]
    prelude = "set -euo pipefail\ncd ~/quest\n"
    if len(checks) == 1:
        assert source == prelude + checks[0].removeprefix(prelude).rstrip("\n") + "\n"
    else:
        expected = prelude + "failed=0\nset +e\n"
        for check in checks:
            expected += "(\nset -e\n" + check + "\n)\n[ $? -eq 0 ] || failed=1\n"
        expected += 'exit "$failed"\n'
        assert source == expected
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
    ("number", "stage", "objective", "marker"),
    [
        (99, 0, 0, "incident_head"),
        (99, 0, 1, "incident_source"),
        (99, 0, 2, "incident_sync"),
        (99, 0, 6, "incident_token"),
        (99, 0, 7, "incident_revoked"),
        (100, 0, 0, "probe_0_0"),
        (100, 1, 0, "probe_1_0"),
        (100, 1, 2, "probe_1_2"),
        (100, 1, 4, "probe_1_4"),
        (100, 1, 5, "probe_1_5"),
        (100, 1, 7, "probe_1_7"),
    ],
)
def test_recovery_platform_failure_retains_status_and_reports_one_marker(
    tmp_path, catalog, number, stage, objective, marker
):
    quest = tmp_path / "quest"
    quest.mkdir()
    (quest / "platform.env").write_text("echo 'platform input failure' >&2\nreturn 42\n")
    goal = catalog.quests[number]["stages"][stage]["objectives"][objective]
    result = subprocess.run(
        ["bash", "-c", "set -euo pipefail\ncd ~/quest\n" + goal["check"]],
        env={**os.environ, "HOME": str(tmp_path), "TMPDIR": str(tmp_path)},
        capture_output=True, text=True, timeout=10,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 42, output
    assert "platform input failure" in output
    assert re.findall(r"\[DQ:([a-z0-9_]+)\]", output) == [marker]
    assert list(tmp_path.iterdir()) == [quest]


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
