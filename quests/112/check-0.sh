set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
board=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
hpa=$(timeout 2s kubectl get hpa board -o json 2>/dev/null || true)
check request 'board CPU request = 100m' '.spec.template.spec.containers[0].resources.requests.cpu=="100m"' "$board"
check limit 'board CPU limit = 200m' '.spec.template.spec.containers[0].resources.limits.cpu=="200m"' "$board"
check ready 'board readyReplicas = 2' '.status.readyReplicas==2' "$board"
check minimum 'HPA minReplicas = 1' '.spec.minReplicas==1' "$hpa"
check maximum 'HPA maxReplicas = 2' '.spec.maxReplicas==2' "$hpa"
check target 'HPA first metric averageUtilization = 50' '.spec.metrics[0].resource.target.averageUtilization==50' "$hpa"
check current 'HPA currentReplicas = 2' '.status.currentReplicas==2' "$hpa"
check desired 'HPA desiredReplicas = 2' '.status.desiredReplicas==2' "$hpa"
check metric 'HPA current resource metric utilization > 50' 'any(.status.currentMetrics[]?;.resource.current.averageUtilization>50)' "$hpa"
check active 'HPA ScalingActive = True' 'any(.status.conditions[]?;.type=="ScalingActive" and .status=="True")' "$hpa"
if ! timeout 2s kubectl top pods -l app=board --no-headers 2>/dev/null | grep -E '[0-9]+m' >/dev/null; then printf '%s\n' 'kubectl top pods shows CPU millicores: ✗ [DQ:top]'; failed=1; fi
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-112; then printf '%s\n' 'board:8080 = north-112: ✗ [DQ:http]'; failed=1; fi
exit "$failed"
