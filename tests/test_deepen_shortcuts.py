"""Old minimal repairs must fail against fresh production bays (dq-82).

The frozen repairs below come from ae87ab3 audit evidence, not current solutions.
Only their convergence waits are bounded by the harness. Native opt-in required.
"""

import json
import os
import secrets
import threading
import time
from pathlib import Path

import pytest

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime

pytestmark = pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1", reason="Explicit local sandbox opt-in required"
)

OLD_FIXES = {
    (85, 0): """kubectl patch pdb relay --type=merge -p '{"spec":{"minAvailable":1}}'
sleep 3
""",
    (77, 0): '''kubectl patch pdb board-budget --type=merge -p '{"spec":{"minAvailable":1}}'
# This is the first precondition of the old supplied evict-one.sh helper.
kubectl get pdb board-budget -o json | jq -e '.status.currentHealthy==2 and .status.disruptionsAllowed==1' >/dev/null
pod=$(kubectl get pods -l app=board -o json | jq -er '[.items[]|select(.metadata.deletionTimestamp==null and any(.status.conditions[]?;.type=="Ready" and .status=="True"))][0].metadata.name')
uid=$(kubectl get pod "$pod" -o jsonpath='{.metadata.uid}')
jq -n --arg pod "$pod" --arg ns "$DQ_NAMESPACE" --arg uid "$uid" '{apiVersion:"policy/v1",kind:"Eviction",metadata:{name:$pod,namespace:$ns},deleteOptions:{preconditions:{uid:$uid},gracePeriodSeconds:15}}' > eviction.json
kubectl create --raw "/api/v1/namespaces/$DQ_NAMESPACE/pods/$pod/eviction" -f eviction.json
''',
    (115, 0): '''kubectl patch service board --type=json -p '[{"op":"replace","path":"/spec/selector","value":{"app":"green"}}]'
''',
    (115, 1): '''kubectl scale deployment blue --replicas=3
kubectl scale deployment green --replicas=1
kubectl rollout status deployment/blue --timeout=90s
kubectl rollout status deployment/green --timeout=90s
''',
    (117, 0): '''python3 - <<'STATIC_FIX'
import yaml
from pathlib import Path
p=Path('static-pod.yaml');v=yaml.safe_load(p.read_text());v['spec']['containers'][0]['command'][-1]=v['spec']['containers'][0]['command'][-1].replace('-p 8099','-p 8080');p.write_text(yaml.safe_dump(v,sort_keys=False))
STATIC_FIX
''',
}


@pytest.mark.parametrize("number,stage", OLD_FIXES)
def test_old_minimal_fix_does_not_complete(number, stage):
    catalog = Catalog()
    runtime = Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": number}
    folder = Path(os.environ.get("DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/deepen-shortcuts"))
    folder.mkdir(parents=True, exist_ok=True)
    log = {"quest": number, "stage": stage, "old_source": "ae87ab3"}
    stop = threading.Event()
    errors = []
    thread = None

    def observe():
        while not stop.wait(2.5):
            try:
                runtime.observe(run)
            except Exception as error:
                errors.append(str(error))

    try:
        runtime.create(run)
        for current in range(stage + 1):
            runtime.exec(run, catalog.script(number, current, "setup"), timeout=240)
            facts = catalog.quests[number].get("immutable", {}).get(current, [])
            if facts:
                runtime.capture_facts(dict(run, stage=current), facts)
            if current < stage:
                runtime.exec(run, (ROOT / f"solutions/{number:03}/{current}.sh").read_text(), timeout=240)
                assert runtime.exec(run, catalog.script(number, current, "check"), check=False, timeout=60).returncode == 0
        check = catalog.script(number, stage, "check")
        initial = runtime.exec(run, check, check=False, timeout=60)
        assert initial.returncode != 0, "Fresh production bay unexpectedly solved"
        if number == 117:
            thread = threading.Thread(target=observe, daemon=True)
            thread.start()
        old = runtime.exec(run, "set -euo pipefail\ncd ~/quest\n" + OLD_FIXES[number, stage], check=False, timeout=180)
        if number == 117:
            # Give the real adapter/kubelet time to consume the repaired source.
            # Its API name is still occupied, so only readiness of a real mirror
            # would change this result; a missing timer tick is not the fault.
            time.sleep(25)
        after = runtime.exec(run, check, check=False, timeout=60)
        assert after.returncode != 0, "Old minimal repair completed the deepened quest"
        if number == 77:
            healthy = runtime.exec(run, "kubectl get pdb board-budget -o jsonpath='{.status.currentHealthy}'").stdout
            assert healthy == "1", "Readiness fault must still be independently observable"
            assert old.returncode != 0, "The old helper must refuse eviction without two healthy replicas"
        if number == 115 and stage == 1:
            assert "[DQ:selector_canary]" in after.stdout
        log.update(initial="FAIL as expected", old_fix_exit=old.returncode,
                   after="FAIL as expected", diagnostics=after.stdout)
    except Exception as error:
        log["error"] = str(error)
        raise
    finally:
        stop.set()
        if thread:
            thread.join(timeout=10)
            assert not thread.is_alive()
        try:
            runtime.teardown(run)
            log["teardown"] = "PASS"
        finally:
            log["observer_errors"] = errors
            (folder / f"{number:03}-{stage}.json").write_text(json.dumps(log, indent=2) + "\n")
        assert not errors, errors
