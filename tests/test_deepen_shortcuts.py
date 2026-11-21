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
    # Frozen at b235ecb. The reference applied the supplied configuration as-is.
    (30, 0): 'tofu apply -auto-approve -input=false -no-color\n',
    (30, 1): '''kubectl set env deployment/relay RELEASE=release-30
kubectl rollout status deployment/relay --timeout=90s
''',
    # Equivalent replay of the two content-only repairs at ec6cef5:
    # the original policy and workload manifests remain unchanged at setup.
    (40, 0): """sed -i "s/content: 'retired/content: 'north-40/" rollout.yml
ansible-playbook rollout.yml
""",
    (40, 1): """sed -i 's/"retired"/"north-40"/' board.yaml
kubectl apply -f board.yaml
kubectl rollout status deployment/board --timeout=90s
retiring=$(kubectl get pods -l app=board -o json | jq -r '.items[] | select(.metadata.deletionTimestamp!=null) | "pod/"+.metadata.name')
if test -n "$retiring"; then
  mapfile -t pods <<< "$retiring"
  kubectl wait --for=delete "${pods[@]}" --timeout=60s
fi
kubectl wait --for='jsonpath={.status.availableReplicas}=2' deployment/board --timeout=45s
""",
    # Copy and reload-on-change from the source at ba6d23b.
    (60, 0): """cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail rollout
  hosts: fleet
  gather_facts: false
  handlers:
  - name: Reload banner
    ansible.builtin.command: dq-service reload
  tasks:
  - name: Deliver the route message
    ansible.builtin.copy:
      dest: /srv/site/message
      content: |
        release-60
      mode: '0644'
    notify: Reload banner
DQ_ASSET
ansible-playbook rollout.yml
""",
    (60, 1): """kubectl set env deployment/relay RELEASE=release-60
kubectl rollout status deployment/relay --timeout=90s
""",
    # Frozen behavior from 5bdcc1f: rebuild, publish the literal, set the literal.
    (90, 0): 'tofu apply -auto-approve -input=false -no-color\n',
    (90, 1): """cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail rollout
  hosts: fleet
  gather_facts: false
  handlers:
  - name: Reload banner
    ansible.builtin.command: dq-service reload
  tasks:
  - name: Deliver the route message
    ansible.builtin.copy:
      dest: /srv/site/message
      content: |
        release-90
      mode: '0644'
    notify: Reload banner
DQ_ASSET
ansible-playbook rollout.yml
""",
    (90, 2): """kubectl set env deployment/relay RELEASE=release-90
kubectl rollout status deployment/relay --timeout=90s
""",
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


# Frozen at 7f37b34. The harness separately waits for the effect of the old edit.
OLD_FIXES.update({
    (122, 0): """python3 - <<'REPAIR_YAML'
from pathlib import Path
import yaml
p=Path('repository/apps/child.yaml'); d=yaml.safe_load(p.read_text()); d['spec']['source']['path']='manifests'; p.write_text(yaml.safe_dump(d,sort_keys=False))
REPAIR_YAML
git -C repository add apps/child.yaml
git -C repository commit -m 'Restore child source path'
git -C repository push origin main
kubectl annotate application parent argocd.argoproj.io/refresh=hard --overwrite
""",
    (123, 0): """python3 - <<'REPAIR_YAML'
from pathlib import Path
import yaml
p=Path('applicationset.yaml'); d=yaml.safe_load(p.read_text()); d['spec']['template']['spec']['source']['path']='stations/{{.station}}'; p.write_text(yaml.safe_dump(d,sort_keys=False))
REPAIR_YAML
""",
})


