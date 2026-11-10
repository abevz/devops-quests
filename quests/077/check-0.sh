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
budget=$(kubectl get pdb board-budget -o json)
deployment=$(kubectl get deployment board -o json)
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
    identity=selector.get('matchLabels',{}).get('app')=='board' or any(e.get('key')=='app' and e.get('operator')=='In' and set(e.get('values',[]))=={'board'} for e in selector.get('matchExpressions',[]))
    same=identity and selected(labels,selector) and all(not selected(p['metadata'].get('labels',{}),selector) or p['metadata'].get('labels',{}).get('app')=='board' for p in pods)
    spec=budget['spec']
    if ('minAvailable' in spec)==('maxUnavailable' in spec):raise ValueError('exclusive budget')
    minimum=amount(spec['minAvailable'],count) if 'minAvailable' in spec else count-amount(spec['maxUnavailable'],count)
    ok=same and minimum>=1
except (ValueError,KeyError,TypeError,AttributeError):ok=False
sys.exit(not ok)
DQ_PDB
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
kubectl get deployment board -o json | jq -e '.spec.replicas==2 and .status.readyReplicas==2' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get pdb board-budget -o json | jq -e '.status.currentHealthy==2 and .status.desiredHealthy==1 and .status.disruptionsAllowed==1' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://board:8080)" = north-77
)
[ $? -eq 0 ] || failed=1
(
set -e
jq -e --slurpfile original /run/dq/facts/0/original-pod-uids.json --arg ns "$DQ_NAMESPACE" '.apiVersion=="policy/v1" and .kind=="Eviction" and .metadata.namespace==$ns and (.deleteOptions.preconditions.uid as $u | $original[0]|index($u)!=null)' eviction.json >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get pods -l app=board -o json | jq -e --slurpfile original /run/dq/facts/0/original-pod-uids.json --arg uid "$(jq -er .deleteOptions.preconditions.uid eviction.json)" '([.items[].metadata.uid]|index($uid))==null and ([.items[].metadata.uid as $u|select($original[0]|index($u)!=null)]|length)==1' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
jq -e --arg uid "$(jq -er .deleteOptions.preconditions.uid eviction.json)" 'index($uid)!=null' /run/dq/observations/evictions.json >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl auth can-i patch pods --subresource=status)" = no
)
[ $? -eq 0 ] || failed=1
exit "$failed"
