set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
grep -Fx 'route must equal north' diagnosis.txt
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/route-worker --timeout=3s
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deploy/route-worker -c worker -- printenv ROUTE)" = north
)
[ $? -eq 0 ] || failed=1
exit "$failed"
