"""Every scaling and routing condition reports its own localized marker."""

import json
import os
import re
import subprocess

import pytest

from devops_quests.catalog import ROOT, Catalog


@pytest.mark.parametrize(("number", "stage", "expected"), [
    (112, 0, {"request", "limit", "ready", "minimum", "maximum", "target", "current", "desired", "metric", "active", "top", "http"}),
    (130, 0, {"request", "limit", "ready", "minimum", "maximum", "target", "current", "desired", "metric"}),
    (130, 1, {"request", "limit", "ready", "minimum", "maximum", "target", "current", "desired", "metric", "gateway_class", "gateway_accepted", "backend", "resolved", "policy", "gateway_http"}),
])
def test_scaling_failures_have_localized_markers(tmp_path, number, stage, expected):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    facts = tmp_path / "facts"
    facts.mkdir()
    (facts / "gateway-target.json").write_text(json.dumps({"url": "http://private.invalid", "class": "private", "namespace": "gateway"}))
    binaries = tmp_path / "bin"
    binaries.mkdir()
    kubectl = binaries / "kubectl"
    kubectl.write_text("#!/bin/bash\nexit 1\n")
    kubectl.chmod(0o755)
    source = (ROOT / f"quests/{number}/check-{stage}.sh").read_text().replace("/run/dq/facts/0", str(facts))
    environment = {**os.environ, "HOME": str(home), "PATH": f'{binaries}:{os.environ["PATH"]}', "DQ_NAMESPACE": "test"}
    result = subprocess.run(["bash", "-c", source], env=environment, text=True, capture_output=True, timeout=15)
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
    assert result.returncode != 0
    assert len(markers) == len(result.stdout.splitlines())
    assert set(markers) == expected
    assert len(result.stdout) <= 2000
    diagnostics = Catalog().public(number)["diagnostics"]
    for marker in markers:
        assert set(diagnostics[marker]) >= {"en", "pl", "es", "de", "ru"}


def test_incident_reports_each_unexpectedly_successful_negative_probe(tmp_path):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    facts = tmp_path / "facts"
    facts.mkdir()
    (facts / "gateway-target.json").write_text(json.dumps({"url": "http://private.invalid", "class": "private", "namespace": "gateway"}))
    binaries = tmp_path / "bin"
    binaries.mkdir()
    kubectl = binaries / "kubectl"
    kubectl.write_text('''#!/bin/bash
if [[ "$*" == *http://board:8080* || "$*" == *closed.station.internal* ]]; then exit 0; fi
exit 1
''')
    kubectl.chmod(0o755)
    source = (ROOT / "quests/130/check-1.sh").read_text().replace("/run/dq/facts/0", str(facts))
    environment = {**os.environ, "HOME": str(home), "PATH": f'{binaries}:{os.environ["PATH"]}', "DQ_NAMESPACE": "test"}
    result = subprocess.run(["bash", "-c", source], env=environment, text=True, capture_output=True, timeout=15)
    assert "[DQ:direct_denied]" in result.stdout
    assert "[DQ:wrong_host]" in result.stdout
