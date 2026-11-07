set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
budget=$(kubectl get pdb relay -o json)
deployment=$(kubectl get deployment relay -o json)
pods=$(kubectl get pods -o json)
python3 -I - /dev/fd/3 /dev/fd/4 /dev/fd/5 3<<<"$budget" 4<<<"$deployment" 5<<<"$pods" <<'DQ_PDB'
import sys

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys,re

def selected(labels,selector):
    if not isinstance(selector,dict):return False
    if not all(labels.get(k)==v for k,v in selector.get('matchLabels',{}).items()):return False
    for clause in selector.get('matchExpressions',[]):
        key=clause['key'];operator=clause['operator'];values=clause.get('values',[])
        if operator=='In':ok=key in labels and labels[key] in values
        elif operator=='NotIn':ok=key not in labels or labels[key] not in values
        elif operator=='Exists':ok=key in labels
        elif operator=='DoesNotExist':ok=key not in labels
        else:return False
        if not ok:return False
    return True

def amount(value,count):
    if type(value) is int and value>=0:return value
    if isinstance(value,str) and re.fullmatch(r'[0-9]+%',value):return (int(value[:-1])*count+99)//100
    raise ValueError('budget')
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
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get pdb relay -o json | jq -e '.status.currentHealthy>=2' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get pdb relay -o json | jq -e '.status.disruptionsAllowed>=1' >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
