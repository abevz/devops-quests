"""Fleet content cannot impersonate its separately checked file mode."""

import os
import re
import subprocess

import pytest

from devops_quests.catalog import ROOT, Catalog


@pytest.fixture(scope="module")
def catalog():
    return Catalog()


@pytest.mark.parametrize(
    ("number", "stage", "expected"),
    [(81, 1, "release-81"), (90, 1, "release-90"), (98, 0, "north-98")],
)
@pytest.mark.parametrize(
    ("suffix", "mode", "content_fails", "mode_fails"),
    [
        (b"\n644", 0o600, True, True),
        (b"\n644", 0o644, True, False),
        (b"\n", 0o600, False, True),
        (b"\n", 0o644, False, False),
        (b"", 0o644, False, False),
        (b"\n\n", 0o644, True, False),
        (b"\0", 0o644, True, False),
    ],
)
def test_fleet_checks_separate_actual_content_and_mode(
    tmp_path, catalog, number, stage, expected, suffix, mode, content_fails, mode_fails
):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    message = tmp_path / "message"
    message.write_bytes(expected.encode() + suffix)
    message.chmod(mode)
    binaries = tmp_path / "bin"
    binaries.mkdir()
    ssh = binaries / "ssh"
    ssh.write_text(
        "#!/usr/bin/python3\nimport os,subprocess,sys\ncommand=sys.argv[-1].replace('/srv/site/message',os.environ['TEST_MESSAGE'])\nsys.exit(subprocess.run(command,shell=True).returncode)\n"
    )
    ssh.chmod(0o755)
    curl = binaries / "curl"
    curl.write_text('#!/bin/sh\nprintf "%s" "$TEST_VALUE"\n')
    curl.chmod(0o755)
    for name in ("tofu", "kubectl"):
        binary = binaries / name
        binary.write_text("#!/bin/sh\nexit 1\n")
        binary.chmod(0o755)
    environment = {
        **os.environ,
        "HOME": str(home),
        "PATH": f"{binaries}:{os.environ['PATH']}",
        "DQ_NAMESPACE": "dq-test",
        "TEST_MESSAGE": str(message),
        "TEST_VALUE": expected,
    }
    source = (ROOT / f"quests/{number:03}/check-{stage}.sh").read_text()
    assert source == catalog.quests[number]["stages"][stage]["objectives"][0]["check"]
    result = subprocess.run(
        ["bash", "-c", source],
        text=True,
        capture_output=True,
        env=environment,
        timeout=20,
    )
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
    if number != 98:
        assert (result.returncode != 0) == (content_fails or mode_fails)
    for host in (1, 2, 3):
        assert (f"content_{host}" in markers) is content_fails, result.stdout
        assert (f"mode_{host}" in markers) is mode_fails, result.stdout
        assert f"http_{host}" not in markers, result.stdout
    diagnostics = catalog.public(number)["diagnostics"]
    for marker in markers:
        assert set(diagnostics[marker]) >= {"en", "pl", "es", "de", "ru"}, marker


@pytest.mark.parametrize(
    ("number", "stage", "expected_count"),
    [(81, 0, 3), (81, 2, 2), (90, 0, 3), (90, 2, 2), (98, 0, 19)],
)
def test_failed_conditions_have_translations(
    tmp_path, catalog, number, stage, expected_count
):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    binaries = tmp_path / "bin"
    binaries.mkdir()
    for name in ("ssh", "curl", "kubectl", "tofu"):
        binary = binaries / name
        binary.write_text("#!/bin/sh\nexit 1\n")
        binary.chmod(0o755)
    source = (ROOT / f"quests/{number:03}/check-{stage}.sh").read_text()
    assert source == catalog.quests[number]["stages"][stage]["objectives"][0]["check"]
    environment = {
        **os.environ,
        "HOME": str(home),
        "PATH": f"{binaries}:{os.environ['PATH']}",
        "DQ_NAMESPACE": "dq-test",
    }
    result = subprocess.run(
        ["bash", "-c", source],
        text=True,
        capture_output=True,
        env=environment,
        timeout=20,
    )
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
    assert result.returncode != 0
    assert len(markers) == len(result.stdout.splitlines()) == expected_count, (
        result.stdout + result.stderr
    )
    for marker in markers:
        assert set(catalog.public(number)["diagnostics"][marker]) >= {
            "en",
            "pl",
            "es",
            "de",
            "ru",
        }
