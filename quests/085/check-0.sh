set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
budget=$(kubectl get pdb relay -o json)
deployment=$(kubectl get deployment relay -o json)
pods=$(kubectl get pods -o json)
python3 -I - /dev/fd/3 /dev/fd/4 /dev/fd/5 3<<<"$budget" 4<<<"$deployment" 5<<<"$pods" <<'DQ_PDB'
import sys

from dq_check import read_argument as _dq_read_argument

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys,re

from dq_check import selector_matches as _dq_selected

def selected(labels, selector):
    return _dq_selected(labels, selector, dialect="pdb")

from dq_check import pdb_amount as amount
try:
    budget=json.loads(sys.argv[1]);deployment=json.loads(sys.argv[2]);pods=json.loads(sys.argv[3])['items']
    labels=deployment['spec']['template']['metadata']['labels'];selector=budget['spec']['selector'];count=deployment['spec']['replicas']
    if type(count) is not int or count<1:raise ValueError('replicas')
    # The selector must retain the workload identity, not merely match today's pods.
    identity=selector.get('matchLabels',{}).get('app')=='relay' or any(e.get('key')=='app' and e.get('operator')=='In' and set(e.get('values',[]))=={'relay'} for e in selector.get('matchExpressions',[]))
    same=identity and selected(labels,selector) and all(not selected(p['metadata'].get('labels',{}),selector) or p['metadata'].get('labels',{}).get('app')=='relay' for p in pods)
    spec=budget['spec']
    if ('minAvailable' in spec)==('maxUnavailable' in spec):raise ValueError('exclusive budget')
    minimum=amount(spec['minAvailable'],count) if 'minAvailable' in spec else count-amount(spec['maxUnavailable'],count)
    ok=same and minimum>=1
except (ValueError,KeyError,TypeError,AttributeError):ok=False
sys.exit(not ok)
DQ_PDB
# Compare the published source, reconciled live policy and retained identities.
git -C repository fetch origin main >/dev/null 2>&1
head=$(git -C repository rev-parse origin/main)
published=$(git -C repository show "$head:policies/budget.yaml")
resources=$(kubectl get deployment,service,pdb,application -o json)
python3 -I - /dev/fd/3 /dev/fd/4 "$head" 3<<<"$published" 4<<<"$resources" <<'DQ_MAINTENANCE_POLICY'
import json,sys,yaml
from pathlib import Path
from dq_check import read_argument,selector_matches,pdb_amount
messages={
 'maintenance_source':'Publish the policy at the retained source and wait for the same revision to synchronize with automatic self-healing.',
 'maintenance_identity':'Retain the baseline controllers, services, budgets and unselected original Pod identities.',
 'maintenance_scope':'Each policy must select its own original pool without covering the other pool.',
 'maintenance_health':'Restore two ready replicas and the original HTTP response in each pool.',
 'maintenance_policy':'Each separate budget must retain a healthy minimum of at least one Pod.',
}
failure='maintenance_source'
try:
    source=yaml.safe_load(read_argument(sys.argv[1]))
    objects={o['kind']+'/'+o['metadata']['name']:o for o in json.loads(read_argument(sys.argv[2]))['items']}
    baseline=json.loads(Path('/run/dq/facts/0/maintenance-baseline.json').read_text())
    failure='maintenance_identity'
    assert all(objects[key]['metadata']['uid']==uid for key,uid in baseline['identities'].items())
    failure='maintenance_source'
    app=objects['Application/maintenance'];spec=app['spec'];automated=spec['syncPolicy']['automated']
    assert spec['source']==baseline['source'] and spec['project']=='station'
    assert spec['destination']=={'server':'https://kubernetes.default.svc','namespace':app['metadata']['namespace']}
    assert automated.get('enabled') is not False and automated['selfHeal'] is True and automated['prune'] is True
    assert app['status']['sync']['status']=='Synced' and app['status']['sync']['revision']==sys.argv[3]
    assert source['apiVersion']=='policy/v1' and source['kind']=='PodDisruptionBudget' and source['metadata']['name']=='relay'
    assert source['spec']==objects['PodDisruptionBudget/relay']['spec']
    for name in baseline['pools']:
        d=objects['Deployment/'+name];budget=objects['PodDisruptionBudget/'+name]
        failure='maintenance_health'
        assert d['spec']['replicas']==2
        failure='maintenance_scope'
        selector=budget['spec']['selector'];labels=d['spec']['template']['metadata']['labels']
        identity=selector.get('matchLabels',{}).get('app')==name or any(e.get('key')=='app' and e.get('operator')=='In' and set(e.get('values',[]))=={name} for e in selector.get('matchExpressions',[]))
        assert identity and selector_matches(labels,selector,dialect='pdb')
        assert all(not selector_matches(objects['Deployment/'+other]['spec']['template']['metadata']['labels'],selector,dialect='pdb') for other in baseline['pools'] if other!=name)
        failure='maintenance_policy'
        bs=budget['spec'];assert ('minAvailable' in bs)!=('maxUnavailable' in bs)
        minimum=pdb_amount(bs['minAvailable'],2) if 'minAvailable' in bs else 2-pdb_amount(bs['maxUnavailable'],2)
        assert minimum>=1
