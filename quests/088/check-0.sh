set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
kubectl get deployment relay -o json | jq -e '.spec.template.spec.containers[0].resources.limits.memory=="96Mi"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/relay --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
