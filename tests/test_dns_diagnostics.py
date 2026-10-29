"""Every failed DNS/network condition has a message in each language."""

import os
import re
import subprocess
import pytest
from devops_quests.catalog import ROOT, Catalog


@pytest.mark.parametrize(
    ("number", "stage"),
    [(105, 0), (106, 0), (107, 0), (110, 0), (110, 1), (113, 0), (118, 0)],
)
def test_missing_resources_report_localized_diagnostics(tmp_path, number, stage):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    facts = tmp_path / "facts"
    facts.mkdir()
    binaries = tmp_path / "bin"
    binaries.mkdir()
    fake = binaries / "kubectl"
    fake.write_text("#!/bin/bash\nexit 1\n")
    fake.chmod(0o755)
    source = (
        (ROOT / f"quests/{number}/check-{stage}.sh")
        .read_text()
        .replace("/run/dq/facts/0", str(facts))
    )
    env = {
        **os.environ,
        "HOME": str(home),
        "PATH": f"{binaries}:{os.environ['PATH']}",
        "DQ_NAMESPACE": "test",
        "DQ_NODE_NAME": "test",
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
