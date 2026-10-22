set -euo pipefail
cd ~/quest
kubectl patch deployment board --type=json -p '[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "100m"}]'
kubectl rollout status deployment/board --timeout=90s
for i in $(seq 1 90); do
 if kubectl get hpa board -o json | jq -e '.status.currentReplicas==2 and .status.desiredReplicas==2 and any(.status.currentMetrics[]?;.resource.current.averageUtilization>50)' >/dev/null; then break; fi
 sleep 2
done
kubectl rollout status deployment/board --timeout=90s
