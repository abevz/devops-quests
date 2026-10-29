"""Failure diagnostics identify the GitOps or registry condition in five languages."""

import os
import re
import subprocess
import pytest
from devops_quests.catalog import ROOT, Catalog


@pytest.mark.parametrize(
    ("number", "stage"), [(42, 0), (80, 0), (80, 1), (122, 0), (123, 0)]
)
def test_missing_inputs_emit_localized_failure_lines(tmp_path, number, stage):
    home = tmp_path / "home"
    quest = home / "quest"
    quest.mkdir(parents=True)
    (quest / "platform.env").write_text(
        "export PRIVATE_IMAGE=image REGISTRY=registry REGISTRY_USER=user REGISTRY_PASSWORD=password GIT_URL=repo\n"
    )
    facts = tmp_path / "facts"
    facts.mkdir()
    binaries = tmp_path / "bin"
    binaries.mkdir()
    for name in ("kubectl", "git", "curl"):
        fake = binaries / name
        fake.write_text("#!/bin/bash\nexit 1\n")
        fake.chmod(0o755)
    source = (
        (ROOT / f"quests/{number:03}/check-{stage}.sh")
        .read_text()
        .replace("/run/dq/facts/0", str(facts))
    )
    env = {
        **os.environ,
        "HOME": str(home),
        "PATH": f"{binaries}:{os.environ['PATH']}",
        "DQ_NAMESPACE": "test",
    }
    result = subprocess.run(
        ["bash", "-c", source], text=True, capture_output=True, env=env, timeout=20
    )
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
    assert result.returncode != 0
    assert markers and len(markers) == len(result.stdout.splitlines()), (
        result.stdout + result.stderr
    )
    assert len(result.stdout.encode()) <= 2000, (
        number,
        len(result.stdout.encode()),
        result.stdout,
    )
    diagnostics = Catalog().public(number)["diagnostics"]
    for marker in markers:
        assert set(diagnostics[marker]) >= {"en", "pl", "es", "de", "ru"}, marker
