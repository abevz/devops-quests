set -euo pipefail
cd ~/quest
failed=0
board=$(kubectl get deployment board -o json 2>/dev/null || true)
uid=$(cat /run/dq/facts/0/original-deployment-uid 2>/dev/null || true)
check() { local label=$1 expression=$2; if ! jq -e --arg uid "$uid" "$expression" <<<"$board" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
if ! test -n "$uid"; then printf '%s\n' 'original-deployment-uid exists: ✗'; failed=1; fi
check 'deployment/board UID = original-deployment-uid' '.metadata.uid==$uid'
check 'deployment/board replicas = 2' '.spec.replicas==2'
check 'deployment/board strategy = RollingUpdate' '.spec.strategy.type=="RollingUpdate"'
check 'deployment/board rollingUpdate = {maxSurge:1,maxUnavailable:0}' '.spec.strategy.rollingUpdate=={maxSurge:1,maxUnavailable:0}'
check 'deployment/board readyReplicas = 2' '.status.readyReplicas==2'
check 'first container readiness HTTP port = 8080' '.spec.template.spec.containers[0].readinessProbe.httpGet.port==8080'
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-102; then printf '%s\n' 'board:8080 = north-102: ✗'; failed=1; fi
exit "$failed"
