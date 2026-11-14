"""Execute the shipped shell guards so an early failure cannot be masked later."""

import json
import os
import subprocess

import pytest
import yaml

from devops_quests.catalog import ROOT


@pytest.mark.parametrize("case", ["good", "unhealthy_budget", "unready_pool", "wrong_http"])
def test_each_health_failure_survives_later_success(tmp_path, case):
    kubectl = tmp_path / "kubectl"
    kubectl.write_text('''#!/usr/bin/env python3
import json,os,sys
case=os.environ['CASE'];args=sys.argv[1:]
if args[:3]==['get','pdb','relay']:
 print(json.dumps({'status':{'currentHealthy':1 if case=='unhealthy_budget' else 2}}))
elif args[:2]==['get','deployment']:
 print(json.dumps({'items':[{'metadata':{'generation':1},'spec':{'replicas':2},'status':{'readyReplicas':1 if case=='unready_pool' else 2,'observedGeneration':1}}]}))
elif args[0]=='exec':
 print('wrong' if case=='wrong_http' else args[-1].split('//')[1].split(':')[0]+'-85')
else:raise SystemExit(3)
''')
    kubectl.chmod(0o755)
    quest = yaml.safe_load((ROOT / "quests/085/quest.yaml").read_text())
    result = subprocess.run(
        ["bash", "-c", quest["stages"][0]["objectives"][1]["check"]],
        capture_output=True, text=True, timeout=10,
        env={**os.environ, "PATH": str(tmp_path) + os.pathsep + os.environ["PATH"], "CASE": case},
    )
    assert (result.returncode == 0) is (case == "good"), result.stdout + result.stderr
    if case != "good":
        assert "[DQ:maintenance_health]" in result.stdout


def test_original_blocked_allowance_has_specific_diagnostic(tmp_path):
    kubectl = tmp_path / "kubectl"
    kubectl.write_text("#!/bin/sh\nprintf '%s\\n' " + "'" + json.dumps({"status": {"disruptionsAllowed": 0}}) + "'\n")
    kubectl.chmod(0o755)
    quest = yaml.safe_load((ROOT / "quests/085/quest.yaml").read_text())
    result = subprocess.run(
        ["bash", "-c", quest["stages"][0]["objectives"][2]["check"]],
        capture_output=True, text=True, timeout=10,
        env={**os.environ, "PATH": str(tmp_path) + os.pathsep + os.environ["PATH"]},
    )
    assert result.returncode != 0
    assert "[DQ:maintenance_allowance]" in result.stdout
