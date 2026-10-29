"""Earlier workload probes expose a localized message for every failure."""

import os
import re
import subprocess

import pytest

from devops_quests.catalog import ROOT, Catalog


@pytest.mark.parametrize(("number", "stage", "expected"), [(101, 0, 12), (102, 0, 8), (102, 1, 8), (103, 0, 17)])
def test_workload_failures_have_translated_markers(tmp_path, number, stage, expected):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    facts = tmp_path / "facts"
    facts.mkdir()
    binaries = tmp_path / "bin"
    binaries.mkdir()
    kubectl = binaries / "kubectl"
    kubectl.write_text("#!/bin/bash\nexit 1\n")
    kubectl.chmod(0o755)
    source = (ROOT / f"quests/{number}/check-{stage}.sh").read_text().replace("/run/dq/facts/0", str(facts))
    environment = {**os.environ, "HOME": str(home), "PATH": f'{binaries}:{os.environ["PATH"]}', "DQ_NODE_NAME": "test", "DQ_NAMESPACE": "test"}
    result = subprocess.run(["bash", "-c", source], text=True, capture_output=True, env=environment, timeout=15)
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
    assert result.returncode != 0
    assert len(markers) == len(result.stdout.splitlines()) == expected, result.stdout + result.stderr
    assert len(result.stdout) <= 2000
    diagnostics = Catalog().public(number)["diagnostics"]
    for marker in markers:
        assert set(diagnostics[marker]) >= {"en", "pl", "es", "de", "ru"}