except (AssertionError,KeyError,ValueError,TypeError,AttributeError,OSError,yaml.YAMLError):
    print(messages[failure]+' ✗ [DQ:'+failure+']')
    sys.exit(1)
DQ_MAINTENANCE_POLICY
if [ "$(kubectl auth can-i patch pods --subresource=status)" != no ]; then
 printf '%s\n' 'Player patches must not modify Pod status: ✗ [DQ:maintenance_authority]'
 exit 1
fi

) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_0]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
trap 'printf "%s\n" "Restore two ready replicas and the original HTTP response in each pool: ✗ [DQ:maintenance_health]"' ERR
kubectl get pdb relay -o json | jq -e '.status.currentHealthy>=2' >/dev/null
kubectl get deployment relay companion -o json | jq -e 'all(.items[];.spec.replicas==2 and .status.readyReplicas==2 and .status.observedGeneration==.metadata.generation)' >/dev/null
for pool in relay companion; do
 test "$(kubectl exec deployment/relay -- wget -qO- -T 3 "http://$pool:8080")" = "$pool-85"
done
trap - ERR
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_1]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
if ! kubectl get pdb relay -o json | jq -e '.status.disruptionsAllowed>=1' >/dev/null; then
 printf '%s\n' 'Wait for both budgets to observe the repaired generation and allow another voluntary disruption: ✗ [DQ:maintenance_allowance]'
 exit 1
fi
resources=$(kubectl get pods,pdb -o json)
python3 -I - /dev/fd/3 "$DQ_NAMESPACE" 3<<<"$resources" <<'DQ_MAINTENANCE_EVICTIONS'
import json,sys
from pathlib import Path
from dq_check import read_argument
messages={
 'maintenance_requests':'Save two policy/v1 requests for different original Pods with this namespace, matching names and UID preconditions.',
 'maintenance_identity':'Retain the baseline controllers, services, budgets and unselected original Pod identities.',
 'maintenance_evictions':'The server must observe an Eviction API outcome for each selected original UID; direct deletion and request files are insufficient.',
 'maintenance_health':'Restore two ready replicas and the original HTTP response in each pool.',
 'maintenance_allowance':'Wait for both budgets to observe the repaired generation and allow another voluntary disruption.',
}
failure='maintenance_requests'
try:
    items=json.loads(read_argument(sys.argv[1]))['items']
    baseline=json.loads(Path('/run/dq/facts/0/maintenance-baseline.json').read_text())
    requests=json.loads(Path('evictions.json').read_text());assert isinstance(requests,list) and len(requests)==2
    requested={}
    for request in requests:
        assert request['apiVersion']=='policy/v1' and request['kind']=='Eviction'
        assert request['metadata']['namespace']==sys.argv[2]
        uid=request['deleteOptions']['preconditions']['uid'];assert uid not in requested
        requested[uid]=request['metadata']['name']
    failure='maintenance_evictions'
    receipt=set(json.loads(Path('/run/dq/observations/evictions.json').read_text()))
    all_pods=[p for p in items if p['kind']=='Pod']
    for name,original in baseline['pools'].items():
        failure='maintenance_requests'
        uids={p['uid'] for p in original};chosen=uids & requested.keys()
        assert len(chosen)==1
        uid=chosen.pop()
        assert requested[uid]==next(p['name'] for p in original if p['uid']==uid)
        failure='maintenance_evictions'
        assert uid in receipt
        failure='maintenance_identity'
        assert all(p['metadata']['uid']!=uid for p in all_pods)
        live=[p for p in all_pods if p['metadata'].get('labels',{}).get('app')==name]
        assert len(uids & {p['metadata']['uid'] for p in live})==1
        failure='maintenance_health'
        assert len(live)==2
        assert all(not p['metadata'].get('deletionTimestamp') and any(c['type']=='Ready' and c['status']=='True' for c in p.get('status',{}).get('conditions',[])) for p in live)
        failure='maintenance_allowance'
        budget=next(p for p in items if p['kind']=='PodDisruptionBudget' and p['metadata']['name']==name)
        assert budget['status']['observedGeneration']==budget['metadata']['generation']
        assert budget['status']['currentHealthy']>=2 and budget['status']['disruptionsAllowed']>=1
except (AssertionError,KeyError,ValueError,TypeError,AttributeError,OSError):
    print(messages[failure]+' ✗ [DQ:'+failure+']')
    sys.exit(1)
DQ_MAINTENANCE_EVICTIONS

) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_2]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
