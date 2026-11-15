set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
test "$(kubectl get pvc spool -o jsonpath='{.status.phase}')" = Bound
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/relay --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
