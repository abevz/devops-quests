set -euo pipefail
cd ~/quest
kubectl get deployment board -o json | jq -e '.spec.template.spec.containers[0].resources.requests.cpu=="100m" and .spec.template.spec.containers[0].resources.limits.cpu=="200m" and .status.readyReplicas==2' >/dev/null
kubectl get hpa board -o json | jq -e '.spec.minReplicas==1 and .spec.maxReplicas==2 and .spec.metrics[0].resource.target.averageUtilization==50 and .status.currentReplicas==2 and .status.desiredReplicas==2 and any(.status.currentMetrics[]?;.resource.current.averageUtilization>50)' >/dev/null
