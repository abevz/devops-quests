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
exit "$failed"
