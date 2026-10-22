set -euo pipefail
cd ~/quest
kubectl get application station -o json | jq -e '.status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null
test "$(kubectl exec deployment/relay -- printenv ROUTE)" = north
kubectl rollout status deployment/relay --timeout=3s >/dev/null
