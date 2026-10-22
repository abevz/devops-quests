set -euo pipefail
cd ~/quest
kubectl rollout status deployment/clock --timeout=3s
pod=$(kubectl get pods -l app=clock -o jsonpath='{.items[0].metadata.name}')
test "$(kubectl exec "$pod" -- cat /tmp/identity)" = "$pod"
kubectl exec "$pod" -- cat /tmp/clock | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
