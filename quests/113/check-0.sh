set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
class=$(jq -r '.class // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
url=$(jq -r '.url // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
gateway=$(kubectl get gateway station -o json 2>/dev/null || true)
route=$(kubectl get httproute board -o json 2>/dev/null || true)
if ! test -n "$class" || ! jq -e --arg class "$class" '.spec.gatewayClassName==$class' <<<"$gateway" >/dev/null 2>&1; then printf '%s\n' 'gateway/station class = supplied private class: ✗'; failed=1; fi
check 'gateway/station Accepted=True at current generation' '. as $gw | any(.status.conditions[]?;.type=="Accepted" and .status=="True" and .observedGeneration==$gw.metadata.generation)' "$gateway"
check 'httproute/board first parent = station' '.spec.parentRefs[0].name=="station"' "$route"
check 'httproute/board hostnames = [north.station.internal]' '.spec.hostnames==["north.station.internal"]' "$route"
check 'httproute/board first backend name = board' '.spec.rules[0].backendRefs[0].name=="board"' "$route"
check 'httproute/board first backend port = 8080' '.spec.rules[0].backendRefs[0].port==8080' "$route"
check 'httproute/board a parent Accepted=True' 'any(.status.parents[]?;any(.conditions[]?;.type=="Accepted" and .status=="True"))' "$route"
check 'httproute/board a parent ResolvedRefs=True' 'any(.status.parents[]?;any(.conditions[]?;.type=="ResolvedRefs" and .status=="True"))' "$route"
check 'httproute/board one parent has both conditions' 'any(.status.parents[]?;any(.conditions[]?;.type=="Accepted" and .status=="True") and any(.conditions[]?;.type=="ResolvedRefs" and .status=="True"))' "$route"
if ! test -n "$url" || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 --header='Host: north.station.internal' "$url" 2>/dev/null)" = north-113; then printf '%s\n' 'matching Host response = north-113: ✗'; failed=1; fi
if test -n "$url" && timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 --header='Host: closed.station.internal' "$url" >/dev/null 2>&1; then printf '%s\n' 'other Host request fails: ✗'; failed=1; fi
exit "$failed"
