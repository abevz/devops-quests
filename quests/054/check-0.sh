set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
kubectl get application station -o json | jq -e '.status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/relay -- printenv ROUTE)" = north
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/relay --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
