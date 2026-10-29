set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
url=$(jq -r '.url // ""' /run/dq/facts/0/ingress-target.json 2>/dev/null || true)
class=$(jq -r '.class // ""' /run/dq/facts/0/ingress-target.json 2>/dev/null || true)
ingress=$(kubectl get ingress board -o json 2>/dev/null || true)
if ! test -n "$class" || ! jq -e --arg class "$class" '.spec.ingressClassName==$class' <<<"$ingress" >/dev/null 2>&1; then printf '%s\n' 'ingress/board class = supplied private class: ✗ [DQ:ingress_class]'; failed=1; fi
check 'ingress/board first host = station.internal [DQ:host]' '.spec.rules[0].host=="station.internal"' "$ingress"
check 'ingress/board first path = / [DQ:path]' '.spec.rules[0].http.paths[0].path=="/"' "$ingress"
check 'ingress/board first pathType = Prefix [DQ:path_type]' '.spec.rules[0].http.paths[0].pathType=="Prefix"' "$ingress"
check 'ingress/board first backend = board:8080 [DQ:backend]' '.spec.rules[0].http.paths[0].backend.service=={name:"board",port:{number:8080}}' "$ingress"
if ! test -n "$url" || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 --header='Host: station.internal' "$url" 2>/dev/null)" = north-107; then printf '%s\n' 'matching Host response = north-107: ✗ [DQ:http]'; failed=1; fi
if test -n "$url" && timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 --header='Host: wrong.station.internal' "$url" >/dev/null 2>&1; then printf '%s\n' 'wrong Host request fails: ✗ [DQ:wrong]'; failed=1; fi
exit "$failed"
