"""Old minimal repairs must fail against fresh production bays (dq-82).

Initial repairs were frozen at ae87ab3; additions identify their pre-deepening revision.
Repair bodies stay frozen while earlier-stage preparation follows the production lifecycle.
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


# Re-verified against main5d34145 before this batch; only convergence waits are bounded.
OLD_FIXES.update({(66, 0): 'cat > prune.sh <<\'DQ_FROZEN_PRUNE\'\n#!/bin/bash\nset -euo pipefail\ncd ~/quest\nsource platform.env\npython3 - <<\'VALIDATE\'\nimport json,re\nc=json.load(open(\'/run/dq/facts/0/release-catalog.json\'));p=json.load(open(\'retention.json\'))\nassert len(p[\'delete\'])==1\nfor d in p[\'delete\']:\n assert re.fullmatch(r\'sha256:[0-9a-f]{64}\',d)\n assert d==c[\'obsolete\'], \'Refusing to remove an unapproved release\'\nVALIDATE\nwhile read -r digest; do\n curl -fsS --cacert registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" --request DELETE "https://$REGISTRY/v2/parcel/manifests/$digest" >/dev/null\ndone < <(jq -r \'.delete[]\' retention.json)\nDQ_FROZEN_PRUNE\nset -euo pipefail\ncd ~/quest\njq --slurpfile c /run/dq/facts/0/release-catalog.json \'{delete:[$c[0].obsolete]}\' retention.json > corrected-retention.json\nmv corrected-retention.json retention.json\nbash prune.sh\n', (75, 0): 'set -euo pipefail\ncd ~/quest\nsource platform.env\nsource webhook.env\nGITEA_API="${GIT_URL%/rail/station.git}/api/v1/repos/rail/station"\nhook=$(cat /run/dq/facts/0/hook-id)\njq -n --arg url "$(jq -er .url /run/dq/facts/0/webhook-target.json)" --arg secret "$WEBHOOK_SECRET" \'{config:{url:$url,content_type:"json",secret:$secret},events:["push"],branch_filter:"main",active:true}\' > hook-repair.json\ncurl -fsS -u "$GIT_USER:$GIT_PASSWORD" -H \'Content-Type: application/json\' --request PATCH --data-binary @hook-repair.json "$GITEA_API/hooks/$hook" >/dev/null\ncurl -fsS -u "$GIT_USER:$GIT_PASSWORD" --request POST "$GITEA_API/hooks/$hook/tests?ref=refs/heads/main" >/dev/null\nfor i in $(seq 1 90); do\n if kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" \'.status.sync.revision==$rev and .status.sync.status=="Synced" and .status.health.status=="Healthy"\' >/dev/null; then break; fi\n sleep 1\ndone\n', (78, 1): 'set -euo pipefail\ncd ~/quest\nkubectl scale deployment board --replicas=1\nkubectl rollout status deployment/board --timeout=8s\n'})

OLD_REGISTRY_RETENTION_CHECK = 'set -euo pipefail\ncd ~/quest\nfailed=0\nset +e\n(\nset -e\njq -e --slurpfile c /run/dq/facts/0/release-catalog.json \'(.delete|type)=="array" and (.delete|unique)==[$c[0].obsolete]\' retention.json >/dev/null\n)\n[ $? -eq 0 ] || failed=1\n(\nset -e\nsource platform.env\nfor kind in rollback current obsolete; do\n digest=$(jq -er --arg kind "$kind" \'.[$kind]\' /run/dq/facts/0/release-catalog.json)\n code=$(curl -sS --cacert registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" -H \'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json\' -o /dev/null -w \'%{http_code}\' "https://$REGISTRY/v2/parcel/manifests/$digest")\n if test "$kind" = obsolete; then test "$code" = 404; else test "$code" = 200; fi\ndone\n)\n[ $? -eq 0 ] || failed=1\nexit "$failed"\n'


@pytest.mark.parametrize("number,stage", OLD_FIXES)
def test_old_minimal_fix_does_not_complete(number, stage):
    catalog = Catalog()
    runtime = Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": number}
    folder = Path(os.environ.get("DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/deepen-shortcuts"))
    folder.mkdir(parents=True, exist_ok=True)
    log = {"quest": number, "stage": stage, "old_source": "5d34145" if number in {66, 75, 78} else "ae87ab3"}
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
                if number == 78:
                    # Match production polling before advancing the original control stage.
                    runtime.game_controls(run)
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
        if number == 75:
            runtime.observe(run)
        after = runtime.exec(run, check, check=False, timeout=60)
        assert after.returncode != 0, "Old minimal repair completed the deepened quest"
        if number == 77:
            healthy = runtime.exec(run, "kubectl get pdb board-budget -o jsonpath='{.status.currentHealthy}'").stdout
            assert healthy == "1", "Readiness fault must still be independently observable"
            assert old.returncode != 0, "The old helper must refuse eviction without two healthy replicas"
        if number == 115 and stage == 1:
            assert "[DQ:selector_canary]" in after.stdout
        if number == 66:
            assert old.returncode == 0
            runtime.exec(run, OLD_REGISTRY_RETENTION_CHECK, timeout=60)
            assert "[DQ:probe_0_1]" in after.stdout
            log["old_whole_predicates"] = "PASS while surviving alias is wrong"
        if number == 75:
            assert old.returncode == 0
            for index in (0, 3, 6):
                goal = catalog.quests[75]["stages"][0]["objectives"][index]["check"]
                runtime.exec(run, "set -euo pipefail\ncd ~/quest\n" + goal, timeout=25)
            # Real reconciliation completed; the startup cache is independently stale.
            runtime.exec(run, "set -euo pipefail\ncd ~/quest\n" + r"""
approved=$(jq -er .approved.data.notice /run/dq/facts/0/webhook-publication.json)
actual=$(kubectl get configmap board-publication -o jsonpath='{.data.notice}')
test "$actual" = "$approved"
test "$(kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://board:8080)" != "$approved"
""", timeout=25)
            log["source_reconciled_consumer_stale"] = True
        if number == 78:
            assert old.returncode != 0
            runtime.exec(run, r"""
kubectl get events -o json | jq -e 'any(.items[];(.message // "" | test("unauthorized|authentication required|failed to authorize";"i")))' >/dev/null
""", timeout=25)
            log["actual_pull_authorization_denial"] = True


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
