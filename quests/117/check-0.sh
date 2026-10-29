set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
observation=$(cat /run/dq/observations/static-pod.json 2>/dev/null || true)
check verified 'static observation verified = true' '.verified==true' "$observation"
check source 'static observation source = file' '.source=="file"' "$observation"
if ! jq -e --arg node "$DQ_NODE_NAME" '.node==$node' <<<"$observation" >/dev/null 2>&1; then printf '%s\n' 'static observation node = bay node: ✗ [DQ:node]'; failed=1; fi
uid=$(jq -r '.mirrorUID // ""' <<<"$observation" 2>/dev/null || true)
hash=$(jq -r '.configHash // ""' <<<"$observation" 2>/dev/null || true)
pod=$(timeout 2s kubectl get pod "static-board-$DQ_NODE_NAME" -o json 2>/dev/null || true)
if ! test -n "$uid" || ! jq -e --arg uid "$uid" '.metadata.uid==$uid' <<<"$pod" >/dev/null 2>&1; then printf '%s\n' 'mirror Pod UID = observed mirrorUID: ✗ [DQ:uid]'; failed=1; fi
if ! test -n "$hash" || ! jq -e --arg hash "$hash" '.metadata.annotations["kubernetes.io/config.mirror"]==$hash' <<<"$pod" >/dev/null 2>&1; then printf '%s\n' 'mirror Pod annotation = observed configHash: ✗ [DQ:hash]'; failed=1; fi
if ! jq -e --arg node "$DQ_NODE_NAME" '.spec.nodeName==$node' <<<"$pod" >/dev/null 2>&1; then printf '%s\n' 'mirror Pod node = bay node: ✗ [DQ:pod_node]'; failed=1; fi
check ready 'mirror Pod has a ready container' 'any(.status.containerStatuses[]?;.ready==true)' "$pod"
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-117; then printf '%s\n' 'board:8080 = north-117: ✗ [DQ:http]'; failed=1; fi
exit "$failed"
