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
services=$(kubectl get service board-internal board-headless board-node -o json 2>/dev/null || true)
original=$(cat /run/dq/facts/0/service-contracts.json 2>/dev/null || true)
pods=$(kubectl get pods -l app=board -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 /dev/fd/4 /dev/fd/5 3<<<"$services" 4<<<"$original" 5<<<"$pods" <<'DQ_SERVICE_CONTRACTS'
import sys

from dq_check import read_argument as _dq_read_argument

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys
try:live=json.loads(sys.argv[1])['items'];original=json.loads(sys.argv[2]);pods=json.loads(sys.argv[3])['items']
except (ValueError,KeyError,TypeError):live=[];original=[];pods=[]
failed=False

def report(marker,ok):
    global failed
    if not ok:failed=True;print('Service contract: ✗ [DQ:'+marker+']')

def canonical(entries):
    result=[]
    for entry in entries:
        protocol=entry.get('protocol','TCP');target=entry.get('targetPort',entry['port'])
        if isinstance(target,str):
            targets=[p for p in pods if p.get('metadata',{}).get('labels',{}).get('app')=='board' and not p.get('metadata',{}).get('deletionTimestamp')]
            if not targets:raise ValueError('target Pods')
            numbers=[]
            for pod in targets:
                matches=[p['containerPort'] for c in pod['spec']['containers'] for p in c.get('ports',[]) if p.get('name')==target and p.get('protocol','TCP')==protocol]
                if len(matches)!=1:raise ValueError('named target')
                numbers+=matches
            if len(set(numbers))!=1:raise ValueError('target mismatch')
            target=numbers[0]
        result.append((entry.get('name',''),entry['port'],target,protocol,entry.get('nodePort'),entry.get('appProtocol')))
    return sorted(result,key=repr)

for name in ('board-internal','board-headless','board-node'):
    a=[x for x in live if x.get('metadata',{}).get('name')==name];b=[x for x in original if x.get('name')==name]
    for field in ('uid','type','clusterIP','clusterIPs','ports'):
        try:
            if len(a)!=1 or len(b)!=1:raise ValueError('service identity')
            actual=a[0]['metadata'].get('uid') if field=='uid' else a[0]['spec'].get(field)
            expected=b[0].get(field)
            ok=canonical(actual)==canonical(expected) if field=='ports' else actual==expected
        except (ValueError,KeyError,TypeError,AttributeError):ok=False
        report('contract_'+name.replace('-','_')+'_'+field.lower(),ok)
report('counts',len(live)==3 and len(original)==3)
by_name={x.get('metadata',{}).get('name'):x for x in live}
report('internal_type',by_name.get('board-internal',{}).get('spec',{}).get('type')=='ClusterIP')
report('internal_ip',by_name.get('board-internal',{}).get('spec',{}).get('clusterIP') not in (None,'None',''))
report('headless_ip',by_name.get('board-headless',{}).get('spec',{}).get('clusterIP')=='None')
report('node_type',by_name.get('board-node',{}).get('spec',{}).get('type')=='NodePort')
ports=[p for p in by_name.get('board-node',{}).get('spec',{}).get('ports',[]) if p.get('name')=='http']
report('node_port',len(ports)==1 and type(ports[0].get('nodePort')) is int and ports[0]['nodePort']>=30000)
sys.exit(failed)
DQ_SERVICE_CONTRACTS
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
set -euo pipefail
cd ~/quest
failed=0
selector_ok() {
  python3 -I - /dev/fd/3 /dev/fd/4 /dev/fd/5 /dev/fd/6 3<<<"$1" 4<<<"$pods" 5<<<"$2" 6<<<"$3" <<'DQ_SELECTOR'
import sys

from dq_check import read_argument as _dq_read_argument

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys
try:
    service,pods=json.loads(sys.argv[1]),json.loads(sys.argv[2])['items'];key,value=sys.argv[3:5]
    selector=service['spec']['selector']
    intended=[p for p in pods if p['metadata'].get('labels',{}).get(key)==value and not p['metadata'].get('deletionTimestamp')]
    from dq_check import selector_matches as _dq_matches

    def matches(p):
        return all(_dq_matches(p["metadata"].get("labels", {}), {"matchLabels": {k: v}}, dialect="pdb") for k, v in selector.items())
    ok=isinstance(selector,dict) and selector.get(key)==value and bool(intended) and all(matches(p) for p in intended) and all(not matches(p) or p['metadata'].get('labels',{}).get(key)==value for p in pods)
except (ValueError,KeyError,TypeError,AttributeError):ok=False
sys.exit(not ok)
DQ_SELECTOR
}
pods=$(timeout 2s kubectl get pods -o json 2>/dev/null || true)
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
internal=$(kubectl get service board-internal -o json 2>/dev/null || true)
headless=$(kubectl get service board-headless -o json 2>/dev/null || true)
nodeport=$(kubectl get service board-node -o json 2>/dev/null || true)
if ! selector_ok "$internal" app board; then printf '%s\n' 'service selector retains only the supplied board workload: ✗ [DQ:internal_selector]'; failed=1; fi
if ! selector_ok "$headless" app board; then printf '%s\n' 'service selector retains only the supplied board workload: ✗ [DQ:headless_selector]'; failed=1; fi
if ! selector_ok "$nodeport" app board; then printf '%s\n' 'service selector retains only the supplied board workload: ✗ [DQ:node_selector]'; failed=1; fi
exit "$failed"
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
set -euo pipefail
cd ~/quest
failed=0
nodeport=$(kubectl get service board-node -o json 2>/dev/null || true)
node=$(kubectl config view --minify -o json 2>/dev/null | jq -r '.clusters[0].cluster.server | sub("^https://";"") | split(":")[0]' 2>/dev/null || true)
port=$(jq -r '[.spec.ports[]? | select(.name=="http")][0].nodePort // ""' <<<"$nodeport" 2>/dev/null || true)
name=board-internal
  if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "http://$name:8080" 2>/dev/null)" = north-106; then printf '%s\n' "$name:8080 = north-106: ✗ [DQ:http_${name//-/_}]"; failed=1; fi
name=board-headless
  if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "http://$name:8080" 2>/dev/null)" = north-106; then printf '%s\n' "$name:8080 = north-106: ✗ [DQ:http_${name//-/_}]"; failed=1; fi
name=board-node
  if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "http://$name:8080" 2>/dev/null)" = north-106; then printf '%s\n' "$name:8080 = north-106: ✗ [DQ:http_${name//-/_}]"; failed=1; fi
if ! test -n "$node" || ! test -n "$port" || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "http://$node:$port" 2>/dev/null)" = north-106; then printf '%s\n' 'private node NodePort = north-106: ✗ [DQ:node_http]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
dns_answer_has() {
  local result=$1 expected=$2
  awk -v expected="$expected" '
    /^[[:space:]]*Name([[:space:]]+[0-9]+)?:/ { answer=1; next }
    answer && /^[[:space:]]*Address([[:space:]]+[0-9]+)?:/ {
      sub(/^[^:]*:[[:space:]]*/, ""); split($0, fields, /[[:space:]]+/)
      if (fields[1] == expected) found=1
    }
    END { exit !found }
  ' <<<"$result"
}
pod_ip=$(kubectl get pod -l app=board -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)
lookup=''
if test -n "$pod_ip"; then
  if ! lookup=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- nslookup -type=A "board-headless.$DQ_NAMESPACE.svc.cluster.local." 2>/dev/null); then lookup=''; fi
fi
if ! test -n "$pod_ip" || ! dns_answer_has "$lookup" "$pod_ip"; then printf '%s\n' 'board-headless DNS answer = board Pod IP: ✗ [DQ:headless_dns]'; failed=1; fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
