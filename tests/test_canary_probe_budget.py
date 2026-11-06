"""The real canary objective checks every IP with bounded pressure and honest expiry."""

import json
import os
import re
from pathlib import Path
import subprocess
import time

import yaml

ROOT = Path(__file__).resolve().parents[1]


def run_probe(tmp_path, per_version, delay):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    binaries = tmp_path / "bin"
    binaries.mkdir()
    targets = {
        "blue": [f"10.0.0.{i}" for i in range(1, per_version + 1)],
        "green": [f"10.0.1.{i}" for i in range(1, per_version + 1)],
    }
    config = tmp_path / "config.json"
    config.write_text(json.dumps({"targets": targets, "delay": delay}))
    state = tmp_path / "state.json"
    state.write_text(json.dumps({"active": 0, "maximum": 0, "seen": []}))
    program = binaries / "kubectl"
    program.write_text("""#!/usr/bin/env python3
import fcntl,json,os,sys,time
from pathlib import Path
config=json.loads(Path(os.environ['PROBE_CONFIG']).read_text())
state=Path(os.environ['PROBE_STATE'])
args=sys.argv[1:]
if args[:2]==['get','pods']:
    version=args[args.index('-l')+1].split('=')[1]
    print(' '.join(config['targets'][version]))
    raise SystemExit(0)
url=args[-1]
if url=='http://board:8080':
    print('blue-115')
    raise SystemExit(0)
ip=url.split('//')[1].split(':')[0]
version=next(v for v,ips in config['targets'].items() if ip in ips)
def update(delta):
    with state.open('r+') as stream:
        fcntl.flock(stream,fcntl.LOCK_EX)
        value=json.load(stream)
        value['active']+=delta
        value['maximum']=max(value['maximum'],value['active'])
        if delta>0:value['seen'].append(ip)
        stream.seek(0);json.dump(value,stream);stream.truncate()
update(1)
try:
    time.sleep(config['delay'])
    print(version+'-115')
finally:update(-1)
""")
    program.chmod(0o755)
    quest = yaml.safe_load((ROOT / "quests/115/quest.yaml").read_text())
    check = next(
        goal["check"] for goal in quest["stages"][1]["objectives"]
        if "[DQ:probe_budget]" in goal["check"]
    )
    started = time.monotonic()
    result = subprocess.run(
        ["bash", "-c", check], text=True, capture_output=True, timeout=24,
        env={**os.environ, "HOME": str(home), "PATH": f"{binaries}:{os.environ['PATH']}",
             "PROBE_CONFIG": str(config), "PROBE_STATE": str(state)},
    )
    return result, json.loads(state.read_text()), targets, time.monotonic() - started


def test_canary_checks_all_ips_with_at_most_two_concurrent_probes(tmp_path):
    result, state, targets, _ = run_probe(tmp_path, 3, 0.1)
    assert result.returncode == 0, result.stdout + result.stderr
    assert state["maximum"] == 2
    assert state["active"] == 0
    assert sorted(state["seen"]) == sorted(sum(targets.values(), []))
    assert not result.stdout


def test_budget_reports_unchecked_ips_without_claiming_their_responses_failed(tmp_path):
    result, state, targets, elapsed = run_probe(tmp_path, 24, 0.9)
    assert result.returncode == 1, result.stdout + result.stderr
    assert state["maximum"] == 2
    assert state["active"] == 0
    unchecked = set(sum(targets.values(), [])) - set(state["seen"])
    assert unchecked
    assert "[DQ:probe_budget]" in result.stdout
    budget_line = next(line for line in result.stdout.splitlines() if "[DQ:probe_budget]" in line)
    assert set(re.findall(r"\b10\.0\.[01]\.\d+\b", budget_line)) == unchecked
    assert "[DQ:pod_blue]" not in result.stdout
    assert "[DQ:pod_green]" not in result.stdout
    assert "[DQ:canary_http]" not in result.stdout
    assert elapsed < 24
