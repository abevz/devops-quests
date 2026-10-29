set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
uid=$(timeout 2s kubectl get deployment board -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
original=$(cat /run/dq/facts/0/original-deployment-uid 2>/dev/null || true)
if ! test -n "$uid" || ! test -n "$original" || ! test "$uid" = "$original"; then printf '%s\n' 'deployment/board UID = original-deployment-uid: ✗ [DQ:uid]'; failed=1; fi
if ! timeout 5s kubectl kustomize overlays/recovery > /tmp/rendered-overlay.yaml 2>/dev/null; then printf '%s\n' 'render overlays/recovery: ✗ [DQ:render]'; failed=1; fi
rendered=$(python3 -c 'import json,yaml; print(json.dumps(list(yaml.safe_load_all(open("/tmp/rendered-overlay.yaml")))))' 2>/dev/null || true)
cm=$(jq -c 'first(.[] | select(.kind=="ConfigMap")) // {}' <<<"$rendered" 2>/dev/null || true)
rendered_board=$(jq -c 'first(.[] | select(.kind=="Deployment")) // {}' <<<"$rendered" 2>/dev/null || true)
check cm_data 'rendered ConfigMap data = ROUTE north-108' '.data=={ROUTE:"north-108"}' "$cm"
check cm_name 'rendered ConfigMap name starts route-' '.metadata.name | startswith("route-")' "$cm"
name=$(jq -r '.metadata.name // ""' <<<"$cm" 2>/dev/null || true)
check rendered_replicas 'rendered Deployment replicas = 2' '.spec.replicas==2' "$rendered_board"
board=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
check live_replicas 'live board replicas = 2' '.spec.replicas==2' "$board"
check ready 'live board readyReplicas = 2' '.status.readyReplicas==2' "$board"
if ! test -n "$name" || ! jq -e --arg name "$name" '.spec.template.spec.containers[0].env==[{name:"ROUTE",valueFrom:{configMapKeyRef:{name:$name,key:"ROUTE"}}}]' <<<"$board" >/dev/null 2>&1; then printf '%s\n' 'board env = single ROUTE reference to rendered ConfigMap: ✗ [DQ:env]'; failed=1; fi
live_cm=$(timeout 2s kubectl get configmap "$name" -o json 2>/dev/null || true)
check live_data 'live ConfigMap data = ROUTE north-108' '.data=={ROUTE:"north-108"}' "$live_cm"
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-108; then printf '%s\n' 'board:8080 = north-108: ✗ [DQ:http]'; failed=1; fi
exit "$failed"
