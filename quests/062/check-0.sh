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
policy=$(kubectl get networkpolicy board-ingress -o json)
pods=$(kubectl get pods -l app=board -o json)
python3 -I - /dev/fd/3 /dev/fd/4 3<<<"$policy" 4<<<"$pods" <<'DQ_INGRESS_POLICY'
import sys

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys
def simple_selector(value, labels):
    if not isinstance(value,dict) or set(value)-{'matchLabels','matchExpressions'}:return False
    matches=value.get('matchLabels',{})
    clauses=value.get('matchExpressions',[])
    if not isinstance(matches,dict) or not isinstance(clauses,list):return False
    if set(matches)-set(labels) or any(e.get('key') not in labels for e in clauses):return False
    for key,expected in labels.items():
        allowed={matches[key]} if key in matches else None
        exclusions=set();exists=key in matches
        for clause in clauses:
            if clause['key']!=key:continue
            operator=clause.get('operator');values=clause.get('values',[])
            if operator=='In':
                if not values:return False
                allowed=set(values) if allowed is None else allowed & set(values)
                exists=True
            elif operator=='NotIn':exclusions.update(values)
            elif operator=='Exists':exists=True
            else:return False
        if allowed is None or not exists or allowed-exclusions!={expected}:return False
    return True

try:
    spec=json.loads(sys.argv[1])['spec'];pods=json.loads(sys.argv[2])['items']
    if not simple_selector(spec.get('podSelector'),{'app':'board'}):raise ValueError('protected workload')
    if set(spec.get('policyTypes',['Ingress']))!={'Ingress'} or spec.get('egress'):raise ValueError('policy direction')
    flows=set()
    for rule in spec.get('ingress',[]):
        if set(rule)-{'from','ports'} or not rule.get('from') or not rule.get('ports'):raise ValueError('unbounded rule')
        for peer in rule['from']:
            if set(peer)!={'podSelector'} or not simple_selector(peer['podSelector'],{'role':'dispatcher'}):raise ValueError('peer scope')
        for port in rule['ports']:
            if set(port)-{'protocol','port','endPort'} or port.get('protocol','TCP')!='TCP':raise ValueError('protocol')
            value=port.get('port')
            if type(value) is int:resolved=value
            elif isinstance(value,str):
                targets=[p for p in pods if p.get('metadata',{}).get('labels',{}).get('app')=='board' and not p.get('metadata',{}).get('deletionTimestamp')]
                if not targets:raise ValueError('target Pods')
                found=[]
                for pod in targets:
                    matches=[entry['containerPort'] for c in pod['spec']['containers'] for entry in c.get('ports',[]) if entry.get('name')==value and entry.get('protocol','TCP')=='TCP']
                    if len(matches)!=1:raise ValueError('port identity')
                    found+=matches
                if len(set(found))!=1:raise ValueError('port mismatch')
                resolved=found[0]
            else:raise ValueError('port')
            if port.get('endPort',resolved)!=resolved:raise ValueError('range')
            flows.add(resolved)
    ok=flows=={8080}
except (ValueError,KeyError,TypeError,AttributeError):ok=False
sys.exit(not ok)
DQ_INGRESS_POLICY
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
test "$(kubectl get networkpolicy -o json | jq '.items|length')" = 1
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/dispatcher -- wget -qO- -T 3 http://board:8080)" = north-62
)
[ $? -eq 0 ] || failed=1
(
set -e
if kubectl exec deployment/visitor -- wget -qO- -T 2 http://board:8080 >/dev/null 2>&1; then exit 1; fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
