set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
if ! jq -e '(.fault|type)=="string" and ((.fault|ascii_downcase|gsub("^[[:space:]]+|[[:space:]]+$";"")|gsub("[_[:space:]-]+";" ")) as $fault | ["selector","service selector","service selector mismatch","selector mismatch","selector fault"] | index($fault)!=null)' diagnosis.json >/dev/null 2>&1; then printf '%s\n' 'diagnosis.json fault = selector: ✗ [DQ:diagnosis]'; failed=1; fi
exit "$failed"
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
service=$(kubectl get service board -o json 2>/dev/null || true)
endpoints=$(kubectl get endpointslices -l kubernetes.io/service-name=board -o json 2>/dev/null || true)
if ! selector_ok "$service" app board; then printf '%s\n' 'service selector retains only the supplied board workload: ✗ [DQ:selector]'; failed=1; fi
check 'service/board EndpointSlice has a ready endpoint [DQ:endpoint]' 'any(.items[].endpoints[]?;.conditions.ready==true)' "$endpoints"
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
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
service=$(kubectl get service board -o json 2>/dev/null || true)
endpoints=$(kubectl get endpointslices -l kubernetes.io/service-name=board -o json 2>/dev/null || true)
ip=$(kubectl get pod -l app=board -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)
vip=$(jq -r '.spec.clusterIP // ""' <<<"$service" 2>/dev/null || true)
if ! test -n "$ip" || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "http://$ip:8080" 2>/dev/null)" = north-118; then printf '%s\n' 'board Pod IP:8080 = north-118: ✗ [DQ:pod]'; failed=1; fi
if ! test -n "$vip" || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "http://$vip:8080" 2>/dev/null)" = north-118; then printf '%s\n' 'board Service VIP:8080 = north-118: ✗ [DQ:vip]'; failed=1; fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
service=$(kubectl get service board -o json 2>/dev/null || true)
endpoints=$(kubectl get endpointslices -l kubernetes.io/service-name=board -o json 2>/dev/null || true)
ip=$(kubectl get pod -l app=board -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)
vip=$(jq -r '.spec.clusterIP // ""' <<<"$service" 2>/dev/null || true)
proxy=$(cat /run/dq/facts/0/proxy-observation.json 2>/dev/null || true)
check 'proxy observation ready = true [DQ:proxy_ready]' '.ready==true' "$proxy"
check 'proxy observation mode = iptables, nftables or ipvs [DQ:proxy_mode]' '.mode=="iptables" or .mode=="nftables" or .mode=="ipvs"' "$proxy"
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
