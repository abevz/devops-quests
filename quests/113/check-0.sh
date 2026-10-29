set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
class=$(jq -r '.class // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
url=$(jq -r '.url // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
gateway=$(kubectl get gateway station -o json 2>/dev/null || true)
route=$(kubectl get httproute board -o json 2>/dev/null || true)
if ! test -n "$class" || ! jq -e --arg class "$class" '.spec.gatewayClassName==$class' <<<"$gateway" >/dev/null 2>&1; then printf '%s\n' 'gateway/station class = supplied private class: ✗ [DQ:class]'; failed=1; fi
check 'gateway/station Accepted=True at current generation [DQ:accepted]' '. as $gw | any(.status.conditions[]?;.type=="Accepted" and .status=="True" and .observedGeneration==$gw.metadata.generation)' "$gateway"
check 'httproute/board first parent = station [DQ:parent]' '.spec.parentRefs[0].name=="station"' "$route"
check 'httproute/board hostnames = [north.station.internal] [DQ:hostnames]' '.spec.hostnames==["north.station.internal"]' "$route"
check 'httproute/board first backend name = board [DQ:backend_name]' '.spec.rules[0].backendRefs[0].name=="board"' "$route"
check 'httproute/board first backend port = 8080 [DQ:backend_port]' '.spec.rules[0].backendRefs[0].port==8080' "$route"
check 'httproute/board a parent Accepted=True [DQ:parent_accepted]' 'any(.status.parents[]?;any(.conditions[]?;.type=="Accepted" and .status=="True"))' "$route"
check 'httproute/board a parent ResolvedRefs=True [DQ:parent_resolved]' 'any(.status.parents[]?;any(.conditions[]?;.type=="ResolvedRefs" and .status=="True"))' "$route"
check 'httproute/board one parent has both conditions [DQ:parent_both]' 'any(.status.parents[]?;any(.conditions[]?;.type=="Accepted" and .status=="True") and any(.conditions[]?;.type=="ResolvedRefs" and .status=="True"))' "$route"
if ! test -n "$url" || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 --header='Host: north.station.internal' "$url" 2>/dev/null)" = north-113; then printf '%s\n' 'matching Host response = north-113: ✗ [DQ:http]'; failed=1; fi
if test -n "$url" && timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 --header='Host: closed.station.internal' "$url" >/dev/null 2>&1; then printf '%s\n' 'other Host request fails: ✗ [DQ:wrong]'; failed=1; fi
exit "$failed"