LEGACY_GITOPS_EFFECT = {
    122: r"""
bash wait-apps.sh
test "$(kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://board:8080)" = north-122
actual=$(kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://board:8080/publication/revision)
test -n "$actual"
test "$actual" != "$(cat /run/dq/facts/0/approved-publication)"
""",
    123: r"""
ns=$(jq -er .namespace /run/dq/facts/0/appset-target.json)
maintenance=$(cat /run/dq/facts/0/maintenance-commit)
kubectl -n "$ns" get applications north south -o json |
  jq -e --arg rev "$maintenance" '(.items|length)==2 and all(.items[];
     .status.sync.status=="Synced" and .status.health.status=="Healthy"
     and .status.sync.revision==$rev and .spec.source.targetRevision=="main")' >/dev/null
for station in north south; do
  test "$(kubectl exec "deployment/$station" -c worker -- wget -qO- -T 3 "http://$station:8080")" = "$station-123"
done
""",
}


def wait_for_old_gitops_effect(runtime, run, number):
    deadline = time.monotonic() + 100
    script = "set -euo pipefail\ncd ~/quest\n" + LEGACY_GITOPS_EFFECT[number]
    while time.monotonic() < deadline:
        result = runtime.exec(run, script, check=False, timeout=20)
        if result.returncode == 0:
            return
        time.sleep(2)
    pytest.fail(f"Old GitOps repair did not converge: {result.stdout}{result.stderr}")


