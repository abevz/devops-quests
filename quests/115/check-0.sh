set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
service=$(timeout 2s kubectl get service board -o json 2>/dev/null || true)
check selector 'service/board selector = app green' '.spec.selector=={app:"green"}' "$service"
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = green-115; then printf '%s\n' 'board:8080 = green-115: ✗ [DQ:http]'; failed=1; fi
exit "$failed"
