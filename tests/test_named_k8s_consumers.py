"""The supplied application worker, never a decoy default container, supplies the result."""

import json
import os
import subprocess

import pytest
import yaml

from devops_quests.catalog import ROOT


@pytest.mark.parametrize(
    "number,stage,goal,value",
    [
        (7, 0, 0, "north"),
        (14, 0, 2, "north"),
        (17, 0, 3, "retired"),
        (51, 1, 0, "north"),
    ],
)
@pytest.mark.parametrize(
    "default_worker,worker_correct,accepted",
    [(True, True, True), (False, True, True), (False, False, False)],
)
def test_route_getter_reads_the_application_worker(
    tmp_path, number, stage, goal, value, default_worker, worker_correct, accepted
):
    source = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())[
        "stages"
    ][stage]["objectives"][goal]["check"]
    executable = tmp_path / "kubectl"
    executable.write_text("""#!/usr/bin/env python3
import json,os,sys
args=sys.argv[1:]
if args[:2]==['get','pods']:
 print(json.dumps({'items':[{'metadata':{'name':'quarantine-current'},'status':{'phase':'Running'}}]}));sys.exit(0)
assert args[0]=='exec'
worker=('-c' in args and args[args.index('-c')+1]=='worker') or ('-c' not in args and os.environ['DQ_TEST_DEFAULT']=='worker')
correct=os.environ['DQ_TEST_CORRECT']=='yes'
print(os.environ['DQ_TEST_VALUE'] if (worker and correct) or (not worker and not correct) else 'wrong')
""")
    executable.chmod(0o755)
    env = {
        **os.environ,
        "PATH": str(tmp_path) + os.pathsep + os.environ["PATH"],
        "DQ_TEST_DEFAULT": "worker" if default_worker else "decoy",
        "DQ_TEST_CORRECT": "yes" if worker_correct else "no",
        "DQ_TEST_VALUE": value,
    }
    result = subprocess.run(
        ["bash", "-euo", "pipefail", "-c", source],
        env=env,
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert (result.returncode == 0) is accepted


def clock_check(tmp_path, goal, pods, broken=()):
    source = yaml.safe_load((ROOT / "quests/011/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][goal]["check"]
    executable = tmp_path / "kubectl"
    executable.write_text("""#!/usr/bin/env python3
import json,os,sys
args=sys.argv[1:]
if args[:2]==['get','pods']:print(os.environ['DQ_TEST_PODS']);sys.exit(0)
assert args[:2]==['exec','--pod-running-timeout=2s']
assert args[3:6]==['-c','worker','--']
name=args[2];broken=json.loads(os.environ['DQ_TEST_BROKEN'])
if name in broken:print('wrong');sys.exit(0)
print(name if args[-1]=='/tmp/identity' else '2026-11-07T02:00:00Z')
""")
    executable.chmod(0o755)
    env = {
        **os.environ,
        "PATH": str(tmp_path) + os.pathsep + os.environ["PATH"],
        "DQ_TEST_PODS": json.dumps({"items": pods}),
        "DQ_TEST_BROKEN": json.dumps(list(broken)),
    }
    return subprocess.run(
        ["bash", "-euo", "pipefail", "-c", source],
        env=env,
        text=True,
        capture_output=True,
        timeout=5,
    )


def pod(name, deleted=False, phase="Running"):
    return {
        "metadata": {
            "name": name,
            **({"deletionTimestamp": "2026-11-07T00:00:00Z"} if deleted else {}),
        },
        "status": {"phase": phase},
    }


@pytest.mark.parametrize("goal", [1, 2])
def test_clock_checks_every_current_worker_and_ignores_terminating_entries(
    tmp_path, goal
):
    assert clock_check(tmp_path, goal, [pod("clock-a")]).returncode == 0
    current = [pod("old", deleted=True), pod("clock-b"), pod("clock-a")]
    assert clock_check(tmp_path, goal, current, broken=["old"]).returncode == 0
    result = clock_check(tmp_path, goal, current, broken=["clock-a"])
    assert result.returncode != 0 and "pod/clock-a /tmp/" in result.stdout
    assert clock_check(tmp_path, goal, []).returncode != 0
    assert (
        clock_check(tmp_path, goal, [pod("pending", phase="Pending")]).returncode != 0
    )
