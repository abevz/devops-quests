"""Checks do not accept missing static-Pod identities as equal."""

import json
import os
import re
import subprocess

import pytest

from devops_quests.catalog import ROOT, Catalog


@pytest.mark.parametrize(("uid", "hash_value", "accepted"), [("uid-1", "hash-1", True), ("", "hash-1", False), ("uid-1", "", False)])
def test_static_mirror_requires_observed_identity(tmp_path, uid, hash_value, accepted):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    observation = tmp_path / "observation.json"
    observation.write_text(json.dumps({"verified": True, "source": "file", "node": "bay-node", "mirrorUID": uid, "configHash": hash_value}))
    pod = {"metadata": {"uid": uid, "annotations": {"kubernetes.io/config.mirror": hash_value}}, "spec": {"nodeName": "bay-node"}, "status": {"containerStatuses": [{"ready": True}]}}
    binaries = tmp_path / "bin"
    binaries.mkdir()
    kubectl = binaries / "kubectl"
    kubectl.write_text(f'''#!/bin/bash
if [ "$1" = get ]; then cat <<'JSON'
{json.dumps(pod)}
JSON
elif [ "$1" = exec ]; then printf north-117
else exit 1; fi
''')
    kubectl.chmod(0o755)
    source = (ROOT / "quests/117/check-0.sh").read_text().replace("/run/dq/observations/static-pod.json", str(observation))
    environment = {**os.environ, "HOME": str(home), "PATH": f'{binaries}:{os.environ["PATH"]}', "DQ_NODE_NAME": "bay-node"}
    result = subprocess.run(["bash", "-c", source], text=True, capture_output=True, env=environment, timeout=10)
    assert (result.returncode == 0) is accepted, result.stdout + result.stderr
    if not accepted:
        expected_marker = "[DQ:uid]" if not uid else "[DQ:hash]"
        assert expected_marker in result.stdout


@pytest.mark.parametrize(("number", "expected"), [
    (116, {"owner_deployment_board", "owner_configmap_board_route", "owner_service_board", "route", "generation", "station_ready", "label", "ready", "data", "http"}),
    (117, {"verified", "source", "node", "uid", "hash", "pod_node", "ready", "http"}),
])
def test_missing_controller_evidence_reports_localized_conditions(tmp_path, number, expected):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    binaries = tmp_path / "bin"
    binaries.mkdir()
    kubectl = binaries / "kubectl"
    kubectl.write_text("#!/bin/bash\nexit 1\n")
    kubectl.chmod(0o755)
    source = (ROOT / f"quests/{number}/check-0.sh").read_text().replace("/run/dq/observations/static-pod.json", str(tmp_path / "missing.json"))
    environment = {**os.environ, "HOME": str(home), "PATH": f'{binaries}:{os.environ["PATH"]}', "DQ_NODE_NAME": "test", "DQ_NAMESPACE": "test"}
    result = subprocess.run(["bash", "-c", source], text=True, capture_output=True, env=environment, timeout=15)
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
    assert result.returncode != 0
    assert len(markers) == len(result.stdout.splitlines())
    assert set(markers) == expected
    diagnostics = Catalog().public(number)["diagnostics"]
    for marker in markers:
        assert set(diagnostics[marker]) >= {"en", "pl", "es", "de", "ru"}