@pytest.mark.parametrize("number,stage", OLD_FIXES)
def test_old_minimal_fix_does_not_complete(number, stage):
    catalog = Catalog()
    runtime = Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": number}
    folder = Path(os.environ.get("DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/deepen-shortcuts"))
    folder.mkdir(parents=True, exist_ok=True)
    log = {"quest": number, "stage": stage, "old_source": "5d34145" if number in {66, 75, 78} else "ae87ab3"}
    if number == 30:
        log["old_source"] = "b235ecb"
    if number == 40:
        log["old_source"] = "ec6cef5"
    if number == 60:
        log["old_source"] = "ba6d23b"
    if number == 90:
        log["old_source"] = "5bdcc1f"
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
            setup = catalog.script(number, current, "setup")
            if number == 30:
                # Engine runs stage setup from the quest directory.
                setup = "set -euo pipefail\ncd ~/quest\n" + setup
            runtime.exec(run, setup, timeout=240)
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
        if number == 123:
            runtime.game_controls(run)
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
        if number in LEGACY_GITOPS_EFFECT:
            assert old.returncode == 0, old.stdout + old.stderr
            if number == 123:
                runtime.game_controls(run)
            wait_for_old_gitops_effect(runtime, run, number)
        after = runtime.exec(run, check, check=False, timeout=60)
        assert after.returncode != 0, "Old minimal repair completed the deepened quest"
        if number == 30:
            assert old.returncode == 0, old.stdout + old.stderr
            marker = "release_content" if stage == 0 else "service_http"
            assert len(after.stdout.splitlines()) == 1 and f"[DQ:{marker}]" in after.stdout
            if stage == 1:
                runtime.exec(run, """
test "$(kubectl exec deployment/relay -c worker -- wget -qO- -T 3 http://127.0.0.1:8080/)" = signalrail
""", timeout=15)
            log["old_repair_converged_with_failure"] = marker
        if number == 40:
            assert old.returncode == 0, old.stdout + old.stderr
            marker = "fleet_http" if stage == 0 else "readiness_probe"
            detail = after.stdout + after.stderr
            failures = [line for line in detail.splitlines() if "[DQ:" in line]
            assert len(failures) == 1 and f"[DQ:{marker}]" in failures[0], detail
            if stage == 1:
                missing = runtime.exec(
                    run, "kubectl exec deployment/board -c worker -- wget -qO- -T 2 http://127.0.0.1:8080/ready",
                    check=False, timeout=10,
                )
                assert missing.returncode != 0
            log["old_repair_converged_with_failure"] = marker
            log["old_repair_diagnostics"] = failures
        if number == 60:
            assert old.returncode == 0, old.stdout + old.stderr
            marker = "http_2" if stage == 0 else "release_source"
            detail = after.stdout + after.stderr
            failures = [line for line in detail.splitlines() if "[DQ:" in line]
            assert len(failures) == 1 and f"[DQ:{marker}]" in failures[0], detail
            if stage == 0:
                runtime.exec(run, "set -euo pipefail\ncd ~/quest\n" + r"""
for host in app2 app3; do
    peer="$host-${DQ_NAMESPACE#dq-}"
    ssh -n -o BatchMode=yes -p 2222 "root@$peer" 'dq-service reload'
    deadline=$((SECONDS+10))
    until test "$(curl -fsS --max-time 2 "http://$peer:8080/" 2>/dev/null)" = release-60; do
        [ "$SECONDS" -lt "$deadline" ] || exit 1
        sleep 0.2
    done
done
""", timeout=25)
                restarted = runtime.exec(run, check, check=False, timeout=25)
                assert restarted.returncode != 0 and "[DQ:healthy_service]" in restarted.stderr
            else:
                runtime.exec(run, """kubectl patch configmap relay-release --type=merge -p '{"data":{"revision":"release-60"}}'""")
                bypass = runtime.exec(run, check, check=False, timeout=25)
                assert bypass.returncode != 0 and "[DQ:release_source]" in bypass.stdout
            log["old_repair_converged_with_failure"] = marker
            log["old_repair_diagnostics"] = failures
        if number == 90:
            assert old.returncode == 0, old.stdout + old.stderr
            expected = {
                0: {"[DQ:checkpoint_binding]"},
                1: {f"[DQ:fleet_identity_{host}]" for host in (1, 2, 3)},
                2: {"[DQ:relay_publication]"},
            }[stage]
            detail = after.stdout + after.stderr
            failures = {line[line.index("[DQ:"):] for line in detail.splitlines() if "[DQ:" in line}
            assert failures == expected, detail
            if stage == 0:
                # A wholesale replacement restores the old release binding
                # but erases the newer handover binding in this disposable bay.
                runtime.exec(run, "cd ~/quest\ncp recovery/checkpoint.tfstate terraform.tfstate")
                goal = catalog.quests[90]["stages"][0]["objectives"][0]["check"]
                wholesale = runtime.exec(run, "set -euo pipefail\ncd ~/quest\n" + goal, check=False, timeout=25)
                assert wholesale.returncode != 0 and "[DQ:handover_state]" in wholesale.stdout
                assert "[DQ:checkpoint_binding]" not in wholesale.stdout
            if stage == 2:
                stale = runtime.exec(run, 'kubectl exec deployment/relay -c worker -- wget -qO- -T 3 http://127.0.0.1:8080/recovery-id', timeout=12)
                assert stale.stdout.strip() == "retired"
                runtime.exec(run, (ROOT / "solutions/090/2.sh").read_text(), timeout=150)
                runtime.exec(run, check, timeout=25)
                runtime.exec(run, """kubectl exec deployment/relay -c worker -- sh -ec '
cp /run/recovery/recovery-id /tmp/www/static-recovery-id
ln -sfn /tmp/www/static-recovery-id /tmp/www/recovery-id
test "$(wget -qO- -T 3 http://127.0.0.1:8080/recovery-id)" = "$(cat /run/recovery/recovery-id)"
'""", timeout=12)
                detached = runtime.exec(run, check, check=False, timeout=25)
                assert detached.returncode != 0
                detail = detached.stdout + detached.stderr
                diagnostics = [line for line in detail.splitlines() if "[DQ:" in line]
                assert len(diagnostics) == 1 and "[DQ:relay_identity]" in diagnostics[0], detail
                log["matching_static_http_copy_rejected"] = True
            log["old_repair_diagnostics"] = sorted(failures)
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
        if number == 122:
            assert len(after.stdout.splitlines()) == 1 and "[DQ:publication]" in after.stdout
            log["old_whole_predicates"] = "PASS while the HTTP publication is stale"
        if number == 123:
            assert len(after.stdout.splitlines()) == 3
            for diagnostic in ("revision_north", "revision_south", "release_source"):
                assert f"[DQ:{diagnostic}]" in after.stdout
            log["maintenance_revision_healthy"] = True


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
